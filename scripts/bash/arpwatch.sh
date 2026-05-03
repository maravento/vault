#!/bin/bash
# maravento.com
#
# ARP Watch
# Usage: sudo ./arpwatch.sh start | stop | status
# To exclude MAC addresses, list them in: /etc/arpwatch/exclude.txt
# Global log (all interfaces, ignoring exclude.txt): /var/log/arpwatch/arpwatch.log
# To uninstall: sudo apt remove --purge arpwatch && sudo rm -rf /etc/arpwatch /var/log/arpwatch

echo "ArpWatch starting. Wait..."
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

# LOCAL USER (multi-strategy detection with validation)
local_user=""
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi
echo "Using local user: $local_user"

# Capture local user UID once — used for DBUS notification path
local_uid=$(id -u "$local_user")

# check dependencies
pkgs='arpwatch libnotify-bin'
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
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
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
                    sudo -u "$local_user" \
                        DISPLAY=:0 \
                        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${local_uid}/bus" \
                        notify-send -i checkbox "ARPWatch" "$msg"
                    echo "$(date +'%F %T') $msg" >> "$UNIFIED_LOG"
                fi
            fi
        done &

        tail_pid=$!
        tail_pids+=("$tail_pid")
        echo "Background monitoring started for interface $iface with PID: $tail_pid"
    done

    printf '%s\n' "${tail_pids[@]}" >> "$TAIL_PID"

    if [[ -s "$ARPWATCH_PIDS" ]]; then
        printf '%s\n' "${tail_pids[@]}" > "$PIDFILE"
        echo "arpwatch service successfully started in background."
    else
        echo "❌ No arpwatch instances started successfully."
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

case "$1" in
    start)  start  ;;
    stop)   stop   ;;
    status) status ;;
    *)      echo "Usage: $0 {start|stop|status}" ;;
esac
