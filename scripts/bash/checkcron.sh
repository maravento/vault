#!/bin/bash
# by maravento.com

# Check Changes into Crontab File

echo "Check Crontab. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# checking dependencies
pkgs='colordiff'
if apt-get install -qq $pkgs; then
    echo "OK"
else
    echo "Error installing $pkgs. Abort"
    exit
fi

if [ ! -f /etc/crontab ]; then crontab /etc/crontab &>/dev/null && cp /etc/crontab{,.bak} &>/dev/null; fi

# checklines=$(colordiff /etc/crontab /etc/crontab.bak)
checklines=$(comm -3 <((sort /etc/crontab)) <((sort /etc/crontab.bak)) | grep '.*')

if ! [ "$checklines" ]; then
    echo "No Changes"
else
    echo "Alert. Check crontab"
    echo "$checklines"
fi
