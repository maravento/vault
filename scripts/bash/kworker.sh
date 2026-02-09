#!/bin/bash
# maravento.com
#
# Kworker Kill

echo "Kworker Kill Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

### VARIABLES
kworker=$(pwd)/gpelist.txt
echo "Check GPE list..."
# Generates GPE list
grep enabled /sys/firmware/acpi/interrupts/* >"$kworker"
# Save in the variable $gpe the full address of the erroneous gpe
gpe=$(cat "$kworker" | egrep '[1-9][0-9][0-9][0-9]+ ' | sort -rnk 2 | head -n1 | cut -d":" -f1)
rm "$kworker"

### KWORKER
if [ ! "$gpe" ]; then
    echo "No Kworker to Disable"
else
    echo "Send Deactivation Signal"
    echo "disable" >"$gpe"
    bash -c 'echo "kworker disable $(cat $gpe)"' | tee -a /var/log/syslog
fi
