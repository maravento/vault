#!/bin/bash
# maravento.com
#
# Kworker Kill

echo "Kworker Kill Starting. Wait..."
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
