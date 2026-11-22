#!/bin/bash
# maravento.com
#
################################################################################
#
# Kill Process By Name
# FILE: pskill.sh
#
# DESCRIPTION: Kills every process matching a name. Sends TERM, waits three
# seconds, then sends KILL to the survivors. Refuses core system processes.
# Matches the exact comm name and rejects names longer than 15 bytes.
#
# USAGE:
# COMMAND              ACTION
# sudo bash pskill.sh  Run (no arguments)
#
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

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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
for dep in procps iproute2 libc-bin coreutils; do
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
# FUNCTIONS
# ------------------------------------------------------------------------------

name_fits_comm() {
    local LC_ALL=C
    (( ${#1} <= 15 ))
}

# LIVE PIDS
# Return the PIDs still running, excluding the gone and the zombies
live_pids() {
    local pid state out=""
    for pid in $1; do
        state=$(ps -o stat= -p "$pid" 2>/dev/null)
        [ -z "$state" ] && continue
        case "$state" in Z*) continue ;; esac
        out="$out $pid"
    done
    echo "$out"
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: pskill start..."

# KILL PROCESS
# Read the process name to stop
read -rp "Set process name (e.g. vlc): " process_name

if [ -z "$process_name" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: process name cannot be empty -abort" >&2
    exit 1
fi

protected_pattern="^(systemd|init|kernel|kthreadd|ksoftirqd|migration|watchdog)$"
if [[ "$process_name" =~ $protected_pattern ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: '$process_name' is a protected system process -abort" >&2
    exit 1
fi

if ! name_fits_comm "$process_name"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: name exceeds 15 bytes; use the comm name -abort" >&2
    exit 1
fi

pids=$(ps -ww -eo pid=,comm= | PROCESS_NAME="$process_name" awk '
    { pid = $1; sub(/^[[:blank:]]*[0-9]+[[:blank:]]+/, "") }
    ("x" $0) == ("x" ENVIRON["PROCESS_NAME"]) { print pid }
')

if [ -z "$pids" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no process named $process_name -skip"
else
    kill -TERM $pids 2>/dev/null
    sleep 3
    surviving=$(live_pids "$pids")
    if [ -n "$surviving" ]; then
        kill -KILL $surviving 2>/dev/null
        sleep 1
    fi
    remaining=$(live_pids "$pids")
    if [ -z "$remaining" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $process_name terminated"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: still running:$remaining -alert" >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: pskill done"
