#!/bin/bash
### BEGIN INIT INFO
# Provides:          bandata
# Required-Start:    $local_fs $remote_fs $network
# Required-Stop:     $local_fs $remote_fs $network
# Should-Start:      $named
# Should-Stop:       $named
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start daemon at boot time
# Description:       Enable service provided by daemon
### END INIT INFO

# maravento.com

# BANDATA FOR BANDWIDTHD
# Data Plan for LocalNet
# https://www.maravento.com/2021/08/bandwidthd.html

# Instructions:
# maximum daily data consumption: 1 Gbyte = 1G
# adjust the variable "max_bandwidth", according to your needs
# can use fractions of bandwidth. Eg: 1.2G, 3.9G...

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

echo "Start BanData for BandwidthD..."
printf "\n"

### VARIABLES
# replace interface (e.g: enpXsX)
lan="eth1"
# today
today=$(date +"%u")
# reorganize IP
reorganize="sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n"
# path to ACLs folder
aclroute="/etc/acl"
mkdir -p "$aclroute" >/dev/null 2>&1
# path to ACLs
allow_list=$aclroute/bwallowdata.txt
block_list=$aclroute/bwbandata.txt
# Create ACLs if doesn't exist
touch {"$allow_list","$block_list"} >/dev/null 2>&1

### BANDATA FOR BANDWIDTHD
# maximum daily data consumption: 1 Gbyte = 1G
max_bandwidth="1G"
# path daily report
html_file="/var/lib/bandwidthd/htdocs/index.html"
# range
range="192.168.1"
# capture
ips=$(grep -Pi '\<tr\.*' $html_file | sed -r 's:<[^>]+>: :g' | grep $range | awk '{gsub(/\./, ",", $2); print $2" "$1}')
max_bw=$(echo "$max_bandwidth" | tr '.' ',' | numfmt --from=iec)
echo "$ips" | numfmt --from=iec | awk '$1 > '$max_bw' {print $2}' | grep -wvf "$allow_list" | "$reorganize" | uniq > "$block_list"

### IPSET/IPTABLES FOR BANDATA
ipset -L bwbandata >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ipset -! create bwbandata hash:net family inet hashsize 1024 maxelem 65536
else
    ipset -! flush bwbandata
fi
for ip in $(cat "$block_list" | "$reorganize" | uniq); do
    ipset -! add bwbandata "$ip"
done
iptables -A INPUT -i $lan -m set --match-set bwbandata src -j DROP
iptables -A FORWARD -i $lan -m set --match-set bwbandata src -j DROP
echo Done
