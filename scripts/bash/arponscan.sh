#!/bin/bash
# maravento.com
#
################################################################################
#
# ARP table filter
# v3.0-ng or higher
#
################################################################################

echo "ARP table filter Starting. Wait..."
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
pkgs='arpon'
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

mkdir -p /var/log/arpon
touch /var/log/arpon/arpon.log

### VARIABLES
# path mac addresses
read -r -p "Enter the path for MAC addresses (e.g. /etc/acl): " acl_path
printf "\n"
# local net interface
read -r -p "Enter the local network interface (e.g. enp2s0): " lan
printf "\n"
# Local IP Server
read -r -p "Enter the local IP server (e.g. 192.168.0.10): " localip

ARPSTATIC_FILE="$(dirname "$(realpath "$0")")/arpstatic"

# ip2mac
function ip2mac() {
    echo '#!/bin/bash' > "$ARPSTATIC_FILE"
    awk -F";" '{print "ip neigh replace " $3 " lladdr " $2 " nud permanent dev '"$lan"'"}' "$acl_path"/mac* \
        | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n -k 5,5n -k 6,6n -k 7,7n -k 8,8n -k 9,9n \
        | uniq >> "$ARPSTATIC_FILE"
}

# arpon run
# change mode (darpi, sarpi, harpi)
mode=darpi

function arponrun() {
    chmod +x "$ARPSTATIC_FILE"

    # optional rule: flush ARP table
    ip -s -s neigh flush all >/dev/null 2>&1
    # optional rule: flush ARP table (PERM) — keep local server IP
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
