#!/bin/bash
# maravento.com
#
################################################################################
#
# Force Log Rotate
# You should only use it if logrotate fails.
#
################################################################################

echo "Force Log Rotate Start. Wait..."
printf "\n"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

if ! command -v logrotate >/dev/null 2>&1; then
    echo "logrotate not found. Installing..."
    apt-get -qq update
    if ! apt-get -qq install -y logrotate; then
        echo "Failed to install logrotate" >&2
        exit 1
    fi
    echo "logrotate installed successfully"
fi

LOGROTATE_BIN=$(command -v logrotate)

LOGROTATE_ERR=$("$LOGROTATE_BIN" /etc/logrotate.conf 2>&1 >/dev/null)
EXITVALUE=$?

if [ "$EXITVALUE" -ne 0 ]; then
    /usr/bin/logger -t logrotate "ALERT exited abnormally with [$EXITVALUE]: $LOGROTATE_ERR"
fi

exit 0
