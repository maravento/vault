#!/bin/bash
# maravento.com
#
################################################################################
#
# Port Kill
# check port with: sudo netstat -lnp | grep "port"
#
################################################################################

set -u

echo "Port Kill Starting. Wait..."
printf "\n"

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
cleanup() {
    : # lock file intentionally preserved; kernel releases flock on exit
}
trap cleanup EXIT
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

### PORT KILL
read -rp "Enter Port Number to close: " port

if [ -z "$port" ]; then
    echo "ERROR: Port number cannot be empty"
    exit 1
fi
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    echo "ERROR: '$port' is not a valid port number (1-65535)"
    exit 1
fi

pids=$(lsof -t -i:"$port" 2>/dev/null)
if [ -z "$pids" ]; then
    echo "There are no records of $port"
else
    if kill $pids 2>/dev/null; then
        echo "Done"
    else
        echo "ERROR: Failed to kill process(es) on port $port"
        exit 1
    fi
fi
