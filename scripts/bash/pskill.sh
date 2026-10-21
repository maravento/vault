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
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

echo "$(date '+%Y-%m-%d %H:%M:%S') Kill Process Starting. Wait..."

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') pskill start..."

# KILL PROCESS
# Read the process name to stop
read -rp "Set process name (e.g. vlc): " process_name

if [ -z "$process_name" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: process name cannot be empty -abort"
    exit 1
fi

protected_pattern="^(systemd|init|kernel|kthreadd|ksoftirqd|migration|watchdog)$"
if [[ "$process_name" =~ $protected_pattern ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: '$process_name' is a protected system process -abort"
    exit 1
fi

pids=$(ps ax | awk '{print $1, $5}' | grep -wF "$process_name" | awk '{print $1}' 2>/dev/null || true)

if [ -z "$pids" ]; then
    echo "There are no records of: $process_name"
else
    kill -TERM $pids 2>/dev/null
    sleep 3
    surviving=$(ps ax | awk '{print $1, $5}' | grep -wF "$process_name" | awk '{print $1}' 2>/dev/null)
    if [ -n "$surviving" ]; then
        kill -KILL $surviving 2>/dev/null
    fi
    echo "Done"
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') pskill done at: $(date '+%Y-%m-%d %H:%M:%S')"
