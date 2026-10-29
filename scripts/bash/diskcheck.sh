#!/bin/bash
# maravento.com
#
################################################################################
#
# Disk Check Monitor
# FILE: diskcheck.sh
# DESCRIPTION: Checks temperature, SMART status and degradation indicators on
# HDD, SSD and NVMe. Sends a desktop alert and logs to syslog on any issue.
# Requires: inxi, smartmontools, util-linux, libnotify-bin
#
# USAGE: sudo ./diskcheck.sh
# Intended to run periodically via root's crontab.
# Log rotate: /etc/logrotate.d/diskcheck
#
# LOG: /var/log/diskcheck.log, written to file and screen via tee
#      Rotation is self-installed by this script
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/diskcheck.log"
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# Start
log "EVENT: diskcheck start..."

# dependencies
for dep in inxi smartmontools util-linux libnotify-bin systemd coreutils grep mawk sudo software-properties-common apt bsdutils logrotate iproute2 libc-bin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: '$dep' is not installed -abort"
        exit 1
    fi
done

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            log "INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no interface with IPv4 -abort"
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

# local_user detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    log "ERROR: no local user; create one with sudo access -abort"
    exit 1
fi
log "INFO: using local user: $local_user"

# check ppa
the_ppa=malcscott/ppa
if ! dpkg -s hddtemp &>/dev/null; then
    check_ipv4_interfaces
    check_internet
    if ! add-apt-repository -y ppa:$the_ppa >/dev/null 2>&1; then
        log "WARNING: add PPA $the_ppa failed; hddtemp absent -alert"
    else
        apt-get update -qq
        if ! apt-get install -y hddtemp >/dev/null 2>&1; then
            log "WARNING: hddtemp install from $the_ppa failed -alert"
        fi
    fi
fi

# ------------------------------------------------------------------------------
# LOGROTATE
# ------------------------------------------------------------------------------

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
    logrotate_ok=$?
    chmod 644 "$LOGROTATE_CONF" || logrotate_ok=1
    chown root:root "$LOGROTATE_CONF" || logrotate_ok=1
    if [ "$logrotate_ok" -eq 0 ]; then
        log "INFO: logrotate config created: $(basename "$LOGROTATE_CONF")"
    else
        log "WARNING: cannot create logrotate config -alert"
    fi
else
    log "INFO: logrotate config OK"
fi

# ------------------------------------------------------------------------------
# ALERTS
# ------------------------------------------------------------------------------

# NOTIFY SEND
# Sends a desktop notification to another user, on X11 and on Wayland.
# Stays silent when that user has no graphical session open.
notify_send() {
    local target_user="$1"; shift
    [ -z "$target_user" ] && return 0
    local target_uid
    target_uid=$(id -u "$target_user" 2>/dev/null) || return 0
    local dbus_address="unix:path=/run/user/${target_uid}/bus"
    local xdg_runtime_dir="/run/user/${target_uid}"
    local session_type
    session_type=$(loginctl show-session \
        "$(loginctl show-user "$target_user" 2>/dev/null | awk -F= '/^Sessions=/{print $2}')" \
        -p Type --value 2>/dev/null || echo "x11")
    if [[ "$session_type" == "wayland" ]]; then
        sudo -u "$target_user" \
            DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
            WAYLAND_DISPLAY=wayland-1 \
            XDG_RUNTIME_DIR="$xdg_runtime_dir" \
            notify-send "$@" 2>/dev/null || true
    else
        sudo -u "$target_user" \
            DISPLAY=:0 \
            DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
            XDG_RUNTIME_DIR="$xdg_runtime_dir" \
            notify-send "$@" 2>/dev/null || true
    fi
}

# NOTIFY ALERT
# Writes the message to syslog and to the log, then raises the desktop alert
notify_alert() {
    local msg="$1"
    local icon="${2:-dialog-warning}"
    local detail="${3:-$msg}" action="${4:-}" alert_line alert_log
    while IFS= read -r alert_line; do
        [ -n "$alert_line" ] || continue
        if [ -n "$action" ]; then
            alert_log="INFO: $alert_line"
        else
            alert_log="WARNING: ${alert_line#ALERT: } -alert"
        fi
        logger -t disktemp "$(date '+%Y-%m-%d %H:%M:%S') $alert_log"
        log "$alert_log"
    done <<< "$detail"
    if [ -n "$action" ]; then
        alert_log="WARNING: $action -alert"
        logger -t disktemp "$(date '+%Y-%m-%d %H:%M:%S') $alert_log"
        log "$alert_log"
    fi
    notify_send "$local_user" -i "$icon" "DISK ALERT" "$msg" \
        || log "WARNING: desktop notification failed -alert"
}

# ------------------------------------------------------------------------------
# TEMPERATURE CHECK
# ------------------------------------------------------------------------------

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
    notify_alert "$TEMP_OUTPUT" "checkbox" "${TEMP_OUTPUT//ALERT: hard drive temperature is above:/disk temperature above limit:}"
fi

# option 2 (for some ssd sata and hdd - uncomment if needed)
#temperature=$(hddtemp /dev/sda --numeric)
#if [ $temperature -ge $degrees ]; then
# notify_alert "ALERT: hard drive's temperature is above: $temperature" "checkbox"
#fi

