#!/bin/bash
# maravento.com

## Iptables Firewall
## Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
## Sockets: ss -ltuna
## Ports: /etc/services
## check: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt

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

echo "Iptables Start. Wait..."
#printf "\n"

## VARIABLES ##
# paths
aclroute=/etc/acl
# interfaces
wan=eth0
lan=eth1
# IP/netmask
local=192.168.0.0
netmask=24
# Broadcast
broadcast=192.168.0.255
# IP/MAC server
# Command to get active interfaces (except lo) (Name/IPv4/MAC) (Replace with your server IPv4/MAC):
# join <(ip -o -br link | sort) <(ip -o -br addr | sort) | awk '$2=="UP" {print $1,$6,$3}' | sed -Ee 's./[0-9]+..'
serverip=192.168.0.10
servermac=00:00:00:00:00:00

## KERNEL RULES ##
echo "Kernel Rules..."

# Zero all packets and counters
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

# Flush routing cache and blackhole (Optional)
#ip route flush cache
#ip route del blackhole 0.0.0.0/0 2>/dev/null || true

# IPv6
# Important: If you set "=1" (disable IPv6), Squid it will display the message:
# WARNING: BCP 177 violation. Detected non-functional IPv6 loopback
#sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
#sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
#sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1
#sysctl -w net.ipv6.conf."$lan".disable_ipv6=1 >/dev/null 2>&1

# IPv4
# Disables IP source routing
sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.send_redirects=0 >/dev/null 2>&1
# Enable Log Spoofed Packets, Source aclrouted Packets, Redirect Packets
sysctl -w net.ipv4.conf.all.log_martians=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.log_martians=1 >/dev/null 2>&1
# Helps against MITM attacks (If you have problems with your lan, change to 1)
sysctl -w net.ipv4.conf.all.secure_redirects=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.secure_redirects=0 >/dev/null 2>&1
# Don't proxy arp for anyone
sysctl -w net.ipv4.conf.all.arp_filter=1 >/dev/null 2>&1
# Increase the networking port range (default 32768 60999)
sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
# Enable a fix for RFC1337 - time-wait assassination hazards in TCP
sysctl -w net.ipv4.tcp_rfc1337=1 >/dev/null 2>&1
# Block SYN attacks
sysctl -w net.ipv4.tcp_max_syn_backlog=20000 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_synack_retries=1 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_syn_retries=5 >/dev/null 2>&1
# Disable IPv4 ICMP Redirect Acceptance
sysctl -w net.ipv4.conf.all.accept_redirects=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.accept_redirects=0 >/dev/null 2>&1
# Ignore all incoming ICMP echo requests
sysctl -w net.ipv4.icmp_echo_ignore_all=1 >/dev/null 2>&1
# Disables packet forwarding (NAT)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
# length of time an orphaned (unreferenced) connection will wait before it is aborted
sysctl -w net.ipv4.tcp_fin_timeout=30 >/dev/null 2>&1
# frequency of TCP keepalive probes sent before deciding that a connection is broken
sysctl -w net.ipv4.tcp_keepalive_probes=5 >/dev/null 2>&1
# determines how often TCP keepalive packets are sent to keep a connection alive
sysctl -w net.ipv4.tcp_keepalive_intvl=15 >/dev/null 2>&1
# specify the maximum number of packets per processing queue
sysctl -w net.core.netdev_max_backlog=20000 >/dev/null 2>&1
# pmtu
sysctl -w net.ipv4.ip_no_pmtu_disc=1 >/dev/null 2>&1

# Enabled by default on Ubuntu 24.04
# syncookies
#sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
# protect hardlinks
#fs.protected_hardlinks=1 >/dev/null 2>&1
# enable full ASLR
#kernel.randomize_va_space=2 >/dev/null 2>&1
# disable IP source routing (security)
#sysctl -w net.ipv4.conf.default.accept_source_route=1

## GLOBAL RULES ##
echo "Global Rules..."

# Global Policies IPv4 (DROP or ACCEPT)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

### Global Policies IPv6 (Optional)
#ip6tables -P INPUT DROP
#ip6tables -P FORWARD DROP
#ip6tables -P OUTPUT DROP

# LOOPBACK
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# LOCALHOST
iptables -t mangle -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP

## SERVER RULES ##
echo "Server Rules..."

