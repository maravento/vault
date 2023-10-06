#!/bin/bash
# by maravento.com

# IP Kill

echo "IP Kill. Wait..."
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

sleep_time="10"

echo "Net Interfaces:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
read -p "Enter the network interface. e.g: enpXsX): " eth
if [ "$eth" ]; then
    read -p "Enter IP to close: " ip
    ipnew=$(echo "$ip" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$ipnew" ]; then
        tcpkill -i "$eth" host "$ipnew" &
        sleep "${sleep_time}"
    fi
    for child in $(jobs -p); do
        echo kill "$child" && kill "$child"
    done
    wait $(jobs -p)
fi
echo "IP Kill Done: $(date)" | tee -a /var/log/syslog
