#!/bin/bash
# maravento.com
#
################################################################################
#
# arponscan -- ARP table filter
# FILE: arponscan.sh
# v3.0-ng or higher
#
# DESCRIPTION: Reads mac*.txt files (format: status;MAC;IP;HOSTNAME; -- same
# convention as gateproxy/pydhcp/uhm's mac-limited.txt/mac-unlimited.txt) from
# the path given at the prompt, and builds static ARP entries (IP<->MAC)
# enforced by arpon against those known devices.
#
# USAGE: sudo ./arponscan.sh
# Asks for the ACL path, the LAN interface and the server IP.
#
# LOG: /var/log/syslog
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') ARP table filter Starting. Wait..."

# dependencies
for dep in arpon net-tools iproute2 procps systemd findutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

mkdir -p /var/log/arpon
touch /var/log/arpon/arpon.log

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'

# ACL FILES
# Read the directory containing the administrator MAC lists
while :; do
    read -r -p "Enter the path for MAC addresses [/etc/acl/mac]: " acl_path
    acl_path="${acl_path:-/etc/acl/mac}"
    if [ -z "$acl_path" ] || ! compgen -G "$acl_path/mac*" >/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: path does not exist or has no mac* files -retry"
        continue
    fi
    break
done
printf "\n"
# LAN INTERFACE
# Read and verify the local network interface
while :; do
    read -r -p "Enter the local network interface (e.g. eth1): " lan
    if [ -z "$lan" ] || ! ip link show "$lan" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: interface does not exist -retry"
        continue
    fi
    break
done
printf "\n"
# SERVER ADDRESS
# Read and validate the server IPv4 address
while :; do
    read -r -p "Enter the local IP server (e.g. 192.168.0.10): " localip
    if [[ "$localip" =~ $UH_IPV4 ]]; then
        break
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: invalid IPv4 address -retry"
done

ARPSTATIC_FILE="$(dirname "$(realpath "$0")")/arpstatic"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# STATIC ENTRIES
# Generate the script that installs permanent IP and MAC bindings
ip2mac() {
    local tmp_file="${ARPSTATIC_FILE}.tmp"
    echo '#!/bin/bash' > "$tmp_file" || return 1
    awk -F";" '$1 == "a" {print "ip neigh replace " $3 " lladdr " $2 " nud permanent dev '"$lan"'"}' "$acl_path"/mac* \
        | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n \
        | uniq >> "$tmp_file" || { rm -f "$tmp_file"; return 1; }
    mv -f "$tmp_file" "$ARPSTATIC_FILE" || { rm -f "$tmp_file"; return 1; }
}

# ARPON MODE
# Select the ArpON mode used when starting the daemon
mode=darpi

# ARPON SERVICE
# Apply static entries and reload or start ArpON
arponrun() {
    if ! chmod +x "$ARPSTATIC_FILE"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot make arpstatic executable -abort" >&2
        exit 1
    fi

    # optional rule: flush ARP table
    ip -s -s neigh flush all >/dev/null 2>&1
    # optional rule: flush ARP table (PERM) -- keep local server IP
    arp -a | grep -i perm | grep -oP '(\d+\.){3}\d+' | grep -v -x -F "$localip" | xargs -I {} arp -d {}
    # run script and add ip+mac to ARP table
    "$ARPSTATIC_FILE" >/dev/null 2>&1

    if pgrep -x arpon > /dev/null; then
        systemctl reload-or-restart arpon >/dev/null 2>&1
        echo "ArpON reloaded $(date '+%Y-%m-%d %H:%M:%S')" | tee -a /var/log/syslog
    else
        # start ArpON
        /usr/sbin/arpon -d -i "$lan" --"$mode" >/dev/null 2>&1
        echo "ArpON start $(date '+%Y-%m-%d %H:%M:%S')" | tee -a /var/log/syslog
    fi
}

# DUPLICATE CHECK
# Reject duplicate MAC, IP or hostname fields before applying entries
duplicate() {
    local dupes
    dupes=$(for field in 2 3 4; do cut -d\; -f"${field}" "$acl_path"/mac* | sort | uniq -d; done)
    if [ -z "$dupes" ]; then
        if ! ip2mac; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to generate arpstatic -abort" | tee -a /var/log/syslog
            exit 1
        fi
        arponrun
        echo "Done"
    else
        echo "Duplicate Data: $(date '+%Y-%m-%d %H:%M:%S') $dupes" | tee -a /var/log/syslog
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') arponscan start..."

duplicate

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') arponscan done at: $(date '+%Y-%m-%d %H:%M:%S')"
