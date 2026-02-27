#!/bin/bash
# maravento.com
#
# Disk Check Monitor
# Checks temperature, SMART status and degradation indicators on HDD, SSD and NVMe.
# Sends desktop alert and logs to syslog if any issue is detected.
# Requires: libnotify-bin, inxi, smartmontools
# Usage: sudo ./diskcheck.sh
# Cron Root: @daily /etc/scr/diskcheck.sh >> /var/log/diskcheck.log 2>&1
# Log rotate: /etc/logrotate.d/diskcheck

echo "Check Disk Temp Starting. Wait..."
printf "\n"
# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi
# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi
# LOCAL USER
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
# Fallback
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi
# Desktop user UID (resolved after final local_user determination)
local_uid=$(id -u "$local_user")
echo "Desktop user: $local_user (uid=$local_uid)"

# check dependencies
pkgs='libnotify-bin inxi smartmontools'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DPKG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi
# check ppa
the_ppa=malcscott/ppa
if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    add-apt-repository -y ppa:$the_ppa >/dev/null 2>&1
    apt-get update -qq
    apt-get install -y hddtemp >/dev/null 2>&1
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
    missingok
    notifempty
}
EOF
    echo "✅ Logrotate config created: $LOGROTATE_CONF"
else
    echo "✅ Logrotate config: OK"
fi

# ---------------------------------------------------------------------
# HELPER: send desktop notification + syslog
# ---------------------------------------------------------------------
notify_alert() {
    local msg="$1"
    local icon="${2:-dialog-warning}"
    logger -t disktemp "$msg"
    echo "$msg"
    sudo -u "$local_user" \
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${local_uid}/bus \
        notify-send -i "$icon" "⚠️ DISK ALERT" "$msg" 2>/dev/null \
        || echo "   ⚠️ notify-send failed (no desktop session?)"
}

# Check desktop notification channel (terminal only)
sudo -u "$local_user" \
    DISPLAY=:0 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${local_uid}/bus \
    notify-send --version &>/dev/null \
    && echo "✅ Desktop notifications: OK" \
    || echo "⚠️ Desktop notifications: not available"

# ---------------------------------------------------------------------
# TEMPERATURE CHECK
# ---------------------------------------------------------------------
degrees=50

# option 1 (ssd sata and nvme)
TEMP_OUTPUT=$(inxi -xD | awk "/temp/ {if (\$2>$degrees) print \"ALERT: hard drive temperature is above: \" \$2}")
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
    echo "⚠️ No disks found"
else
    for DISK in $DISKS; do
        echo "→ Checking $DISK"
        DISK_ALERTS=0

        if ! smartctl -i "$DISK" &>/dev/null; then
            echo "   ⚠️ $DISK: SMART not available or not supported"
            continue
        fi

        SMART_STATUS=$(smartctl -H "$DISK" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
        if [ "$SMART_STATUS" = "FAILED!" ]; then
            notify_alert "🔴 $DISK: SMART status FAILED. Replace immediately." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi

        # NVMe: uses its own attributes
        if echo "$DISK" | grep -q "nvme"; then
            CRITICAL=$(smartctl -A "$DISK" 2>/dev/null | grep -i "critical_warning" | awk '{print $2}')
            if [ -n "$CRITICAL" ] && [ "$CRITICAL" != "0x00" ] && [ "$CRITICAL" != "0" ]; then
                notify_alert "🔴 $DISK (NVMe): Critical warning detected ($CRITICAL). Check disk immediately." "drive-harddisk"
                DISK_ALERTS=$((DISK_ALERTS + 1))
            fi
            WEAR=$(smartctl -A "$DISK" 2>/dev/null | grep -i "percentage_used" | awk '{print $2}' | tr -d '%')
            if [ -n "$WEAR" ] && [ "$WEAR" -ge 90 ] 2>/dev/null; then
                notify_alert "🟠 $DISK (NVMe): Wear level at ${WEAR}%. Plan replacement soon." "drive-harddisk"
                DISK_ALERTS=$((DISK_ALERTS + 1))
            fi
            [ "$DISK_ALERTS" -eq 0 ] && echo "   ✅ $DISK: OK"
            continue
        fi

        # HDD / SSD SATA: classic SMART attributes
        SMART_ATTRS=$(smartctl -A "$DISK" 2>/dev/null)
        REALLOCATED=$(echo "$SMART_ATTRS" | awk '/Reallocated_Sector_Ct/ {print $10}')
        PENDING=$(echo "$SMART_ATTRS" | awk '/Current_Pending_Sector/ {print $10}')
        UNCORRECTABLE=$(echo "$SMART_ATTRS" | awk '/Offline_Uncorrectable/ {print $10}')
        POWER_HOURS=$(echo "$SMART_ATTRS" | awk '/Power_On_Hours/ {print $10}')

        if [ -n "$REALLOCATED" ] && [ "$REALLOCATED" -ge "$REALLOCATED_THRESHOLD" ] 2>/dev/null; then
            notify_alert "🟠 $DISK: $REALLOCATED reallocated sectors detected. Disk degrading — plan replacement." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$PENDING" ] && [ "$PENDING" -ge "$PENDING_THRESHOLD" ] 2>/dev/null; then
            notify_alert "🟠 $DISK: $PENDING pending sectors. Possible imminent failure." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$UNCORRECTABLE" ] && [ "$UNCORRECTABLE" -ge "$UNCORRECTABLE_THRESHOLD" ] 2>/dev/null; then
            notify_alert "🔴 $DISK: $UNCORRECTABLE uncorrectable errors. Replace disk immediately." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$POWER_HOURS" ] && [ "$POWER_HOURS" -ge 40000 ] 2>/dev/null; then
            notify_alert "🟡 $DISK: ${POWER_HOURS}h of use. Consider replacement as preventive measure." "drive-harddisk"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi

        [ "$DISK_ALERTS" -eq 0 ] && echo "   ✅ $DISK: OK"
    done
fi

echo ""
echo "Check Disk Health Done."
