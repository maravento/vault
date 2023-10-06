#!/bin/bash
# by maravento.com

# ARP table filter
# v3.0-ng or higher

echo "ARP table filter Start. Wait..."
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
arponbin=$(which arpon)
if [ -z "$arponbin" ]; then
    apt-get install -qq arpon
    mkdir -p /var/log/arpon && touch /var/log/arpon/arpon.log
fi

# VARIABLES
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
