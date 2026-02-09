#!/bin/bash
# maravento.com

# Force Log Rotate
# You should only use it if logrotate fails.

echo "Force Log Rotate Start. Wait..."
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

# check and install logrotate if needed
if ! command -v logrotate >/dev/null 2>&1; then
    echo "logrotate not found. Installing..."
    apt-get -qq update
    apt-get -qq install -y logrotate
    if [ $? -ne 0 ]; then
        echo "Failed to install logrotate" 1>&2
        exit 1
    fi
    echo "logrotate installed successfully"
fi

### logrotate
/usr/sbin/logrotate /etc/logrotate.conf >/dev/null 2>&1
EXITVALUE=$?
if [ "$EXITVALUE" != 0 ]; then
    /usr/bin/logger -t logrotate "ALERT exited abnormally with [$EXITVALUE]"
fi
exit 0
