#!/bin/bash
# maravento.com
#
################################################################################
#
# Check Bandwidth
# Source: https://github.com/sivel/speedtest-cli
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

echo "Check Bandwidth Starting. Wait..."

# DEPENDENCIES
for dep in speedtest-cli gawk; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: Required dependency '$dep' is not installed." >&2
        exit 1
    fi
done

### VARIABLES
# Set Minimum Download Value (Mbit/s)
dlmin="1.00"
# Set Minimum Upload Value (Mbit/s)
ulmin="1.00"

### SPEEDTEST
echo "Running speedtest (this may take ~30s)..."
resume=$(speedtest-cli --secure --simple 2>&1)

if ! echo "$resume" | grep -q "^Download:"; then
    echo "speedtest-cli failed or returned unexpected output:"
    echo "$resume"
    exit 1
fi

dl=$(echo "$resume" | grep "^Download:")
ul=$(echo "$resume" | grep "^Upload:")

dlvalue=$(echo "$dl" | awk '{print $2}')
ulvalue=$(echo "$ul" | awk '{print $2}')
dlmb=$(echo "$dl" | awk '{print $3}')
ulmb=$(echo "$ul" | awk '{print $3}')

if [ -z "$dlvalue" ] || [ -z "$ulvalue" ]; then
    echo "Could not parse speedtest output:"
    echo "$resume"
    exit 1
fi

# speedtest-cli switches to Gbit/s above ~1000 Mbit/s which broke the unit check
normalize_to_mbit() {
    local value="$1"
    local unit="$2"
    if [[ "$unit" == "Gbit/s" ]]; then
        echo "$value" | awk '{printf "%.2f", $1 * 1000}'
    else
        echo "$value"
    fi
}

dlvalue_mbit=$(normalize_to_mbit "$dlvalue" "$dlmb")
ulvalue_mbit=$(normalize_to_mbit "$ulvalue" "$ulmb")

download() {
    if (($(echo "$dlvalue_mbit $dlmin" | awk '{print ($1 < $2)}'))); then
        echo "WARNING! Bandwidth Download Slow: $dlvalue $dlmb < $dlmin Mbit/s (min value)"
    else
        echo "Bandwidth Download OK: $dlvalue $dlmb (min: $dlmin Mbit/s)"
    fi
}
upload() {
    if (($(echo "$ulvalue_mbit $ulmin" | awk '{print ($1 < $2)}'))); then
        echo "WARNING! Bandwidth Upload Slow: $ulvalue $ulmb < $ulmin Mbit/s (min value)"
    else
        echo "Bandwidth Upload OK: $ulvalue $ulmb (min: $ulmin Mbit/s)"
    fi
}

download
upload

echo "Full result:"
echo "$resume"
echo "Done"
