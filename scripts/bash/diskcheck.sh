#!/bin/bash
# maravento.com
#
################################################################################
#
# Disk Check Monitor
# Checks temperature, SMART status and degradation indicators on HDD, SSD and NVMe.
# Sends desktop alert and logs to syslog if any issue is detected.
# Requires: inxi, smartmontools
# Usage: sudo ./diskcheck.sh
# Cron Root: @daily /etc/scr/diskcheck.sh
# Log rotate: /etc/logrotate.d/diskcheck
#
################################################################################

echo "Check Disk Temp Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

set -uo pipefail

### LOG
DISKCHECK_LOG="/var/log/diskcheck.log"
touch "$DISKCHECK_LOG" 2>/dev/null || true
exec >> "$DISKCHECK_LOG" 2>&1

echo "----------------------------------------------------------------"
echo "$(date '+%Y-%m-%d %H:%M:%S') — Diskcheck start"
echo "----------------------------------------------------------------"

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

# check dependencies
pkgs='inxi smartmontools'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "Waiting for APT/DPKG locks to be released..."
    APT_LOCK_TIMEOUT=120
    APT_LOCK_ELAPSED=0
    APT_LOCK_FILES="/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
    while lsof $APT_LOCK_FILES >/dev/null 2>&1; do
        if [ "$APT_LOCK_ELAPSED" -ge "$APT_LOCK_TIMEOUT" ]; then
            echo "APT/DPKG locks still held after ${APT_LOCK_TIMEOUT}s. Aborting."
            exit 1
        fi
        echo "   Locks held, waiting... (${APT_LOCK_ELAPSED}s)"
        sleep 5
        APT_LOCK_ELAPSED=$((APT_LOCK_ELAPSED + 5))
    done
    dpkg --configure -a
    echo "Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "Error installing: $missing"
        exit 1
    fi
else
    echo "Dependencies OK"
fi

# check ppa
the_ppa=malcscott/ppa
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    if ! add-apt-repository -y ppa:$the_ppa >/dev/null 2>&1; then
        echo "WARNING: Failed to add PPA $the_ppa. hddtemp may not be available."
    else
        apt-get update -qq
        if ! apt-get install -y hddtemp >/dev/null 2>&1; then
            echo "WARNING: Failed to install hddtemp from PPA $the_ppa."
        fi
    fi
fi

# ---------------------------------------------------------------------
# LOGROTATE
# ---------------------------------------------------------------------
LOGROTATE_CONF=/etc/logrotate.d/diskcheck
if [ ! -f "$LOGROTATE_CONF" ]; then
    cat > "$LOGROTATE_CONF" << 'EOF'
/var/log/diskcheck.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF
    chmod 644 "$LOGROTATE_CONF"
    chown root:root "$LOGROTATE_CONF"
    echo "Logrotate config created: $LOGROTATE_CONF"
else
    echo "Logrotate config: OK"
fi

# ---------------------------------------------------------------------
# HELPER: send desktop notification + syslog
# ---------------------------------------------------------------------
_notify() {
    local user="$1"; shift
    local uid
    uid=$(id -u "$user")
    local bus="unix:path=/run/user/${uid}/bus"
    local xdg_runtime="/run/user/${uid}"
    local session_type
    session_type=$(loginctl show-session \
        "$(loginctl show-user "$user" 2>/dev/null | awk -F= '/^Sessions=/{print $2}')" \
        -p Type --value 2>/dev/null || echo "x11")
    if [[ "$session_type" == "wayland" ]]; then
        sudo -u "$user" \
            DBUS_SESSION_BUS_ADDRESS="$bus" \
            WAYLAND_DISPLAY=wayland-1 \
            XDG_RUNTIME_DIR="$xdg_runtime" \
            notify-send "$@" 2>/dev/null || true
    else
        sudo -u "$user" \
            DISPLAY=:0 \
            DBUS_SESSION_BUS_ADDRESS="$bus" \
            XDG_RUNTIME_DIR="$xdg_runtime" \
            notify-send "$@" 2>/dev/null || true
    fi
}

notify_alert() {
    local msg="$1"
    local icon="${2:-dialog-warning}"
    logger -t disktemp "$msg"
    echo "$msg"
    _notify "$local_user" -i "$icon" "DISK ALERT" "$msg" \
        || echo "  notify-send failed (no desktop session?)"
}

# ---------------------------------------------------------------------
# TEMPERATURE CHECK
# ---------------------------------------------------------------------
degrees=50

