#!/bin/bash
# maravento.com
#
################################################################################
#
# Hardware Clock Sync
# FILE: hwclock.sh
#
# DESCRIPTION: Syncs the hardware clock with the system clock. Run as root,
# intended to run at boot via cron (@reboot).
#
# USAGE:
# COMMAND               ACTION
# sudo bash hwclock.sh  Run (no arguments)
#
# LOG: system logger (destination set by system configuration)
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

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
# iproute2 first: the network checks need ip, so it installs without them
if [[ "$(dpkg-query -W -f='${Status}' iproute2 2>/dev/null)" != *"ok installed"* ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing iproute2..."
    if ! apt-get install -y iproute2; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2
        exit 1
    fi
fi
net_checked=0
for dep in util-linux util-linux-extra bsdutils coreutils libc-bin; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            check_ipv4_interfaces
            check_internet
            if ! apt-get update -qq; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
                exit 1
            fi
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing $dep..."
        if ! apt-get install -y "$dep"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: hwclock start..."

hwclock_rc=0
hwclock -w || {
    hwclock_rc=$?
    echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: hwclock -w failed, VM or container? -alert"
}
if [ "$hwclock_rc" -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: HWClock Update"
fi
logger -t hwclock "HWClock Update: rc=$hwclock_rc" || true

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: hwclock done"
