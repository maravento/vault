#!/bin/bash
# by maravento.com

# Kill Process By Name

echo "Kill Process Start. Wait..."
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

read -p "Set process name (e.g. vlc): " PS
f() { ps ax | grep "$1" | grep -v grep | awk '{print $1}' | xargs kill -9 &>/dev/null; }
f "$PS"

if [ $? -gt 0 ]; then
    echo "There are no records of: $PS"
else
    echo "Done"
fi