# MASQUERADE (share internet with LAN)
iptables -t nat -A POSTROUTING -s $local/$netmask -o $wan -j MASQUERADE

# LAN ---> PROXY <--- INTERNET
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# DROP LAN2WAN (Optional)
iptables -A INPUT -i $wan -s 10.0.0.0/8 -j DROP
iptables -A INPUT -i $wan -s 172.16.0.0/12 -j DROP

# Broadcast
iptables -A INPUT -i $lan -s $local/$netmask -d $broadcast -p udp -j ACCEPT

# DHCP
iptables -A INPUT -i $lan -p udp -m multiport --dports 67,68 -j ACCEPT
iptables -A OUTPUT -o $lan -p udp -m multiport --sport 67,68 -j ACCEPT

# Warning Page, Wpad, NTP
iptables -A INPUT -i $lan -p tcp -m multiport --dports 80,18443,18880,18800,123 -j ACCEPT
iptables -A FORWARD -i $lan -p tcp -m multiport --dports 80,18443,18880,18800,123 -j ACCEPT

# DNS
dns="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1"
for ip in $dns; do
    # DNS
    for proto in tcp udp; do
        iptables -A OUTPUT -d $ip -p $proto --dport 53 -j ACCEPT
        iptables -A INPUT -s $ip -p $proto --sport 53 -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A FORWARD -i $lan -d $ip -p $proto --dport 53 -j ACCEPT
        iptables -A FORWARD -o $lan -s $ip -p $proto --sport 53 -m state --state ESTABLISHED,RELATED -j ACCEPT
    done
    # DNS over TLS (DoT)
    iptables -A OUTPUT -d $ip -p tcp --dport 853 -j ACCEPT
    iptables -A INPUT -s $ip -p tcp --sport 853 -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -i $lan -d $ip -p tcp --dport 853 -j ACCEPT
    iptables -A FORWARD -o $lan -s $ip -p tcp --sport 853 -m state --state ESTABLISHED,RELATED -j ACCEPT
done

## MAC ACCESS RULE ##
echo "MAC Access..."

dhcp_conf=/etc/dhcp/dhcpd.conf
# path ips-mac dhcp
path_ips=$aclroute/dhcp_ip.txt
path_macs=$aclroute/dhcp_mac.txt
# mac2ip
mac2ip=$(sed -n '/^\s\+hardware\|^\s\+fixed/ s:hardware ethernet \|fixed-address ::p' $dhcp_conf | sed 's/;//')
create_acl() {
    ips="# ips"
    macs="# macs"
    while [ "$1" ]; do
        mac="$1"
        shift
        ip="$1"
        shift
        iptables -t mangle -A PREROUTING -i $lan -m mac --mac-source $mac -s $ip -j ACCEPT
        ips="$ips\n$ip"
        macs="$macs\n$mac"
    done
    echo -e $ips >$path_ips
    echo -e $macs >$path_macs
}
create_acl $mac2ip
iptables -t mangle -A PREROUTING -i $lan -j DROP

# MACUNLIMITED (For Access Points, Switch, etc)
for mac in $(awk -F";" '{print $2}' $aclroute/mac-unlimited.txt); do
    iptables -A INPUT -i $lan -m mac --mac-source $mac -j ACCEPT
    iptables -A FORWARD -i $lan -m mac --mac-source $mac -j ACCEPT
done

## SERVER PORTS ##
echo "Server Rules..."

