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
# USAGE:
# COMMAND              ACTION
# sudo bash ipkill.sh  Run (no arguments)
#
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

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort" >&2
    exit 1
}

# dependencies
net_checked=0
for dep in dsniff iproute2 bsdutils coreutils libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
            fi
            check_ipv4_interfaces
            check_internet
            apt-get update -qq || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2; exit 1; }
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing $dep"
        if ! apt-get install -y "$dep" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
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
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: ipkill start..."

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

logger -t ipkill "$(date '+%Y-%m-%d %H:%M:%S') INFO: ipkill done: $target_ip_validated on $eth"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: ipkill done"
