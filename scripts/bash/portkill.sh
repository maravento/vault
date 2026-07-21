#!/bin/bash
# maravento.com
#
################################################################################
#
# Port Kill
# check port with: sudo netstat -lnp | grep "port"
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

echo "Port Kill Starting. Wait..."

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
