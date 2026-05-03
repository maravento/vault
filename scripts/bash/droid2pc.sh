#!/bin/bash
# maravento.com
#
# droid2pc - Control and mirror Android devices to PC via scrcpy
#
# Compatible:
# Android 5.0 (API 21) or higher
#
# ⚠️ Requirements (run once):
# 1. Enable "Developer options" on your Android device.
#    → Settings > About phone > Tap "Build number" 7 times.
# 2. Enable "USB debugging" in Developer options.
# 3. Connect the phone via USB and authorize the PC when prompted.
# 4. Install required packages on Ubuntu:
#    sudo apt install adb scrcpy
#
# ✅ Usage:
#    ./droid2pc start   # Start scrcpy if device is connected
#    ./droid2pc stop    # Stop any running scrcpy instance
#    ./droid2pc status  # Check if scrcpy is running
#
# 🔒 Note: This script must NOT be run as root.

if [ "$(id -u)" -eq 0 ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

pkgs='adb scrcpy'
for pkg in $pkgs; do
    dpkg -s "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null || {
        echo "❌ '$pkg' is not installed. Run:"
        echo "   sudo apt install $pkg"
        exit 1
    }
done

PIDFILE="/run/user/$(id -u)/scrcpy.pid"

check_device() {
    adb start-server > /dev/null 2>&1
    if ! adb devices | grep -w "device" > /dev/null; then
        echo "❌ No ADB device connected."
        exit 1
    fi
}

start() {
    check_device
    if pgrep -x scrcpy > /dev/null; then
        echo "⚠️ scrcpy is already running."
        exit 1
    fi
    nohup scrcpy --max-size 1024 > /dev/null 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PIDFILE"
    sleep 1
    if kill -0 "$new_pid" 2>/dev/null; then
        echo "✅ scrcpy started (PID $new_pid)."
    else
        echo "❌ scrcpy failed to start."
        rm -f "$PIDFILE"
        exit 1
    fi
}

stop() {
    if [ -f "$PIDFILE" ]; then
        local pid
        pid=$(cat "$PIDFILE")
        if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
        fi
        rm -f "$PIDFILE"
        echo "🛑 scrcpy stopped."
    else
        pkill -x scrcpy && echo "🛑 scrcpy stopped (no PIDFILE)." || echo "ℹ️ scrcpy was not running."
    fi
}

status() {
    local pid
    pid=$(pgrep -x scrcpy)
    if [ -n "$pid" ]; then
        echo "✅ scrcpy is running (PID $pid)."
    else
        echo "ℹ️ scrcpy is not running."
    fi
}

case "$1" in
    start)  start  ;;
    stop)   stop   ;;
    status) status ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