for mac in $(awk -F";" '{print $2}' $aclroute/mac-*); do
    # mDNS/Bonjour (5353), LLMNR (5355)
    iptables -A INPUT -i $lan -d 224.0.0.251 -p udp --dport 5353 -m mac --mac-source $mac -j ACCEPT
    iptables -A FORWARD -i $lan -o $lan -d 224.0.0.251 -p udp --dport 5353 -m mac --mac-source $mac -j ACCEPT
    iptables -A INPUT -i $lan -d 224.0.0.252 -p udp --dport 5355 -m mac --mac-source $mac -j ACCEPT
    iptables -A FORWARD -i $lan -o $lan -d 224.0.0.252 -p udp --dport 5355 -m mac --mac-source $mac -j ACCEPT
    # SSDP/UPnP
    iptables -A INPUT -i $lan -d 239.255.255.250 -p udp --dport 1900 -m mac --mac-source $mac -j ACCEPT
    iptables -A FORWARD -i $lan -o $lan -d 239.255.255.250 -p udp --dport 1900 -m mac --mac-source $mac -j ACCEPT
    iptables -A FORWARD -i $lan -o $lan -p udp -m multiport --dports 1900,5000 -m mac --mac-source $mac -j ACCEPT
    # DLNA
    iptables -A FORWARD -i $lan -o $lan -p tcp -m multiport --dports 2869,8200,10243 -m mac --mac-source $mac -j ACCEPT
    # IGMP
    iptables -A FORWARD -i $lan -o $lan -p igmp -m mac --mac-source $mac -j ACCEPT
    # NetBIOS
    iptables -A INPUT -i $lan -p udp -m multiport --dports 137,138 -m mac --mac-source $mac -j ACCEPT
    # SMB
    iptables -A INPUT -i $lan -p tcp -m multiport --dports 139,445 -m mac --mac-source $mac -j ACCEPT
    # Print: SNMP, SLP, ENPC
    iptables -A INPUT -i $lan -p udp -m multiport --dports 161,162,427,3289 -m mac --mac-source $mac -j ACCEPT
    iptables -A INPUT -i $lan -p tcp --dport 3289 -m mac --mac-source $mac -j ACCEPT
    # Print: IPP, Raw printing, LPD
    iptables -A INPUT -i $lan -p tcp -m multiport --dports 631,9100,515 -m mac --mac-source $mac -j ACCEPT
    # Email: SMTP (25, 465, 587), IMAP (143, 993), POP3 (110, 995).
    iptables -A FORWARD -i $lan -p tcp -m multiport --dports 25,465,587,143,993,110,995 -m mac --mac-source $mac -j ACCEPT
done

## SECURITY RULES ##
echo "Security Rules..."

# Block BitTorrent (Experimental)
#bt=$(curl -s https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/ipt/torrent.txt)
#for string in $(echo -e "$bt" | sed -e '/^#/d' -e 's:#.*::g'); do
#    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo bm -j NFLOG --nflog-prefix 'torrent'
#    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo bm -j DROP
#done

# Invalid Packages
iptables -A INPUT -i $lan -m conntrack --ctstate INVALID -j DROP

# syncflood
iptables -N syn_flood
iptables -A INPUT -i $lan -p tcp --syn -j syn_flood
iptables -A syn_flood -m limit --limit 50/s --limit-burst 200 -j RETURN
iptables -A syn_flood -j NFLOG --nflog-prefix 'synflood'
iptables -A syn_flood -j DROP
# synflood (Optional)
#iptables -A INPUT -i $lan -p tcp --tcp-flags ALL NONE -j DROP
#iptables -A INPUT -i $lan -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
#iptables -A INPUT -i $lan -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
#iptables -A INPUT -i $lan -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
#iptables -A INPUT -i $lan -p tcp --tcp-flags ACK,FIN FIN -j DROP
#iptables -A INPUT -i $lan -p tcp --tcp-flags ACK,PSH PSH -j DROP
#iptables -A INPUT -i $lan -p tcp --tcp-flags ACK,URG URG -j DROP

# Block Spoofed Packets (Optional)
#for ip in $(sed '/^\s*#/d;/^\s*$/d' "$aclroute/bogons.txt"); do
#    iptables -A INPUT -i $lan -s $ip -j NFLOG --nflog-prefix 'spoof'
#    iptables -A INPUT -i $lan -s $ip -j DROP
#done

# ICMP (ping) (Optional)
#iptables -A OUTPUT -o $lan -p icmp --icmp-type echo-request -j ACCEPT
#iptables -A INPUT -i $lan -p icmp --icmp-type echo-reply   -j ACCEPT
#iptables -A INPUT -i $lan -p icmp --icmp-type echo-request -m limit --limit 5/s --limit-burst 10 -j ACCEPT
#iptables -A OUTPUT -o $lan -p icmp --icmp-type echo-reply -j ACCEPT

# Protection against port scanning (optional)
#iptables -N port-scanning
#iptables -A INPUT -p tcp --tcp-flags ALL RST -j port-scanning
#iptables -A port-scanning -p tcp --tcp-flags ALL RST -m limit --limit 1/s --limit-burst 2 -j RETURN
#iptables -A port-scanning -j NFLOG --nflog-prefix 'portscan'
#iptables -A port-scanning -j DROP

