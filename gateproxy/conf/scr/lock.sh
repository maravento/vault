#!/bin/bash
# maravento.com

# Lock Scripts

echo "Lock Script Start. Wait..."
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

### LOCK
randa=$(($RANDOM % 3 + 1))
pid_execute=$(ps -eo pid,comm | grep $0 | egrep -o '[0-9]+')
if [[ "${pid_execute:-NO_VALUE}" != "NO_VALUE" ]]; then
    echo "$0 $@" | at now + "$randa" min
    exit
    echo "Lock Start: $(date)" | tee -a /var/log/syslog
fi
echo "Done"
