#!/bin/bash
# maravento.com

# Iptables NetCut

# Warning
# Use it only in case of attack or illegal access to your network

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

# Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
# Ports: /etc/services
# check: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt

echo "Iptables NetCut. Wait..."
printf "\n"

### VARIABLES
# interfaces
wan=eth0
lan=eth1
# IP/Netmask
local=192.168.0.0
netmask=24

####################
### KERNEL RULES ###
####################

echo "Load Kerner Rules..."

### Zero all packets and counters ###
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -t security -F
iptables -t security -X
iptables -Z
iptables -t nat -Z
iptables -t mangle -Z

echo "Drop All..."

### Global Policies IPv4
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

### Global Policies IPv6
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

echo "Blackhole..."

### Blackhole
ip route add blackhole 0.0.0.0/0

echo "iptables NetCut at: $(date)" | tee -a /var/log/syslog
echo "Done"
