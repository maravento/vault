#!/bin/bash
# maravento.com

# Force Log Rotate
# You should only use it if logrotate fails.

echo "Force Log Rotate Start. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
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
