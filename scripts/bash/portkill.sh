#!/bin/bash
# maravento.com
#
################################################################################
#
# portkill -- kills the process listening on a port
# FILE: portkill.sh
#
# DESCRIPTION:
# Kills the process(es) listening on a port number entered by the user.
#
# USAGE:
# COMMAND                ACTION
# sudo bash portkill.sh  Run (no arguments)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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
for dep in iproute2 libc-bin coreutils grep; do
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

# PIDs listening on a local TCP/UDP port; a failed query returns 1
listener_pids() {
    local ss_out
    ss_out=$(ss -Hlntup "( sport = :$1 )") || return 1
    grep -oP 'pid=\K[0-9]+' <<<"$ss_out" | sort -u || true
}

# validation - integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: portkill start..."

# PORT KILL
# Read the port whose owning processes will be stopped
read -rp "Enter Port Number to close: " port

if [ -z "$port" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: port number cannot be empty -abort" >&2
    exit 1
fi
if ! [[ "$port" =~ $UH_UINT ]] || [ "${#port}" -gt 5 ] \
    || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: '$port' is not a valid port number (1-65535) -abort" >&2
    exit 1
fi

if ! pids=$(listener_pids "$port"); then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot query port $port -abort" >&2
    exit 1
fi
if [ -z "$pids" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no process on port $port -skip"
else
    if ! kill $pids 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to kill process(es) on port $port -abort" >&2
        exit 1
    fi
    sleep 1
    if ! remaining=$(listener_pids "$port"); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot verify port $port -abort" >&2
        exit 1
    fi
    if [ -z "$remaining" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: port $port released"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: port $port still in use -alert" >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: portkill done"