# option 1 (ssd sata and nvme)
TEMP_OUTPUT=$(inxi -xD | awk -v max="$degrees" '
    /temp:/ {
        for (i=1; i<=NF; i++) {
            if ($i == "temp:") {
                temp = $(i+1)+0
                if (temp > max)
                    print "ALERT: hard drive temperature is above: " temp "C"
            }
        }
    }
')
if [ -n "$TEMP_OUTPUT" ]; then
    notify_alert "$TEMP_OUTPUT" "checkbox"
fi

# option 2 (for some ssd sata and hdd - uncomment if needed)
#temperature=$(hddtemp /dev/sda --numeric)
#if [ $temperature -ge $degrees ]; then
#    notify_alert "ALERT: hard drive's temperature is above: $temperature" "checkbox"
#fi

# ---------------------------------------------------------------------
# SMART DISK HEALTH CHECK
# Detects HDD/SSD/NVMe degradation and alerts for timely replacement
# ---------------------------------------------------------------------
echo ""
echo "Check Disk SMART Health. Wait..."

# Alert thresholds
REALLOCATED_THRESHOLD=10   # reallocated sectors (sign of bad sectors)
PENDING_THRESHOLD=5        # sectors pending reallocation
UNCORRECTABLE_THRESHOLD=1  # uncorrectable errors (critical from the first one)

# Detect all disks in the system (HDD, SSD, NVMe)
DISKS=$(lsblk -dno NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}')

if [ -z "$DISKS" ]; then
    echo "No disks found"
else
    for DISK in $DISKS; do
        echo "Checking $DISK"
        DISK_ALERTS=0

        if ! smartctl -i "$DISK" &>/dev/null; then
            echo "$DISK: SMART not available or not supported"
            continue
        fi

        SMART_STATUS=$(smartctl -H "$DISK" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
        if [ "$SMART_STATUS" = "FAILED!" ]; then
            notify_alert "$DISK: SMART status FAILED. Replace immediately." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi

        # NVMe: uses its own attributes
        if echo "$DISK" | grep -q "nvme"; then
            CRITICAL=$(smartctl -A "$DISK" 2>/dev/null | grep -i "critical_warning" | awk '{print $2}')
            if [ -n "$CRITICAL" ] && [ "$CRITICAL" != "0x00" ] && [ "$CRITICAL" != "0" ]; then
                notify_alert "$DISK (NVMe): Critical warning detected ($CRITICAL). Check disk immediately." "drive-harddisk"
                DISK_ALERTS=$((DISK_ALERTS + 1))
            fi
            WEAR=$(smartctl -A "$DISK" 2>/dev/null | grep -i "percentage_used" | awk '{print $2}' | tr -d '%')
            if [ -n "$WEAR" ] && [ "$WEAR" -ge 90 ] 2>/dev/null; then
                notify_alert "$DISK (NVMe): Wear level at ${WEAR}%. Plan replacement soon." "drive-harddisk"
                DISK_ALERTS=$((DISK_ALERTS + 1))
            fi
            [ "$DISK_ALERTS" -eq 0 ] && echo "$DISK: OK"
            continue
        fi

        # HDD / SSD SATA: classic SMART attributes
        SMART_ATTRS=$(smartctl -A "$DISK" 2>/dev/null)
        REALLOCATED=$(echo "$SMART_ATTRS" | awk '/Reallocated_Sector_Ct/ {print $10}')
        PENDING=$(echo "$SMART_ATTRS" | awk '/Current_Pending_Sector/ {print $10}')
        UNCORRECTABLE=$(echo "$SMART_ATTRS" | awk '/Offline_Uncorrectable/ {print $10}')
        POWER_HOURS=$(echo "$SMART_ATTRS" | awk '/Power_On_Hours/ {print $10}')

        if [ -n "$REALLOCATED" ] && [ "$REALLOCATED" -ge "$REALLOCATED_THRESHOLD" ] 2>/dev/null; then
            notify_alert "$DISK: $REALLOCATED reallocated sectors detected. Disk degrading — plan replacement." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$PENDING" ] && [ "$PENDING" -ge "$PENDING_THRESHOLD" ] 2>/dev/null; then
            notify_alert "$DISK: $PENDING pending sectors. Possible imminent failure." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$UNCORRECTABLE" ] && [ "$UNCORRECTABLE" -ge "$UNCORRECTABLE_THRESHOLD" ] 2>/dev/null; then
            notify_alert "$DISK: $UNCORRECTABLE uncorrectable errors. Replace disk immediately." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$POWER_HOURS" ] && [ "$POWER_HOURS" -ge 40000 ] 2>/dev/null; then
            notify_alert "$DISK: ${POWER_HOURS}h of use. Consider replacement as preventive measure." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi

        [ "$DISK_ALERTS" -eq 0 ] && echo "$DISK: OK"
    done
fi

echo ""
echo "Check Disk Health Done."
