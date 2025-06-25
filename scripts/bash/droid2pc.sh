#!/bin/bash
#
# droid2pc - Control and mirror Android devices to PC via scrcpy
#
# This script provides start/stop/status commands for scrcpy,
# ensuring only one instance runs at a time and verifying that
# an Android device is properly connected via ADB.
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

# check no-root
if [ "$(id -u)" -eq 0 ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

# chec script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
pkgs='adb scrcpy'
for pkg in $pkgs; do
  dpkg -s "$pkg" &>/dev/null || command -v "$pkg" &>/dev/null || {
    echo "❌ '$pkg' is not installed. Run:"
    echo "sudo apt install $pkg"
    exit 1
  }
done

PIDFILE="/tmp/scrcpy.pid"

check_device() {
    # Start ADB daemon explicitly (silently)
    adb start-server > /dev/null 2>&1

    # Check if an ADB device is connected
    if ! adb devices | grep -w "device" > /dev/null; then
        echo "❌ No ADB device connected."
        exit 1
    fi
}

start() {
    check_device

    # Avoid starting multiple instances
    if pgrep -x scrcpy > /dev/null; then
        echo "⚠️ scrcpy is already running."
        exit 1
    fi

    # Start scrcpy in the background and save its PID
    nohup scrcpy --max-size 1024 > /dev/null 2>&1 &
    echo $! > "$PIDFILE"
    echo "✅ scrcpy started."
}

stop() {
    # Stop scrcpy if PID file exists
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null && rm -f "$PIDFILE"
        echo "🛑 scrcpy stopped."
    else
        # Fallback if PID file is missing
        pkill -x scrcpy && echo "🛑 scrcpy stopped (no PIDFILE)." || echo "ℹ️ scrcpy was not running."
    fi
}

status() {
    # Report whether scrcpy is running
    if pgrep -x scrcpy > /dev/null; then
        echo "✅ scrcpy is running (PID $(pgrep -x scrcpy))."
    else
        echo "ℹ️ scrcpy is not running."
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac

