#!/bin/bash
# maravento.com
#
################################################################################
#
# ARP Watch
# Usage: sudo ./arpwatch.sh start | stop | status
# To exclude MAC addresses, list them in: /etc/arpwatch/exclude.txt
# Global log (all interfaces, ignoring exclude.txt):
#   /var/log/arpwatch/arpwatch.log
# To uninstall:
#   sudo apt remove --purge arpwatch
#   sudo rm -rf /etc/arpwatch /var/log/arpwatch
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# LOCAL USER detection
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
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

echo "ArpWatch starting. Wait..."

# Desktop notification helper (X11 and Wayland, silent if no desktop session)
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

# DEPENDENCIES
for dep in arpwatch libnotify-bin systemd iproute2 procps bsdutils coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

# Disable default systemd arpwatch service if it's enabled
if systemctl is-enabled --quiet arpwatch.service; then
    systemctl disable --now arpwatch.service
fi

LOGDIR="/var/log/arpwatch"
mkdir -p "$LOGDIR"
PIDFILE="/run/arpwatch-wrapper.pid"
TAIL_PID="/run/arpwatch-tail.pid"
ARPWATCH_PIDS="/run/arpwatch-instances.pid"
UNIFIED_LOG="$LOGDIR/arpwatch.log"
touch "$UNIFIED_LOG"

WHITELIST="/etc/arpwatch/exclude.txt"
mkdir -p /etc/arpwatch
[[ -f "$WHITELIST" ]] || touch "$WHITELIST"

start() {
    # prevent overlapping runs
    SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$SCRIPT_LOCK")
    exec 200>"$SCRIPT_LOCK"
    if ! flock -n 200; then
        echo "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    echo "Starting arpwatch on active interfaces..."

    if [[ -f "$PIDFILE" ]]; then
        echo "arpwatch is already running."
        return
    fi

    > "$ARPWATCH_PIDS"
    interfaces=$(ip -o link show | grep 'state UP' | cut -d: -f2 | tr -d ' ' | grep -v '^lo$')

    # Start arpwatch for each interface
    for iface in $interfaces; do
        LOGFILE="$LOGDIR/arpwatch_$iface.log"
        touch "$LOGFILE"

        if ! pgrep -f "arpwatch -i $iface" > /dev/null; then
            echo "Running: /usr/sbin/arpwatch -i $iface -f /var/lib/arpwatch/arp_$iface.dat -d"
            /usr/sbin/arpwatch -i "$iface" -f "/var/lib/arpwatch/arp_$iface.dat" -d >> "$LOGFILE" 2>&1 &
            arp_pid=$!

            # Use kill -0 to verify the process actually started
            sleep 0.3
            if kill -0 "$arp_pid" 2>/dev/null; then
                echo "arpwatch started on interface: $iface with PID: $arp_pid"
                echo "$arp_pid" >> "$ARPWATCH_PIDS"
            else
                echo "Failed to start arpwatch on interface $iface. Check $LOGFILE for details."
            fi
        else
            echo "arpwatch is already running for interface $iface"
        fi
    done

    # Monitor logs and send notifications
    tail_pids=()
    for iface in $interfaces; do
        LOGFILE="$LOGDIR/arpwatch_$iface.log"
        tail -n0 -F "$LOGFILE" | while read -r line; do
            if [[ "$line" =~ new\ station|changed\ ethernet|flip-flop|duplicate ]]; then
                mac=$(echo "$line" | grep -o -i -E '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}')
                if ! grep -iq "$mac" "$WHITELIST"; then
                    msg="[$iface] $line"
                    logger -t arpwatch "$msg"
                    echo "$(date +'%F %T') $msg" | tee -a "$UNIFIED_LOG"
                    _notify "$local_user" -i checkbox "ARPWatch" "$msg"
                fi
            fi
        done &

        tail_pid=$!
        tail_pids+=("$tail_pid")
        echo "Background monitoring started for interface $iface with PID: $tail_pid"
    done

    printf '%s\n' "${tail_pids[@]}" > "$TAIL_PID"

    if [[ -s "$ARPWATCH_PIDS" ]]; then
        printf '%s\n' "${tail_pids[@]}" > "$PIDFILE"
        echo "arpwatch service successfully started in background."
    else
        echo "No arpwatch instances started successfully."
        rm -f "$ARPWATCH_PIDS" "$TAIL_PID"
        exit 1
    fi
}

stop() {
    if [[ -f "$PIDFILE" ]]; then
        echo "Stopping arpwatch..."

        # Stop tail monitoring processes
        if [[ -f "$TAIL_PID" ]]; then
            while read -r pid; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null
                    sleep 0.5
                    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
                    echo "Stopped monitoring process: $pid"
                fi
            done < "$TAIL_PID"
            rm -f "$TAIL_PID"
        fi

        # Kill any tail processes watching arpwatch log files that may have outlived their subshell
        pkill -f "tail -n0 -F ${LOGDIR}/" 2>/dev/null || true

        # Stop arpwatch instances
        if [[ -f "$ARPWATCH_PIDS" ]]; then
            while read -r pid; do
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid" 2>/dev/null
                    sleep 0.5
                    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
                    echo "Stopped arpwatch process: $pid"
                fi
            done < "$ARPWATCH_PIDS"
            rm -f "$ARPWATCH_PIDS"
        fi

        script_real=$(realpath "$0")
        while read -r pid; do
            kill "$pid" 2>/dev/null && echo "Stopped arpwatch.sh process: $pid"
        done < <(pgrep -f "bash.*${script_real}.*start" 2>/dev/null)

        rm -f "$PIDFILE"
        echo "All arpwatch processes have been stopped."
    else
        echo "arpwatch is not running."
    fi
}

status() {
    if [[ -f "$PIDFILE" ]]; then
        echo "arpwatch script is running with PID(s): $(cat "$PIDFILE")"

        if [[ -f "$TAIL_PID" ]]; then
            echo "Monitoring process(es) running with PID(s): $(cat "$TAIL_PID")"
        else
            echo "Monitoring process is not running."
        fi

        if [[ -f "$ARPWATCH_PIDS" ]]; then
            echo "arpwatch instances running:"
            cat "$ARPWATCH_PIDS"
        else
            echo "No arpwatch instances are currently running."
        fi
    else
        echo "arpwatch is not running."
    fi
}

case "${1:-}" in
    start)  start  ;;
    stop)   stop   ;;
    status) status ;;
    *)      echo "Usage: $0 {start|stop|status}" ;;
esac
