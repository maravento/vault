#!/bin/bash
# by maravento.com

# Kworker Kill

echo "Kworker Kill. Wait..."
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

kworker=$(pwd)/gpelist.txt
echo "Check GPE list..."
# Generates GPE list
grep enabled /sys/firmware/acpi/interrupts/* >"$kworker"
# Save in the variable $gpe the full address of the erroneous gpe
gpe=$(cat "$kworker" | egrep '[1-9][0-9][0-9][0-9]+ ' | sort -rnk 2 | head -n1 | cut -d":" -f1)
rm "$kworker"
if [ ! "$gpe" ]; then
    echo "No Kworker to Disable"
else
    echo "Send Deactivation Signal"
    echo "disable" >"$gpe"
    bash -c 'echo "kworker disable $(cat $gpe)"' | tee -a /var/log/syslog
fi
