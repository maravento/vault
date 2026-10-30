#!/bin/bash
# maravento.com
#
################################################################################
#
# bwmon - Bandwidth Watchdog
# FILE: bwmon.sh
# Source: https://github.com/sivel/speedtest-cli
#
# DESCRIPTION: Runs a speedtest and alerts (syslog + log file + desktop
# notification, if a desktop session is available) when download/upload falls
# below the configured minimum (dlmin/ulmin below, user-editable). Exits 1 if
# either value is below the minimum, 0 otherwise -- usable as a cron watchdog.
#
# USAGE:
# Add this script to your crontab to run periodically, e.g. every 30 minutes:
# */30 * * * * /path_to/bwmon.sh
#
# LOG: /var/log/bwmon.log
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

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
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
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
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

log "EVENT: bwmon start..."

# dependencies
for dep in speedtest-cli libnotify-bin systemd util-linux iproute2 libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
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

check_ipv4_interfaces
check_internet

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# User-editable thresholds, in Mbit/s
# Minimum Download value (Mbit/s)
dlmin="1.00"
# Minimum Upload value (Mbit/s)
ulmin="1.00"

# ------------------------------------------------------------------------------
# SPEEDTEST
# ------------------------------------------------------------------------------

# Measure the current download and upload speeds
log "EVENT: Running speedtest (this may take ~30s)..."
resume=$(speedtest-cli --secure --simple 2>&1)

if ! echo "$resume" | grep -q "^Download:"; then
    log "ERROR: speedtest-cli failed: ${resume//$'\n'/ | } -abort"
    exit 1
fi

dl=$(echo "$resume" | grep "^Download:")
ul=$(echo "$resume" | grep "^Upload:")

dlvalue=$(echo "$dl" | awk '{print $2}')
ulvalue=$(echo "$ul" | awk '{print $2}')
dlmb=$(echo "$dl" | awk '{print $3}')
ulmb=$(echo "$ul" | awk '{print $3}')

if [ -z "$dlvalue" ] || [ -z "$ulvalue" ]; then
    log "ERROR: could not parse speedtest output: ${resume//$'\n'/ | } -abort"
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
        log "WARNING: $label slow: $value $unit < $min Mbit/s -alert"
        logger -t bwmon "WARNING: $label slow: $value $unit < $min Mbit/s -alert"
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

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: bwmon done"
exit "$below_threshold"
