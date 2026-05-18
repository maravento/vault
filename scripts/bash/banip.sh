#!/bin/bash
# maravento.com
#
################################################################################
#
# Ban IP
# Reads NFLOG/ulogd2 syslogemu log, extracts IPs matching configured patterns,
# and blocks them via ipset/iptables for a configurable ban period.
#
################################################################################

echo "Banip Start. Wait..."
printf "\n"

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

### VARIABLES
# replace localnet interface (enpXsX)
lan="eth1"
# path to ACLs folder
aclroute=/etc/acl
# path to banip
ban_ip="$aclroute/banip.txt"
# ban_nflog option grep -f
# Notice:
# If you add an iptables rule with NFLOG, you must add the message to the nflog.txt ACL
ban_nflog="$aclroute/nflog.txt"
# syslogemu (log)
syslogemu="/var/log/ulog/syslogemu.log"
# ban time (10 min = 600 seconds - 24H = 86400)
bantime="86400"
# localrange (replace "192.168.*" with the first two octets of your local network range)
localrange="192.168.*"
# DEBUG IP
reorganize="sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n"

### VERIFY DEPENDENCIES
for cmd in ipset iptables; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found"
        exit 1
    fi
done
if ! systemctl is-active --quiet ulogd2; then
    echo "ERROR: ulogd2 is not running"
    exit 1
fi
if [ ! -f "$syslogemu" ]; then
    echo "ERROR: $syslogemu not found"
    exit 1
fi

### CREATE ACLs IF NOT EXIST
[[ -f "$ban_nflog" ]] || touch "$ban_nflog"
[[ -f "$ban_ip" ]] || touch "$ban_ip"

### BANIP CAPTURE
echo "BanIP for syslogemu..."
# add matches to ban_ip
# change option path (for local: grep -f "$ban_nflog") (for curl: grep -F "$ban_nflog")
perl -MDate::Parse -ne "print if/^(.{15})\s/&&str2time(\$1)>time-$bantime" "$syslogemu" | grep -f "$ban_nflog" | grep -Pio 'src=[^\s]+' | grep -Po "$localrange" >"$ban_ip"

### IPSET/IPTABLES FOR BANIP
ipset -L banip >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ipset -! create banip hash:net family inet hashsize 1024 maxelem 65536
else
    ipset -! flush banip
fi
for ip in $(cat $ban_ip | $reorganize | uniq); do
    ipset -! add banip "$ip"
done
iptables -C INPUT -i $lan -m set --match-set banip src -j DROP 2>/dev/null || \
    iptables -A INPUT -i $lan -m set --match-set banip src -j DROP
iptables -C FORWARD -i $lan -m set --match-set banip src -j DROP 2>/dev/null || \
    iptables -A FORWARD -i $lan -m set --match-set banip src -j DROP
echo "Done"
