#!/bin/bash
# maravento.com
#
################################################################################
#
# IP Kill
#
################################################################################

echo "IP Kill Starting. Wait..."
printf "\n"

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

if ! command -v tcpkill &>/dev/null; then
    echo "❌ 'tcpkill' is not installed. Run: sudo apt install dsniff"
    exit 1
fi

sleep_time="10"

echo "Net Interfaces:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'

read -r -p "Enter the network interface (e.g: enpXsX): " eth

if [ -z "$eth" ]; then
    echo "❌ No interface entered."
    exit 1
fi

if ! ip link show "$eth" &>/dev/null; then
    echo "❌ Interface '$eth' does not exist."
    exit 1
fi

read -r -p "Enter IP to close: " target_ip

target_ip_validated=$(echo "$target_ip" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
if [ -z "$target_ip_validated" ]; then
    echo "❌ Invalid IP address: '$target_ip'"
    exit 1
fi
case "$target_ip_validated" in
    0.0.0.0|255.255.255.255|127.*|224.*|225.*|226.*|227.*|228.*|229.*|230.*|231.*|232.*|233.*|234.*|235.*|236.*|237.*|238.*|239.*)
        echo "⚠️  Warning: '$target_ip_validated' is a special/reserved address. Continuing anyway."
        ;;
esac

tcpkill -i "$eth" host "$target_ip_validated" &
tcpkill_pid=$!
sleep "${sleep_time}"
kill "$tcpkill_pid" 2>/dev/null
wait "$tcpkill_pid" 2>/dev/null

logger -t ipkill "IP Kill Done: $target_ip_validated on $eth"
echo "IP Kill Done: $(date)"
