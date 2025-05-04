#!/bin/bash
# maravento.com

# Ban IP

echo "Banip Start. Wait..."
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

### VARIABLES
# ipset/iptables
iptables=/sbin/iptables
ipset=/sbin/ipset
# replace localnet interface (enpXsX)
lan=eth1
# path to ACLs folder
aclroute=/etc/acl
# path to banip
ban_ip="$aclroute/banip.txt"
# ban_nflog option grep -f
# Notice: 
# If you add an iptables rule with NFLOG, you must add the message to the nflog.txt ACL
ban_nflog="$aclroute/nflog.txt"
# Create ACLs if doesn't exist
if [[ ! -f {$ban_nflog,$ban_ip} ]]; then touch {$ban_nflog,$ban_ip}; fi
# DEBUG IP
reorganize="sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n"

### BANIP CAPTURE
echo "BanIP for syslogemu..."
# syslogemu (log)
syslogemu="/var/log/ulog/syslogemu.log"
# ban time (10 min = 600 seconds - 24H = 86400)
bantime="86400"
# localrange (replace "192.168.*" with the first two octets of your local network range)
localrange="192.168.*"
# add matches to ban_ip
# change option path (for local: grep -f "$ban_nflog") (for curl: grep -F "$ban_nflog")
perl -MDate::Parse -ne "print if/^(.{15})\s/&&str2time(\$1)>time-$bantime" "$syslogemu" | grep -f "$ban_nflog" | grep -Pio 'src=[^\s]+' | grep -Po "$localrange" >"$ban_ip"

### IPSET/IPTABLES FOR BANIP
$ipset -L banip >/dev/null 2>&1
if [ $? -ne 0 ]; then
    $ipset -! create banip hash:net family inet hashsize 1024 maxelem 65536
else
    $ipset -! flush banip
fi
for ip in $(cat $ban_ip | $reorganize | uniq); do
    $ipset -! add banip "$ip"
done
$iptables -t mangle -I PREROUTING -i $lan -m set --match-set banip src,dst -j DROP
$iptables -I INPUT -i $lan -m set --match-set banip src,dst -j DROP
$iptables -I FORWARD -i $lan -m set --match-set banip src,dst -j DROP
echo "Done"
