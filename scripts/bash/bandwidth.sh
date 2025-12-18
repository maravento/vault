#!/bin/bash
# maravento.com
#
# Check Bandwidth
# Source: https://github.com/sivel/speedtest-cli

echo "Check Bandwidth Starting. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "This script requires Ubuntu 24.04. Use at your own risk"
    # exit 1
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
    echo "🔧 Releasing APT/DKPG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
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
# Set Minimum Download Value
dlmin="1.00"
# Set Minimum Upload Value
ulmin="1.00"

### SPEEDTEST
# Speedtest Python Script
#dl=$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple --no-upload | grep 'Download:')
#ul=$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple --no-download | grep 'Upload:')
#resume=$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple)
# Speedtest-cli
dl=$(speedtest-cli --secure --simple --no-upload | grep 'Download:')
ul=$(speedtest-cli --secure --simple --no-download | grep 'Upload:')
resume=$(speedtest-cli --secure --simple)

mb="Mbit/s"
dlvalue=$(echo "$dl" | awk '{print $2}')
ulvalue=$(echo "$ul" | awk '{print $2}')
dlmb=$(echo "$dl" | awk '{print $3}')
ulmb=$(echo "$ul" | awk '{print $3}')

function download() {
    if (($(echo "$dlvalue $dlmin" | awk '{print ($1 < $2)}'))); then
        echo "WARNING! Bandwidth Download Slow: $dlvalue $dlmb < $dlmin $mb (min value)"
    else
        echo "Bandwidth Download OK:" "Up to $dlmin"
    fi
}

function upload() {
    if (($(echo "$ulvalue $ulmin" | awk '{print ($1 < $2)}'))); then
        echo "WARNING! Bandwidth Upload Slow: $ulvalue $ulmb < $ulmin $mb (min value)"
    else
        echo "Bandwidth Upload OK:" "Up to $ulmin"
    fi
}

if [[ "$mb" == "$dlmb" ]] && [[ "$mb" == "$ulmb" ]]; then
    download
    upload
else
    echo "Incorrect Value. Abort: $resume"
    exit
fi
echo Done
