#!/bin/bash
# maravento.com
#
################################################################################
#
# IP Kill
# FILE: ipkill.sh
#
# DESCRIPTION: Interactively cuts off a target host's TCP connections on a
# chosen network interface for a fixed time window. Run as root.
#
# USAGE: sudo ./ipkill.sh
# Asks for the target host and the network interface.
#
# LOG: system log (via logger, tag ipkill)
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# dependencies
for dep in dsniff iproute2 bsdutils coreutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: ipkill start..."

sleep_time="10"

echo "Net Interfaces:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'

read -r -p "Enter the network interface (e.g: enpXsX): " eth

if [ -z "$eth" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface entered -abort" >&2
    exit 1
fi

if ! ip link show "$eth" &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: interface not found: '$eth' -abort" >&2
    exit 1
fi

read -r -p "Enter IP to close: " target_ip

if ! [[ "$target_ip" =~ $UH_IPV4 ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid IP address -abort" >&2
    exit 1
fi
target_ip_validated="$target_ip"
case "$target_ip_validated" in
    0.0.0.0|255.255.255.255|127.*|224.*|225.*|226.*|227.*|228.*|229.*|230.*|231.*|232.*|233.*|234.*|235.*|236.*|237.*|238.*|239.*)
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: special/reserved IP: '$target_ip_validated' -alert"
        ;;
esac

tcpkill -i "$eth" host "$target_ip_validated" &
tcpkill_pid=$!
sleep "${sleep_time}"
kill "$tcpkill_pid" 2>/dev/null
wait "$tcpkill_pid" 2>/dev/null

logger -t ipkill "$(date '+%Y-%m-%d %H:%M:%S') EVENT: ipkill done: $target_ip_validated on $eth"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: ipkill done"
