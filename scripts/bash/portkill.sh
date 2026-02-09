#!/bin/bash
# maravento.com
#
# Port Kill
# check port with: sudo netstat -lnp | grep "port"

echo "Port Kill Starting. Wait..."
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

### PORT KILL
read -p "Enter Port Number to close: " port
kill $(lsof -t -i:"$port") &>/dev/null
if [ $? -gt 0 ]; then
    echo "There are no records of $port"
else
    echo "Done"
fi
