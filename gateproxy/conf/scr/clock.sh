#!/bin/bash
# maravento.com

# Update Clock

echo "Cleaner Start. Wait..."
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

hwclock -w
echo "Clock Update: $(date)" | tee -a /var/log/syslog
echo "Done"