# BLOCKZONE (optional)
# https://github.com/maravento/blackip
# select country to block and ip/range
# http://www.ipdeny.com/ipblocks/
#zone=/etc/zones
#mkdir -p $zone >/dev/null 2>&1
# ipset rules
#ipset -L blockzone >/dev/null 2>&1
#if [ $? -ne 0 ]; then
    #echo "set blockzone does not exist. create set..."
    #ipset -! create blockzone hash:net family inet hashsize 1024 maxelem 10000000
#else
    #echo "set blockzone exist. flush set..."
    #ipset -! flush blockzone
#fi
#ipset -! save > /tmp/ipset_blockzone.txt
# read file and sort (v8.32 or later)
#cat $zone/{cn,ru}.zone $aclroute/blackip.txt | sort -V -u | while read line; do
# optional: if there are commented lines
#if [ "${line:0:1}" = "#" ]; then
    #continue
#fi
# adding IPv4 addresses to the tmp list
#echo "add blockzone $line" >> /tmp/ipset_blockzone.txt
#done
# adding the tmp list of IPv4 addresses to the ddosip set of ipset
#ipset -! restore < /tmp/ipset_blockzone.txt
# iptables rules
#iptables -A INPUT -m set --match-set blockzone src -j DROP

# BLOCKPORTS (Remove or add ports to block TCP/UDP):
# path: /etc/acl/blockports.txt
# Echo (7), CHARGEN (19), 6to4 (41,43,44,58,59,60,3544), FINGER (79), TOR Ports (9001,9050,9150), Brave Tor (9001:9004,9090,9101:9103,9030,9031,9050), IRC (6660-6669), Trojans/Metasploit (4444), SQL inyection/XSS (8088, 8888), bittorrent (6881-6889 58251,58252,58687,6969) others P2P (1337,2760,4662,4672), Cryptomining (3333,5555,6666,7777,8848,9999,14444,14433,45560), WINS (42), BTC/ETH (8332,8333,8545,30303)
ipset -L blockports >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ipset -! create blockports bitmap:port range 0-65535
else
    ipset -! flush blockports
fi
for blports in $(cat $aclroute/blockports.txt | sort -V -u); do
    ipset -! add blockports $blports
done
iptables -A INPUT -i $lan -m set --match-set blockports dst -j NFLOG --nflog-prefix 'blockports'
iptables -A INPUT -i $lan -m set --match-set blockports dts -j DROP
iptables -A FORWARD -i $lan -m set --match-set blockports dst -j NFLOG --nflog-prefix 'blockports'
iptables -A FORWARD -i $lan -m set --match-set blockports dst -j DROP
iptables -A OUTPUT -m set --match-set blockports dst -j NFLOG --nflog-prefix 'blockports'
iptables -A OUTPUT -m set --match-set blockports dst -j DROP

## ACL RULES ##
echo "ACL Rules..."

# MACTRANSPARENT (Not recommended)
#for mac in $(awk -F";" '{print $2}' $aclroute/mac-transparent.txt); do
#    iptables -A INPUT -i $lan -p tcp -m multiport --dports 443,853 -m mac --mac-source $mac -j ACCEPT
#    iptables -A FORWARD -i $lan -p tcp -m multiport --dports 443,853 -m mac --mac-source $mac -j ACCEPT
#done

# MACPROXY (Port 18800 to 3128 - Opcion 252 DHCP)
for mac in $(awk -F";" '{print $2}' $aclroute/mac-proxy.txt); do
    iptables -A INPUT -i $lan -p tcp -m multiport --dports 18800,3128 -m mac --mac-source $mac -j ACCEPT
    iptables -A FORWARD -i $lan -p tcp -m multiport --dports 18800,3128 -m mac --mac-source $mac -j ACCEPT
done

## END ## 
echo "Drop All..."
iptables -A INPUT -s 0.0.0.0/0 -j NFLOG --nflog-prefix 'final-input-drop: '
iptables -A INPUT -s 0.0.0.0/0 -j DROP
iptables -A FORWARD -d 0.0.0.0/0 -j NFLOG --nflog-prefix 'final-forward-drop: '
iptables -A FORWARD -d 0.0.0.0/0 -j DROP

echo "iptables Load at: $(date)" | tee -a /var/log/syslog
echo "Done"
