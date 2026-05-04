#!/bin/bash
# maravento.com
#
# Kill Process By Name

set -u

echo "Kill Process Starting. Wait..."
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
cleanup() {
    rm -f "$SCRIPT_LOCK"
}
trap cleanup EXIT
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

### KILL PROCESS
read -rp "Set process name (e.g. vlc): " PS

if [ -z "$PS" ]; then
    echo "ERROR: Process name cannot be empty"
    exit 1
fi

PROTECTED="^(systemd|init|kernel|kthreadd|ksoftirqd|migration|watchdog)$"
if [[ "$PS" =~ $PROTECTED ]]; then
    echo "ERROR: '$PS' is a protected system process and cannot be killed"
    exit 1
fi

pids=$(ps ax | awk '{print $1, $5}' | grep -F "$PS" | awk '{print $1}' 2>/dev/null) || {
    echo "ERROR: Failed to query process list"
    exit 1
}

if [ -z "$pids" ]; then
    echo "There are no records of: $PS"
else
    kill -TERM $pids 2>/dev/null
    sleep 3
    surviving=$(ps ax | awk '{print $1, $5}' | grep -F "$PS" | awk '{print $1}' 2>/dev/null)
    if [ -n "$surviving" ]; then
        kill -KILL $surviving 2>/dev/null
    fi
    echo "Done"
fi
