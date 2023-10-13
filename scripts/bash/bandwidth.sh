#!/bin/bash
# by maravento.com

# Check Bandwidth
# Source: https://github.com/sivel/speedtest-cli

echo "Check Bandwidth. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# checking dependencies (optional)
pkgs='speedtest-cli'
if apt-get install -qq $pkgs; then
    true
else
    echo "Error installing $pkgs. Abort"
    exit
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
