#!/bin/bash
# maravento.com
#
################################################################################
#
# Kworker Kill
# FILE: kworker.sh
#
# DESCRIPTION: Detects an ACPI GPE interrupt in storm (high count) and
# disables it to stop the associated kworker CPU spike. Run as root.
#
# USAGE:
# COMMAND               ACTION
# sudo bash kworker.sh  Run (no arguments)
#
# LOG: system logger (destination set by system configuration)
################################################################################

set -uo pipefail

# root check
if [ "$(command -p id -u)" != "0" ]; then
    echo "$(command -p date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
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
for dep in grep coreutils util-linux bsdutils iproute2 libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
                # the download proves link and internet; only IPv4 is left to check
                check_ipv4_interfaces
            else
                check_ipv4_interfaces
                check_internet
            fi
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
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: kworker start..."

kworker=$(mktemp /tmp/gpelist.XXXXXX)
trap 'rm -f "$kworker"' EXIT

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Checking GPE list..."
grep enabled /sys/firmware/acpi/interrupts/* 2>/dev/null > "$kworker"

gpe=$(grep -E '[1-9][0-9][0-9][0-9]+ ' "$kworker" | sort -rnk 2 | head -n1 | cut -d":" -f1)
# Pattern matches GPE interrupt counts >= 1000, indicating a potential IRQ storm

if [ -z "$gpe" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no GPE interrupt storm found"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Disabling ${gpe##*/}..."
    echo "disable" > "$gpe"
    gpe_rc=$?
    if [ "$gpe_rc" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: kworker disable: $gpe"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot disable ${gpe##*/}, rc=$gpe_rc -alert"
    fi
    logger -t kworker "kworker disable: $gpe rc=$gpe_rc" || true
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: kworker done"
