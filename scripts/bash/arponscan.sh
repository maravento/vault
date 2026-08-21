#!/bin/bash
# maravento.com
#
################################################################################
#
# ARP table filter
# v3.0-ng or higher
#
################################################################################

set -uo pipefail

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

echo "ARP table filter Starting. Wait..."

# DEPENDENCIES
for dep in arpon net-tools iproute2 procps gawk systemd findutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: Required dependency '$dep' is not installed." >&2
        exit 1
    fi
done

mkdir -p /var/log/arpon
touch /var/log/arpon/arpon.log

# VALIDATION -- one variable per thing validated; use directly with =~
_UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

### VARIABLES
# path mac addresses
while :; do
    read -r -p "Enter the path for MAC addresses [/etc/acl]: " acl_path
    acl_path="${acl_path:-/etc/acl}"
    if [ -z "$acl_path" ] || ! compgen -G "$acl_path/mac*" >/dev/null; then
        echo "ERROR: path does not exist or has no mac* files. Try again."
        continue
    fi
    break
done
printf "\n"
# local net interface
while :; do
    read -r -p "Enter the local network interface (e.g. enp2s0): " lan
    if [ -z "$lan" ] || ! ip link show "$lan" &>/dev/null; then
        echo "ERROR: interface does not exist. Try again."
        continue
    fi
    break
done
printf "\n"
# Local IP Server
while :; do
    read -r -p "Enter the local IP server (e.g. 192.168.0.10): " localip
    if [[ "$localip" =~ $_UH_IPV4 ]]; then
        break
    fi
    echo "ERROR: invalid IPv4 address. Try again."
done

ARPSTATIC_FILE="$(dirname "$(realpath "$0")")/arpstatic"

# ip2mac
function ip2mac() {
    echo '#!/bin/bash' > "$ARPSTATIC_FILE"
    awk -F";" '{print "ip neigh replace " $3 " lladdr " $2 " nud permanent dev '"$lan"'"}' "$acl_path"/mac* \
        | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n \
        | uniq >> "$ARPSTATIC_FILE"
}

# arpon run
# change mode (darpi, sarpi, harpi)
mode=darpi

function arponrun() {
    chmod +x "$ARPSTATIC_FILE"

    # optional rule: flush ARP table
    ip -s -s neigh flush all >/dev/null 2>&1
    # optional rule: flush ARP table (PERM) -- keep local server IP
    arp -a | grep -i perm | grep -oP '(\d+\.){3}\d+' | grep -v "$localip" | xargs -I {} arp -d {}
    # run script and add ip+mac to ARP table
    "$ARPSTATIC_FILE" >/dev/null 2>&1

    if ps -ef | grep -qw '[a]rpon'; then
        systemctl reload-or-restart arpon >/dev/null 2>&1
        echo "ArpON reloaded $(date)" | tee -a /var/log/syslog
    else
        # start ArpON
        /usr/sbin/arpon -d -i "$lan" --"$mode" >/dev/null 2>&1
        echo "ArpON start $(date)" | tee -a /var/log/syslog
    fi
}

# Stops the service if there are duplicates
function duplicate() {
    local dupes
    dupes=$(for field in 2 3 4; do cut -d\; -f"${field}" "$acl_path"/mac* | sort | uniq -d; done)
    if [ -z "$dupes" ]; then
        ip2mac
        arponrun
        echo "Done"
    else
        echo "Duplicate Data: $(date) $dupes" | tee -a /var/log/syslog
        exit 1
    fi
}

duplicate
