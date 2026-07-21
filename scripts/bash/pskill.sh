#!/bin/bash
# maravento.com
#
################################################################################
#
# Kill Process By Name
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

echo "Kill Process Starting. Wait..."

### KILL PROCESS
read -rp "Set process name (e.g. vlc): " PS

if [ -z "$PS" ]; then
    echo "ERROR: Process name cannot be empty"
    exit 1
fi

PROTECTED="^(systemd|init|kernel|kthreadd|ksoftirqd|migration|watchdog)$"
if [[ "$PS" =~ $PROTECTED ]]; then
    echo "ERROR: '$PS' is a protected system process and cannot be killed"
    exit 1
fi

pids=$(ps ax | awk '{print $1, $5}' | grep -wF "$PS" | awk '{print $1}' 2>/dev/null || true)

if [ -z "$pids" ]; then
    echo "There are no records of: $PS"
else
    kill -TERM $pids 2>/dev/null
    sleep 3
    surviving=$(ps ax | awk '{print $1, $5}' | grep -wF "$PS" | awk '{print $1}' 2>/dev/null)
    if [ -n "$surviving" ]; then
        kill -KILL $surviving 2>/dev/null
    fi
    echo "Done"
fi
