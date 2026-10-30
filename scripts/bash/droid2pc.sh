#!/bin/bash
# maravento.com
#
################################################################################
#
# droid2pc - Control and mirror Android devices to PC via scrcpy
# FILE: droid2pc.sh
#
# DESCRIPTION: Starts, stops or checks the status of scrcpy for an Android
# device connected via ADB/USB debugging. Not run as root.
#
# USAGE: ./droid2pc.sh { --start | --stop | --status }
#
# ENV: PID file under /run/user/<uid>/
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# dependencies
for dep in zenity adb scrcpy procps util-linux; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# validation -- integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Confirms the PID still belongs to scrcpy: the PID file can outlive its
# process and the number may have been reused by an unrelated program.
_pid_is_scrcpy() {
    local pid="$1"
    [[ -n "$pid" && "$pid" =~ $UH_UINT ]] || return 1
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == "scrcpy" ]]
}
show_error() {
    echo -e "$1"
    zenity --error --title="droid2pc Error" --text="$1" --timeout=5 2>/dev/null
    exit 1
}

show_info() {
    echo -e "$1"
    zenity --info --title="droid2pc" --text="$1" --timeout=5 2>/dev/null
}

PIDFILE="/run/user/$(id -u)/scrcpy.pid"

check_device() {
    adb start-server > /dev/null 2>&1
    if ! adb devices | grep -w "device" > /dev/null; then
        show_error "No ADB device connected.\n\nPlease:\n1. Enable USB debugging on your Android device\n2. Connect the phone via USB\n3. Authorize the PC on your device"
    fi
}

start() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$script_lock")
    exec 200>"$script_lock"
    if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
        exit 1
    fi

    check_device
    if pgrep -x scrcpy > /dev/null; then
        show_error "scrcpy is already running.\n\nClose the existing instance first."
    fi
    nohup scrcpy --max-size 1024 > /dev/null 2>&1 200>&- &
    local new_pid=$!
    echo "$new_pid" > "$PIDFILE"
    sleep 1
    if kill -0 "$new_pid" 2>/dev/null; then
        show_info "scrcpy started successfully (PID: $new_pid)"
    else
        rm -f "$PIDFILE"
        show_error "scrcpy failed to start.\n\nCheck that your Android device is connected and USB debugging is enabled."
    fi
}

stop() {
    if [ -f "$PIDFILE" ]; then
        local pid
        pid=$(cat "$PIDFILE")
        if _pid_is_scrcpy "$pid"; then
            kill "$pid" 2>/dev/null
            sleep 1
            _pid_is_scrcpy "$pid" && kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$PIDFILE"
        show_info "scrcpy stopped."
    else
        pkill -x scrcpy 2>/dev/null
        show_info "scrcpy stopped (or was not running)."
    fi
}

status() {
    local pid
    pid=$(pgrep -x scrcpy)
    if [ -n "$pid" ]; then
        show_info "scrcpy is running (PID: $pid)"
    else
        show_info "scrcpy is not running."
    fi
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: droid2pc start..."

case "${1:-}" in
    --start) start ;;
    --stop) stop ;;
    --status) status ;;
    *)
        show_error "Usage: $0 {--start|--stop|--status}"
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: droid2pc done"
