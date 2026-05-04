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

if ! command -v zenity &>/dev/null; then
    echo "Error: zenity is required but not installed."
    exit 1
fi

show_error() {
    echo -e "$1"
    zenity --error --title="droid2pc Error" --text="$1" --timeout=5 2>/dev/null
    exit 1
}

show_info() {
    echo -e "$1"
    zenity --info --title="droid2pc" --text="$1" --timeout=5 2>/dev/null
}

pkgs='adb scrcpy'
for pkg in $pkgs; do
    dpkg -s "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null || {
        show_error "'$pkg' is not installed.\n\nRun: sudo apt install adb scrcpy"
    }
done

PIDFILE="/run/user/$(id -u)/scrcpy.pid"

check_device() {
    adb start-server > /dev/null 2>&1
    if ! adb devices | grep -w "device" > /dev/null; then
        show_error "No ADB device connected.\n\nPlease:\n1. Enable USB debugging on your Android device\n2. Connect the phone via USB\n3. Authorize the PC on your device"
    fi
}

start() {
    check_device
    if pgrep -x scrcpy > /dev/null; then
        show_error "scrcpy is already running.\n\nClose the existing instance first."
    fi
    nohup scrcpy --max-size 1024 > /dev/null 2>&1 &
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
        if [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]; then
            kill "$pid" 2>/dev/null
            sleep 1
            kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
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

case "$1" in
    start)  start  ;;
    stop)   stop   ;;
    status) status ;;
    *)
        show_error "Usage: $0 {start|stop|status}"
        ;;
esac
