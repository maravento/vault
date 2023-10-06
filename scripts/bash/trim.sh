#! /bin/bash
# by maravento.com

# Run TRIM for SSD
# https://askubuntu.com/a/665670/828892

echo "TRIM Start. Wait..."
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

# checking dependencies
pkgs='notify-osd libnotify-bin'
if apt-get install -qq $pkgs; then
    echo "OK"
else
    echo "Error installing $pkgs. Abort"
    exit
fi

# check trim
notify-send "TRIM" "$(fstrim -v /)"
