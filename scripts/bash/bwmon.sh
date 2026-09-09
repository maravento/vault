#!/bin/bash
# maravento.com
#
################################################################################
#
# bwmon - Bandwidth Watchdog
# Source: https://github.com/sivel/speedtest-cli
#
# Runs a speedtest and alerts (syslog + log file + desktop notification, if
# a desktop session is available) when download/upload falls below the
# configured minimum (dlmin/ulmin below, user-editable). Exits 1 if either
# value is below the minimum, 0 otherwise -- usable as a cron watchdog.
#
# Usage:
# Add this script to your crontab to run periodically, e.g. every 30 minutes:
# */30 * * * * /path_to/bwmon.sh
#
# Log file: /var/log/bwmon.log
#
################################################################################

set -uo pipefail

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# local_user detection (target for the desktop notification, if any)
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
local_user=$(detect_local_user || true)

# logging
log_file="/var/log/bwmon.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# desktop notification to another user (X11 and Wayland, silent if no session)
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

log "bwmon start..."

# dependencies
for dep in speedtest-cli libnotify-bin systemd util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

# check internet
check_internet() {
    local max_attempts="${1:-24}" attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            log "INFO: internet is available"
            return 0
        fi
        log "INFO: waiting for internet ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

if ! check_internet; then
    log "ERROR: no internet connection -- abort"
    exit 1
fi

# VARIABLES (user-editable)
# Minimum Download value (Mbit/s)
dlmin="1.00"
# Minimum Upload value (Mbit/s)
ulmin="1.00"

# SPEEDTEST
log "Running speedtest (this may take ~30s)..."
resume=$(speedtest-cli --secure --simple 2>&1)

if ! echo "$resume" | grep -q "^Download:"; then
    log "ERROR: speedtest-cli failed or returned unexpected output: $resume"
    exit 1
fi

dl=$(echo "$resume" | grep "^Download:")
ul=$(echo "$resume" | grep "^Upload:")

dlvalue=$(echo "$dl" | awk '{print $2}')
ulvalue=$(echo "$ul" | awk '{print $2}')
dlmb=$(echo "$dl" | awk '{print $3}')
ulmb=$(echo "$ul" | awk '{print $3}')

if [ -z "$dlvalue" ] || [ -z "$ulvalue" ]; then
    log "ERROR: Could not parse speedtest output: $resume"
    exit 1
fi

# speedtest-cli switches to Gbit/s above ~1000 Mbit/s which broke the unit check
normalize_to_mbit() {
    local value="$1"
    local unit="$2"
    if [[ "$unit" == "Gbit/s" ]]; then
        echo "$value" | awk '{printf "%.2f", $1 * 1000}'
    else
        echo "$value"
    fi
}

dlvalue_mbit=$(normalize_to_mbit "$dlvalue" "$dlmb")
ulvalue_mbit=$(normalize_to_mbit "$ulvalue" "$ulmb")

# Logs + syslog on failure, returns 1 if below minimum
check_metric() {
    local label="$1" value="$2" unit="$3" min="$4" mbit="$5"
    if (($(echo "$mbit $min" | awk '{print ($1 < $2)}'))); then
        log "WARNING: $label slow: $value $unit < $min Mbit/s (min value)"
        logger -t bwmon "WARNING: $label slow: $value $unit < $min Mbit/s (min value)"
        return 1
    fi
    log "$label OK: $value $unit (min: $min Mbit/s)"
    return 0
}

below_threshold=0
check_metric "Download" "$dlvalue" "$dlmb" "$dlmin" "$dlvalue_mbit" || below_threshold=1
check_metric "Upload" "$ulvalue" "$ulmb" "$ulmin" "$ulvalue_mbit" || below_threshold=1

if [ "$below_threshold" -eq 1 ]; then
    notify_send "$local_user" -i network-error "Bandwidth Watchdog" \
        "Speed below minimum: Download ${dlvalue} ${dlmb}, Upload ${ulvalue} ${ulmb}"
fi

log "Full result: $resume"
log "bwmon done at: $(date)"
exit "$below_threshold"