# ------------------------------------------------------------------------------
# SMART HEALTH
# ------------------------------------------------------------------------------

# Detects HDD/SSD/NVMe degradation and alerts for timely replacement
log "EVENT: Check Disk SMART Health. Wait..."

# Alert thresholds
REALLOCATED_THRESHOLD=10 # reallocated sectors (sign of bad sectors)
PENDING_THRESHOLD=5 # sectors pending reallocation
UNCORRECTABLE_THRESHOLD=1 # uncorrectable errors (critical from the first one)

# Detect all disks in the system (HDD, SSD, NVMe)
DISKS=$(lsblk -dno NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}')

if [ -z "$DISKS" ]; then
    log "INFO: no disks found -skip"
else
    for DISK in $DISKS; do
        log "EVENT: Checking $DISK"
        DISK_ALERTS=0

        if ! smartctl -i "$DISK" &>/dev/null; then
            log "INFO: ${DISK##*/}: SMART unavailable or unsupported -skip"
            continue
        fi

        SMART_STATUS=$(smartctl -H "$DISK" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
        if [ "$SMART_STATUS" = "FAILED!" ]; then
            notify_alert "$DISK: SMART status FAILED. Replace immediately." "drive-harddisk" "${DISK##*/}: SMART failed; replace immediately"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi

        # NVMe: uses its own attributes
        if echo "$DISK" | grep -q "nvme"; then
            CRITICAL=$(smartctl -A "$DISK" 2>/dev/null | awk -F: '/Critical Warning/{gsub(/ /,"",$2);print $2}')
            if [ -n "$CRITICAL" ] && [ "$CRITICAL" != "0x00" ] && [ "$CRITICAL" != "0" ]; then
                notify_alert "$DISK (NVMe): Critical warning detected ($CRITICAL). Check disk immediately." "drive-harddisk" "${DISK##*/}: NVMe critical warning=$CRITICAL" "${DISK##*/}: check disk immediately"
                DISK_ALERTS=$((DISK_ALERTS + 1))
            fi
            WEAR=$(smartctl -A "$DISK" 2>/dev/null | awk -F: '/Percentage Used/{gsub(/[ %]/,"",$2);print $2}')
            if [ -n "$WEAR" ] && [ "$WEAR" -ge 90 ] 2>/dev/null; then
                notify_alert "$DISK (NVMe): Wear level at ${WEAR}%. Plan replacement soon." "drive-harddisk" "${DISK##*/}: wear=${WEAR}%" "${DISK##*/}: plan replacement soon"
                DISK_ALERTS=$((DISK_ALERTS + 1))
            fi
            [ "$DISK_ALERTS" -eq 0 ] && log "INFO: ${DISK##*/}: OK"
            continue
        fi

        # HDD / SSD SATA: classic SMART attributes
        SMART_ATTRS=$(smartctl -A "$DISK" 2>/dev/null)
        REALLOCATED=$(echo "$SMART_ATTRS" | awk '/Reallocated_Sector_Ct/ {print $10}')
        PENDING=$(echo "$SMART_ATTRS" | awk '/Current_Pending_Sector/ {print $10}')
        UNCORRECTABLE=$(echo "$SMART_ATTRS" | awk '/Offline_Uncorrectable/ {print $10}')
        POWER_HOURS=$(echo "$SMART_ATTRS" | awk '/Power_On_Hours/ {print $10}')

        if [ -n "$REALLOCATED" ] && [ "$REALLOCATED" -ge "$REALLOCATED_THRESHOLD" ] 2>/dev/null; then
            notify_alert "$DISK: $REALLOCATED reallocated sectors detected. Disk degrading -- plan replacement." "drive-harddisk" "${DISK##*/}: reallocated sectors=$REALLOCATED" "${DISK##*/}: disk degrading; plan replacement"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$PENDING" ] && [ "$PENDING" -ge "$PENDING_THRESHOLD" ] 2>/dev/null; then
            notify_alert "$DISK: $PENDING pending sectors. Possible imminent failure." "drive-harddisk" "${DISK##*/}: pending sectors=$PENDING" "${DISK##*/}: possible imminent failure"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$UNCORRECTABLE" ] && [ "$UNCORRECTABLE" -ge "$UNCORRECTABLE_THRESHOLD" ] 2>/dev/null; then
            notify_alert "$DISK: $UNCORRECTABLE uncorrectable errors. Replace disk immediately." "drive-harddisk" "${DISK##*/}: uncorrectable errors=$UNCORRECTABLE" "${DISK##*/}: replace disk immediately"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi
        if [ -n "$POWER_HOURS" ] && [ "$POWER_HOURS" -ge 40000 ] 2>/dev/null; then
            notify_alert "$DISK: ${POWER_HOURS}h of use. Consider replacement as preventive measure." "drive-harddisk" "${DISK##*/}: hours of use=$POWER_HOURS" "${DISK##*/}: consider preventive replacement"
            DISK_ALERTS=$((DISK_ALERTS + 1))
        fi

        [ "$DISK_ALERTS" -eq 0 ] && log "INFO: ${DISK##*/}: OK"
    done
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
log "EVENT: diskcheck done"
