#!/bin/bash
# maravento.com
#
# Kill Process By Name

echo "Kill Process Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

### KILL PROCESS
read -p "Set process name (e.g. vlc): " PS
f() { ps ax | grep "$1" | grep -v grep | awk '{print $1}' | xargs kill -9 &>/dev/null; }
f "$PS"

if [ $? -gt 0 ]; then
    echo "There are no records of: $PS"
else
    echo "Done"
fi
