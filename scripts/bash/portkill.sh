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
# sudo ./portkill.sh
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
for dep in lsof; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# lsof must support -Q, which separates a failed query from an empty result
if ! lsof -h 2>&1 | grep -q -- '-Q'; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: lsof does not support -Q -abort" >&2
    exit 1
fi

# validation -- integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'
echo "$(date '+%Y-%m-%d %H:%M:%S') Port Kill Starting. Wait..."

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: portkill start..."

# PORT KILL
# Read the port whose owning processes will be stopped
read -rp "Enter Port Number to close: " port

if [ -z "$port" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: port number cannot be empty -abort"
    exit 1
fi
if ! [[ "$port" =~ $UH_UINT ]] || [ "${#port}" -gt 5 ] \
    || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: '$port' is not a valid port number (1-65535) -abort"
    exit 1
fi

if ! pids=$(lsof -Q -t -i:"$port" 2>/dev/null); then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot query port $port -abort"
    exit 1
fi
if [ -z "$pids" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no process on port $port -skip"
else
    if ! kill $pids 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to kill process(es) on port $port -abort"
        exit 1
    fi
    sleep 1
    if ! remaining=$(lsof -Q -t -i:"$port" 2>/dev/null); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot verify port $port -abort"
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
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: portkill done"
