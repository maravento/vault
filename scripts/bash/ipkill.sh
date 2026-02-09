#!/bin/bash
# maravento.com
#
# IP Kill

echo "IP Kill Starting. Wait..."
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

### VARIABLES
sleep_time="10"

### IP KILL
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
