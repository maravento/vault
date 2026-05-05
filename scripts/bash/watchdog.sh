#!/bin/bash
# maravento.com
#
# Internet Watchdog Script
#
# This script monitors Internet connectivity by pinging a public IP (default: 1.1.1.1)
# every 60 seconds. It logs connection status, packet loss, and average latency
# to a file (`connection.log`). The script supports start/stop/status controls,
# runs safely in the background, and avoids multiple instances.
#
# Usage:
#   ./watchdog.sh start     # Launch watchdog in background
#   ./watchdog.sh status    # Check if watchdog is running
#   ./watchdog.sh stop      # Stop the running watchdog
#
# Log output:
#   connection.log
#   Format: [YYYY-MM-DD HH:MM:SS] Internet OK | Loss: X% | Avg latency: Y ms
#           or   [YYYY-MM-DD HH:MM:SS] Internet DOWN
#
# Note:
# - Target IP can be changed by editing the TARGET variable.
# - PID is tracked in /tmp/watchdog.pid
#
# Command to check real-time logs:
#   tail -f connection.log

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root"
fi

PIDFILE="/tmp/watchdog.pid"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOGFILE="$SCRIPT_DIR/connection.log"
TARGET="1.1.1.1"

start() {
    _pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -f "$PIDFILE" ] && [[ "$_pid" =~ ^[0-9]+$ ]] && kill -0 "$_pid" 2>/dev/null; then
        echo "[!] Watchdog already running (PID $_pid)"
        exit 1
    fi

    echo "[+] Starting watchdog in background..."
    (
        while true; do
            timestamp=$(date '+%F %T')
            result=$(ping -c 3 -W 2 "$TARGET")

            if echo "$result" | grep -q "0 received"; then
                echo "[$timestamp] Internet DOWN" >> "$LOGFILE"
            else
                loss=$(echo "$result" | grep -oP '\d+(?=% packet loss)')
                latency=$(echo "$result" | grep "rtt" | awk -F '/' '{print $5}')
                echo "[$timestamp] Internet OK | Loss: ${loss}% | Avg latency: ${latency} ms" >> "$LOGFILE"
            fi

            sleep 60
        done
    ) > /dev/null 2>&1 &

    echo $! > "$PIDFILE"
    echo "[✓] Watchdog started (PID $!)"
}

stop() {
    if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
            echo "[!] Invalid PID in $PIDFILE"
            rm -f "$PIDFILE"
            exit 1
        fi
        if kill "$PID" 2>/dev/null; then
            echo "[✓] Watchdog stopped (PID $PID)"
            rm -f "$PIDFILE"
        else
            echo "[!] Failed to stop watchdog (PID $PID may not exist)"
        fi
    else
        echo "[!] Watchdog is not running"
    fi
}

status() {
    _pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -f "$PIDFILE" ] && [[ "$_pid" =~ ^[0-9]+$ ]] && kill -0 "$_pid" 2>/dev/null; then
        echo "[✓] Watchdog is running (PID $_pid)"
    else
        echo "[✗] Watchdog is not running"
    fi
}

case "$1" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
