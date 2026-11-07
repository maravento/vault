#!/bin/bash
# maravento.com
#
################################################################################
#
# Internet Watchdog Script
# FILE: watchdog.sh
#
# DESCRIPTION:
# Monitors Internet connectivity by periodically pinging a public IP and
# logs connection status, packet loss and average latency. Runs safely in
# the background and avoids multiple instances.
#
# USAGE:
# ./watchdog.sh {--start|--stop|--status}
#
# LOG: connection.log, next to this script
#      PID file under /run/user/<uid>/watchdog.pid
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# dependencies
for dep in libnotify-bin iputils-ping util-linux; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# validation -- integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
# Desktop notification helper (X11 and Wayland, silent if no desktop session)
# desktop notification to the current user (X11 and Wayland, no sudo)
notify_send_self() {
    local current_uid
    current_uid=$(id -u)
    local dbus_address="unix:path=/run/user/${current_uid}/bus"
    local xdg_runtime_dir="/run/user/${current_uid}"
    local session_type
    session_type=$(loginctl show-session \
        "$(loginctl show-user "$(id -un)" 2>/dev/null | awk -F= '/^Sessions=/{print $2}')" \
        -p Type --value 2>/dev/null || echo "x11")
    if [[ "$session_type" == "wayland" ]]; then
        DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        WAYLAND_DISPLAY=wayland-1 \
        XDG_RUNTIME_DIR="$xdg_runtime_dir" \
        notify-send "$@" 2>/dev/null || true
    else
        DISPLAY=:0 \
        DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
        XDG_RUNTIME_DIR="$xdg_runtime_dir" \
        notify-send "$@" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

RUN_DIR="/run/user/${UID}"
mkdir -p "$RUN_DIR"
PIDFILE="${RUN_DIR}/watchdog.pid"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOGFILE="$SCRIPT_DIR/connection.log"
TARGET="1.1.1.1"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# PID CHECK
# Check whether the recorded process belongs to this daemon
# Returns 0 for this daemon, 1 for another process, 2 if unreadable
daemon_alive() {
    local pid="$1" args=() self i
    [ -n "$pid" ] || return 1
    { mapfile -d '' -t args < "/proc/$pid/cmdline"; } 2>/dev/null || return 2
    [ "${#args[@]}" -gt 0 ] || return 2
    self="$(basename -- "$0")"
    case "$(basename -- "${args[0]:-}")" in
        "$self") i=0 ;;
        bash|sh) i=1 ;;
        *) return 1 ;;
    esac
    [ "$(basename -- "${args[i]:-}")" = "$self" ] || return 1
    [ "${args[i+1]:-}" = --start ]
}

start() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    exec 200>"$script_lock"
    if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
        exit 1
    fi

    watchdog_pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -f "$PIDFILE" ] && [[ "$watchdog_pid" =~ $UH_UINT ]] && daemon_alive "$watchdog_pid"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: watchdog already running (PID $watchdog_pid) -abort" >&2
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: starting watchdog in background..."
    (
        while true; do
            timestamp=$(date '+%F %T')
            result=$(ping -c 3 -W 2 "$TARGET")
            ping_status=$?

            if echo "$result" | grep -q "0 received" || [ "$ping_status" -ge 2 ]; then
                echo "[$timestamp] Internet DOWN" >> "$LOGFILE"
                notify_send_self -i network-error -u critical "Watchdog" "Internet DOWN"
            else
                loss=$(echo "$result" | grep -oP '\d+(?=% packet loss)')
                latency=$(echo "$result" | grep -E "rtt|round-trip" | sed 's/.*=\s*//' | awk -F '/' '{print $2}')
                latency="${latency:-N/A}"
                echo "[$timestamp] Internet OK | Loss: ${loss}% | Avg latency: ${latency} ms" >> "$LOGFILE"
            fi

            sleep 60
        done
    ) > /dev/null 2>&1 &

    echo $! > "$PIDFILE"
    sleep 0.2
    if ! daemon_alive "$(cat "$PIDFILE")"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: watchdog failed to start -abort" >&2
        rm -f "$PIDFILE"
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: watchdog started (PID $(cat "$PIDFILE"))"
}

stop() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ! [[ "$PID" =~ $UH_UINT ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid PID in $(basename "$PIDFILE") -abort" >&2
            rm -f "$PIDFILE"
            exit 1
        fi
        if [ ! -d "/proc/$PID" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: watchdog is not running"
        else
            daemon_alive "$PID"
            alive_rc=$?
            if [ "$alive_rc" -eq 2 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot verify watchdog PID $PID -abort" >&2
                exit 1
            elif [ "$alive_rc" -eq 1 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: PID $PID is not the watchdog"
            elif ! kill "$PID" 2>/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot send stop signal (PID $PID) -abort" >&2
                exit 1
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: sent stop signal to watchdog (PID $PID)"
                rm -f "$PIDFILE"
            fi
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: watchdog is not running"
    fi
}

status() {
    watchdog_pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -f "$PIDFILE" ] && [[ "$watchdog_pid" =~ $UH_UINT ]] && daemon_alive "$watchdog_pid"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: watchdog is running (PID $watchdog_pid)"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: watchdog is not running"
    fi
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: watchdog start..."

case "${1:-}" in
    --start) start ;;
    --stop) stop ;;
    --status) status ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        echo "Usage: $0 {--start|--stop|--status}"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: watchdog done"
