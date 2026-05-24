#!/bin/bash
# maravento.com
#
################################################################################
#
# Kworker Kill
#
################################################################################

echo "Kworker Kill Starting. Wait..."
printf "\n"

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

kworker=$(mktemp /tmp/gpelist.XXXXXX)
trap 'rm -f "$kworker"' EXIT

echo "Check GPE list..."
grep enabled /sys/firmware/acpi/interrupts/* 2>/dev/null > "$kworker"

gpe=$(grep -E '[1-9][0-9][0-9][0-9]+ ' "$kworker" | sort -rnk 2 | head -n1 | cut -d":" -f1)

if [ -z "$gpe" ]; then
    echo "No Kworker to Disable"
else
    echo "Send Deactivation Signal"
    echo "disable" > "$gpe"
    echo "kworker disable: $gpe" | tee -a /var/log/syslog
fi
