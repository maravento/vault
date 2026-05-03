#!/bin/bash
# maravento.com
#
# Check Bandwidth
# Source: https://github.com/sivel/speedtest-cli

echo "Check Bandwidth Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# check dependencies
pkgs='speedtest-cli'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DPKG locks..."
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi

### VARIABLES
# Set Minimum Download Value (Mbit/s)
dlmin="1.00"
# Set Minimum Upload Value (Mbit/s)
ulmin="1.00"

### SPEEDTEST
echo "Running speedtest (this may take ~30s)..."
resume=$(speedtest-cli --secure --simple 2>&1)

if ! echo "$resume" | grep -q "^Download:"; then
    echo "❌ speedtest-cli failed or returned unexpected output:"
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
    echo "❌ Could not parse speedtest output:"
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

function download() {
    if (($(echo "$dlvalue_mbit $dlmin" | awk '{print ($1 < $2)}'))); then
        echo "WARNING! Bandwidth Download Slow: $dlvalue $dlmb < $dlmin Mbit/s (min value)"
    else
        echo "Bandwidth Download OK: $dlvalue $dlmb (min: $dlmin Mbit/s)"
    fi
}

function upload() {
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
