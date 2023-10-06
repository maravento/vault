#!/bin/bash
# by maravento.com

# Port Kill
# check port with: sudo netstat -lnp | grep "port"

echo "Port Kill Start. Wait..."
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

read -p "Enter Port Number to close: " port
kill $(lsof -t -i:"$port") &>/dev/null
if [ $? -gt 0 ]; then
    echo "There are no records of $port"
else
    echo "Done"
fi
