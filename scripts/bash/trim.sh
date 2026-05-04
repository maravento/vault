#!/bin/bash
# by maravento.com

# Run TRIM for SSD
# WARNING: TRIM is a highly destructive command. Use it at your own risk.

echo "TRIM Start. Wait..."
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
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# Checking dependencies. Abort if installation fails.
pkgs='libnotify-bin'
if ! command -v notify-send >/dev/null 2>&1; then
    echo "Dependency $pkgs missing. Attempting to install..."
    if apt-get update -qq && apt-get install -qq $pkgs; then
        echo "Dependency installed successfully."
    else
        echo "Error: Failed to install $pkgs. Aborting script."
        exit 1
    fi
fi

# Execute TRIM
# -a: all mounted filesystems on devices that support TRIM
# -v: verbose output
TRIM_LOG=$(fstrim -av) || { echo "ERROR: fstrim failed"; exit 1; }
echo "$TRIM_LOG"

# Notify the user
# Since fstrim runs as root, we bridge to the user session to show the pop-up
REAL_USER=$(who | grep -m 1 '(:0)' | awk '{print $1}' || true)
if [ -z "$REAL_USER" ]; then
    REAL_USER=$(who | head -1 | awk '{print $1}' || true)
fi
if [ -z "$REAL_USER" ]; then
    REAL_USER=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}' || true)
fi
if [ -z "$REAL_USER" ]; then
    echo "WARNING: Cannot determine local user — skipping desktop notification"
else
    USER_ID=$(id -u "$REAL_USER")
    sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$USER_ID"/bus \
    notify-send "TRIM" "$TRIM_LOG"
fi

echo ""
echo "TRIM Finished."
