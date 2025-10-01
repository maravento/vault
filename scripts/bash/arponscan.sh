#!/bin/bash
# maravento.com
#
# ARP table filter
# v3.0-ng or higher

echo "ARP table filter Starting. Wait..."
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
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
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

mkdir -p /var/log/arpon >/dev/null 2>&1
touch /var/log/arpon/arpon.log >/dev/null 2>&1

### VARIABLES
# path mac adresses
read -p "Enter the path for MAC addresses (e.g. /etc/acl): " acl
printf "\n"
# local net interface
read -p "Enter the local network interface (e.g. enp2s0): " lan
printf "\n"
# Local IP Server
read -p "Enter the local IP server (e.g. 192.168.0.10): " localip

# ip2mac
function ip2mac() {
    # SARPI + ISC-DHCP-SERVER + arpon.conf
    # capture mac/ip from /var/lib/dhcp/dhcpd.leases (out format: ip  mac)
    #cat /var/lib/dhcp/dhcpd.leases | egrep -o 'lease.*{|ethernet.*;' | awk '{print $2}' | xargs -n 2 | cut -d ';' -f 1 > /etc/arpon.conf

    # SARPI + arpon.conf
    # capture mac+ip from mac* adresses files and add to /etc/arpon.conf (string format mac*: a;mac;ip;HOST)
    # example mac files: $acl/macadmin $acl/macusers
    #awk -F";" '{print $3 " " $2}' $acl/mac* | xargs -I {} echo {} > /etc/arpon.conf

    # DARPI + arpstatic
    # optional: activate DARPI in /etc/default/arpon (not necessary)
    #sed -i '/DAEMON_ARGS="--sarpi"/s/^#*/#/g' /etc/default/arpon
    #sed -i '/DAEMON_ARGS="--darpi"/s/^#*\s*//g' /etc/default/arpon

    # check script (with arp)
    # capture mac+ip from mac* adresses files and add to arpstatic (string format mac*: a;mac;ip;HOST)
    # example mac files: $acl/macadmin $acl/macusers
    #awk -F";" '{print $3 " " $2}' $acl/mac* | sed -e "s/^/arp -i $lan -s /" | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n -k 5,5n -k 6,6n -k 7,7n -k 8,8n -k 9,9n | uniq | sed -e '1i#!/bin/bash\' > arpstatic

    # check script (with ip neigh)
    # capture mac+ip from mac* adresses files and add to arpstatic (string format mac*: a;mac;ip;HOST)
    # example mac files: $acl/macadmin $acl/macusers
    echo '#!/bin/bash' >arpstatic
    awk -F";" '{print "ip neigh replace " $3 " lladdr " $2 " nud permanent dev '$lan'"}' $acl/mac* | sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n -k 5,5n -k 6,6n -k 7,7n -k 8,8n -k 9,9n | uniq >>arpstatic
}

# arpon run
# change mode (darpi, sarpi, harpi)
mode=darpi

function arponrun() {
    if [[ $(ps -ef | grep -w '[a]rpon') != "" ]]; then
        # optional rule: flush ARP table
        ip -s -s neigh flush all >/dev/null 2>&1
        # optional rule: flush ARP table (PERM)
        arp -a | grep -i perm | grep -oP '(\d+\.){3}\d+' | grep -v $localip | xargs -I {} arp -d {}
        # run script and add ip+mac to ARP Table (DARPI + arpstatic)
        chmod +x ./arpstatic && ./arpstatic >/dev/null 2>&1
        # log
        echo "ArpON ONLINE" | tee -a /var/log/syslog
    else
        # optional rule: flush ARP table
        ip -s -s neigh flush all >/dev/null 2>&1
        # optional rule: flush ARP table (PERM)
        arp -a | grep -i perm | grep -oP '(\d+\.){3}\d+' | grep -v $localip | xargs -I {} arp -d {}
        # run script and add ip+mac to ARP Table (DARPI + arpstatic)
        chmod +x ./arpstatic && ./arpstatic >/dev/null 2>&1
        # start ArpON
        /usr/sbin/arpon -d -i $lan --$mode >/dev/null 2>&1
        # log
        echo "ArpON start $date" | tee -a /var/log/syslog
    fi
}

# Stops the service if there are duplicates / Detiene el servicio si hay duplicados
function duplicate() {
    acl=$(for field in 2 3 4; do cut -d\; -f${field} "$acl"/mac-* | sort | uniq -d; done)
    if [ "${acl}" == "" ]; then
        ip2mac
        arponrun
        echo Done
    else
        echo "Duplicate Data: $(date) $acl" | tee -a /var/log/syslog
        exit
    fi
}
duplicate
