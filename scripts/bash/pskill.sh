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
# USAGE: sudo bash pskill.sh
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

# dependencies
for dep in procps; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
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
