#!/bin/bash
# by maravento.com

# Iptables Firewall

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

# Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
# Ports: /etc/services
# check: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt

echo "Iptables Start..."

### VARIABLES ###
# paths
ip6tables=/usr/sbin/ip6tables
iptables=/usr/sbin/iptables
ipset=/usr/sbin/ipset
aclroute=/etc/acl
# net
internet=eth0
lan=eth1
local=192.168.0.0
netmask=24
# Command to get active interfaces (except lo) (Name/IPv4/MAC) (Replace with your server IPv4/MAC):
# join <(ip -o -br link | sort) <(ip -o -br addr | sort) | awk '$2=="UP" {print $1,$6,$3}' | sed -Ee 's./[0-9]+..'
ipserver=192.168.0.10
macserver=00:00:00:00:00:00

####################
### KERNEL RULES ###
####################

echo "Load Kerner Rules. Wait..."

### Zero all packets and counters ###
$iptables -F
$iptables -X
$iptables -t nat -F
$iptables -t nat -X
$iptables -t mangle -F
$iptables -t mangle -X
$iptables -t raw -F
$iptables -t raw -X
$iptables -t security -F
$iptables -t security -X
$iptables -Z
$iptables -t nat -Z
$iptables -t mangle -Z

### TRAFFIC CUTTING IN CASE OF ATTACK ###
#$iptables -P INPUT DROP
#$iptables -P FORWARD DROP
#$iptables -P OUTPUT DROP
#$iptables -t nat -P PREROUTING DROP
#$iptables -t mangle -A PREROUTING -j DROP
#echo 0 > /proc/sys/net/ipv4/ip_forward
#ip aclroute add blackhole 0.0.0.0
#$iptables -t raw -A PREROUTING ! -i lo -m addrtype --src-type UNSPEC -j DROP
#$iptables -t raw -A PREROUTING ! -i lo -m addrtype --src-type LOCAL -j DROP

### IPv4 RULES ###
# syncookies
echo 1 >/proc/sys/net/ipv4/tcp_syncookies
# Disables IP source routing
echo 0 >/proc/sys/net/ipv4/conf/all/send_redirects     # default 1
echo 0 >/proc/sys/net/ipv4/conf/default/send_redirects # default 1
#echo 0 > /proc/sys/net/ipv4/conf/default/accept_source_aclroute # default 1
# Enable Log Spoofed Packets, Source aclrouted Packets, Redirect Packets
echo 1 >/proc/sys/net/ipv4/conf/all/log_martians     # default 0
echo 1 >/proc/sys/net/ipv4/conf/default/log_martians # default 0
# Helps against MITM attacks (If you have problems with your lan, change to 1)
echo 0 >/proc/sys/net/ipv4/conf/all/secure_redirects     # default 1
echo 0 >/proc/sys/net/ipv4/conf/default/secure_redirects # default 1
# Don't proxy arp for anyone
echo 1 >/proc/sys/net/ipv4/conf/all/arp_filter # default 0
# Increase the networking port range
echo 1024 65535 >/proc/sys/net/ipv4/ip_local_port_range # default 32768 60999
# Enable a fix for RFC1337 - time-wait assassination hazards in TCP
echo 1 >/proc/sys/net/ipv4/tcp_rfc1337 # default 0
# Block SYN attacks
echo 20000 >/proc/sys/net/ipv4/tcp_max_syn_backlog # default 1024
echo 1 >/proc/sys/net/ipv4/tcp_synack_retries      # default 5
echo 5 >/proc/sys/net/ipv4/tcp_syn_retries         # default 6
# Disable IPv4 ICMP Redirect Acceptance
echo 0 >/proc/sys/net/ipv4/conf/all/accept_redirects     # default 1
echo 0 >/proc/sys/net/ipv4/conf/default/accept_redirects # default 1
# Ignore all incoming ICMP echo requests
echo 1 >/proc/sys/net/ipv4/icmp_echo_ignore_all # default 0
# Disables packet forwarding (NAT)
echo 1 >/proc/sys/net/ipv4/ip_forward # default 0
# length of time an orphaned (unreferenced) connection will wait before it is aborted
echo 30 >/proc/sys/net/ipv4/tcp_fin_timeout # default 60
# frequency of TCP keepalive probes sent before deciding that a connection is broken
echo 5 >/proc/sys/net/ipv4/tcp_keepalive_probes # default 9
# determines how often TCP keepalive packets are sent to keep a connection alive
echo 15 >/proc/sys/net/ipv4/tcp_keepalive_intvl # default 75
# specify the maximum number of packets per processing queue
echo 20000 >/proc/sys/net/core/netdev_max_backlog # default 1000
# pmtu
echo 1 >/proc/sys/net/ipv4/ip_no_pmtu_disc # default 0
# pmtu (alternative)
#$iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o $internet -j TCPMSS --clamp-mss-to-pmtu

### IPv6 RULES ###
# Important: If you set "echo 1" (disable IPv6), Squid it will display the message:
# WARNING: BCP 177 violation. Detected non-functional IPv6 loopback
echo 0 >/proc/sys/net/ipv6/conf/all/disable_ipv6     # default 0
echo 0 >/proc/sys/net/ipv6/conf/default/disable_ipv6 # default 0
echo 0 >/proc/sys/net/ipv6/conf/lo/disable_ipv6      # default 0

echo "OK"

####################
### GLOBAL RULES ###
####################

echo "Loading Global Rules. Wait..."

### Global Policies IPv4 (DROP or ACCEPT) ###
$iptables -P INPUT ACCEPT
$iptables -P FORWARD ACCEPT
$iptables -P OUTPUT ACCEPT

### Global Policies IPv6 (DROP or ACCEPT) ###
$ip6tables -P INPUT DROP
$ip6tables -P FORWARD DROP
$ip6tables -P OUTPUT DROP

### LOOPBACK ###
$iptables -w -t filter -A INPUT -i lo -j ACCEPT
$iptables -w -t filter -A FORWARD -i lo -j ACCEPT
$iptables -w -t filter -A OUTPUT -o lo -j ACCEPT
$iptables -w -t nat -A PREROUTING -i lo -j ACCEPT
$iptables -w -t mangle -A PREROUTING -i lo -j ACCEPT

echo "OK"

####################
## LOCALNET RULES ##
####################

echo "Loading localnet Rules. Wait..."

# LOCALHOST
$iptables -w -t mangle -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP

# ACCESS TO LOCAL NETWORK
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
        $iptables -w -t mangle -A PREROUTING -i $lan -m mac --mac-source $mac -s $ip -j ACCEPT
        ips="$ips\n$ip"
        macs="$macs\n$mac"
    done
    echo -e $ips >$path_ips
    echo -e $macs >$path_macs
}
create_acl $mac2ip
$iptables -w -t mangle -A PREROUTING -i $lan -j DROP

# SYADMIN
# Audit Ports: ssh (8282) webmin (10000), smbaudit (10100), sqstat audit (10200), sarg audit (10300)
APORTS="8282,10000,10100,10200,10300"
# add your sysadmin mac address to control audit ports
sysadmin="00:00:00:00:00:00"
for mac in $sysadmin; do
    for protocol in $(echo tcp udp); do
        $iptables -w -A INPUT -p $protocol -m multiport --dports $APORTS -m mac --mac-source $mac -j ACCEPT
        $iptables -w -A FORWARD -p $protocol -m multiport --dports $APORTS -m mac --mac-source $mac -j ACCEPT
        $iptables -w -t mangle -A PREROUTING -p $protocol -m multiport --dports $APORTS -m mac --mac-source $mac -j ACCEPT
    done
done
# Block Audit Ports
for protocol in $(echo tcp udp); do
    $iptables -w -A INPUT -p $protocol -m multiport --dports $APORTS -j DROP
    $iptables -w -A FORWARD -p $protocol -m multiport --dports $APORTS -j DROP
    $iptables -w -t mangle -A PREROUTING -p $protocol -m multiport --dports $APORTS -j DROP
done
# MACUNLIMITED
for mac in $(awk -F";" '{print $2}' $aclroute/mac-unlimited.txt); do
    $iptables -w -t nat -A PREROUTING -i $lan -m mac --mac-source $mac -j ACCEPT
    $iptables -w -A INPUT -i $lan -m mac --mac-source $mac -j ACCEPT
    $iptables -w -A FORWARD -i $lan -m mac --mac-source $mac -j ACCEPT
    $iptables -w -t mangle -A PREROUTING -i $lan -m mac --mac-source $mac -j ACCEPT
done

# LOCALNETWORK
for mac in $(awk -F";" '{print $2}' $aclroute/mac-*); do
    $iptables -w -A INPUT -i $lan -s $local/$netmask -m mac --mac-source $mac -j ACCEPT
    $iptables -w -A FORWARD -i $lan -d $local/$netmask -m mac --mac-source $mac -j ACCEPT
    $iptables -w -t mangle -A PREROUTING -i $lan -d $local/$netmask -m mac --mac-source $mac -j ACCEPT
done

# MASQUERADE (share internet with LAN)
$iptables -w -t nat -A POSTROUTING -s $local/$netmask -o $internet -j MASQUERADE

# LAN ---> PROXY <--- INTERNET
$iptables -w -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
$iptables -w -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
$iptables -w -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS Public Server (8.8.8.8 8.8.4.4) with DNS PORT (53), DNS over TLS DoT (853), Stubby (127.0.0.1 192.168.0.10), Multicast DNS Bonjour-Apple, LLMNR-Microsoft, Avanhi-Linux, Link-Local Multicast LLMNR (5353)
dns="8.8.8.8 8.8.4.4 127.0.0.1 192.168.1.10"
for IP in $dns; do
    for protocol in $(echo tcp udp); do
        $iptables -w -A INPUT -i $lan -s $IP -p $protocol -m multiport --dports 53,853,5353,5355 -m state --state ESTABLISHED -j ACCEPT
        $iptables -w -A FORWARD -i $lan -d $IP -p $protocol -m multiport --dports 53,853,5353,5355 -j ACCEPT
        $iptables -w -A OUTPUT -d $IP -p $protocol -m multiport --dports 53,853 -j ACCEPT
    done
done

# COMMONS LOCALPORTS (Uncomment ports you need)
for protocol in $(echo tcp udp); do
    # Open cups (printing service) udp/tcp for lan users IPP (631)
    #$iptables -w -A INPUT -i $lan -p $protocol --dport 631 -j ACCEPT
    # NTP (allow time sync via NTP)
    #$iptables -w -A INPUT -i $lan -m state --state NEW -p $protocol --dport 123 -j ACCEPT
    # skype for business, lync -SfB/Lync-, teams (TCP 5061, UDP 40000–49999, TCP/UDP 40000–59999, TCP 55000–65535, TCP 8057, UDP 8104)
    #$iptables -w -A INPUT -i $lan -p $protocol -m multiport --dports 3478:3481,8104,50000:60000,8104 -j ACCEPT
    # whatsapp (TCP: 4244,5223,5228,5242 TCP/UDP: 59234, 50318 UDP: 3478,45395)
    #$iptables -w -A INPUT -i $lan -p $protocol -m multiport --dports 4244:5242,3478,45395,50318,59234 -j ACCEPT
    # XMPP (TCP/UDP 5222,5233,5298 TCP 5223,5269,8010), Whatsapp, iChat (TCP/UDP 5222)
    #$iptables -w -A INPUT -i $lan -p $protocol --dport xmpp-client -j ACCEPT
    #$iptables -w -A INPUT -i $lan -p $protocol -m multiport --dports 5222,5269,5298,8010,5190,5220 -j ACCEPT
    #$iptables -w -A FORWARD -i $lan -p $protocol --dport xmpp-client -j ACCEPT
    #$iptables -w -A FORWARD -i $lan -p $protocol -m multiport --dports 5222,5269,5298,8010,5190,5220 -j ACCEPT
    # anydesk
    #$iptables -w -A INPUT -i $lan -p $protocol -m multiport --dports 6568,7070 -j ACCEPT
    #$iptables -w -A FORWARD -i $lan -p $protocol -m multiport --dports 6568,7070 -j ACCEPT
    # SAMBA

done

echo "OK"

###########################
## GLOBAL SECURITY RULES ##
###########################

echo "Loading Security Rules. Wait..."

# syn_flood
$iptables -w -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
$iptables -w -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
$iptables -w -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
$iptables -w -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
$iptables -w -A INPUT -p tcp --tcp-flags ACK,FIN FIN -j DROP
$iptables -w -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
$iptables -w -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP

$iptables -N syn_flood
$iptables -w -A INPUT -p tcp --syn -j syn_flood
$iptables -w -A syn_flood -m limit --limit 500/s --limit-burst 2000 -j RETURN
$iptables -w -A syn_flood -j NFLOG --nflog-prefix 'synflood'
$iptables -w -A syn_flood -j DROP

# Limit the available bandwidth for each IP
$iptables -w -A INPUT -p tcp --dport 80 -m connlimit --connlimit-above 50 -j NFLOG --nflog-prefix 'BW_limit'
$iptables -w -A INPUT -p tcp --dport 80 -m connlimit --connlimit-above 50 -j REJECT

# Number of connections per minute from an IP address
$iptables -w -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 10/minute --limit-burst 10 -j NFLOG --nflog-prefix 'CONN_limit'
$iptables -w -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 10/minute --limit-burst 10 -j ACCEPT

# Invalid Packages
$iptables -w -t mangle -A PREROUTING -i $lan -m conntrack --ctstate INVALID -j NFLOG --nflog-prefix 'invalid'
$iptables -w -t mangle -A PREROUTING -i $lan -m conntrack --ctstate INVALID -j DROP

# Block Spoofed Packets
for IP in $(sed '/#.*/d' $aclroute/ipsreserved.txt); do
    $iptables -w -A INPUT -i $lan -s $IP -j NFLOG --nflog-prefix 'spoof'
    $iptables -w -A INPUT -i $lan -s $IP -j DROP
done

# ICMP (ping)
#$iptables -w -t mangle -A PREROUTING -p icmp -j NFLOG --nflog-prefix 'icmp'
$iptables -w -t mangle -A PREROUTING -p icmp -j DROP

# Protection against port scanning
$iptables -N port-scanning
$iptables -w -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
$iptables -w -A port-scanning -j NFLOG --nflog-prefix 'portscan'
$iptables -w -A port-scanning -j DROP

# Port Speed Limit (experimental rule)
# Length of a packet + maximum length of an ethernet frame: 1518 bytes = 12144 bits = 12 Kbits
# Equation: packets x 12 K/sec = speed in Kbps
# Example: 17 packets/sec = approximately 200 Kbps
# Example: 60 packets/sec = approximately 700 Kbps
#PORTSPEED="80,8080,8081,443"
#$iptables -w -A INPUT -i $lan -p tcp -m multiport --dports $PORTSPEED -m hashlimit --hashlimit-above 60/sec --hashlimit-mode srcip --hashlimit-name all -j NFLOG --nflog-prefix 'Port_limit'
#$iptables -w -A INPUT -i $lan -p tcp -m multiport --dports $PORTSPEED -m hashlimit --hashlimit-above 60/sec --hashlimit-mode srcip --hashlimit-name all -j DROP

# BLOCKPORTS (Remove or add ports to block TCP/UDP):
# path: /etc/acl/blockports.txt
# Echo (7), CHARGEN (19), FTP (20, 21), SSH (22), TELNET (23), SMTP/SSMTP/IMAP/IMAPS/POP3/POP3S/POP3PASS (25,106,143,465,587,993,110,995), 6to4 (41,43,44,58,59,60,3544), FINGER (79), SSDP (2869,1900,5000), RDP-MS WBT Server - Windows Terminal Serve (3389), RFB-VNC (5900), TOR Ports (9001,9050,9150), Brave Tor (8008,8443,9001:9004,9090,9101:9103,9030,9031,9050,9132:9159), IBM HTTP Server administration default (TCP/UDP 8008), SqueezeCenter/Cherokee/Openfire (9090), IPP (631), DCOM TCP Port & RPC Endpoint Mapper & RDC/DCE [Endpoint Mapper] – Microsoft networks (135), WinRM TCP Ports HTTP/HTTPS (5985:5986), TFTP (69) Trojans (10080), IRC (6660-6669), Trojans/Metasploit (4444), SQL inyection/XSS (8088, 8888), bittorrent (6881-6889 58251-58252,58687,6969) others P2P (1337,2760,4662,4672), RFC 2131 DHCP BOOTP protocol (67,68), Cryptomining (3333,5555,6666,7777,8848,9999,14444,14433,45560), Lightweight Directory Access protocol (LDAP) (389,636,3268,3269,10389,10636), Kerberos (88), WINS (42,1512), SUN.RPC - rpcbind [Remote Procedure Calls] (111), Barkley r-services and r-commands [e.g., rlogin, rsh, rexec] (512-514), Microsoft SQL Server [ms-sql-s] (1433), Microsoft SQL Monitor [ms-sql-m] (1434), TFTP (69), SNMP (161), VoIP - H.323 (1719/UDP 1720/TCP), Microsoft Point-to-Point Tunneling Protocol PPTP - VPN (1723), SIP (5060, 5061), SANE network scanner (6566), RTSP Nat Slipstreaming (TCP 554,5060:5061,1719:1720)
$ipset -L blockports >/dev/null 2>&1
if [ $? -ne 0 ]; then
    $ipset -! create blockports bitmap:port range 0-65535
else
    $ipset -! flush blockports
fi
for blports in $(cat $aclroute/blockports.txt | sort -V -u); do
    $ipset -! add blockports $blports
done
$iptables -w -A INPUT -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -w -A INPUT -m set --match-set blockports src,dst -j DROP
$iptables -w -A FORWARD -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -w -A FORWARD -m set --match-set blockports src,dst -j DROP
$iptables -w -t mangle -A PREROUTING -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -w -t mangle -A PREROUTING -m set --match-set blockports src,dst -j DROP

# BLOCKZONE (optional)
# https://github.com/maravento/blackip
# select country to block and ip/range
# http://www.ipdeny.com/ipblocks/
#zone=/etc/zones
#if [ ! -d $zone ]; then mkdir -p $zone; fi
# ipset rules
#$ipset -L blockzone >/dev/null 2>&1
#if [ $? -ne 0 ]; then
#echo "set blockzone does not exist. create set..."
#$ipset -! create blockzone hash:net family inet hashsize 1024 maxelem 10000000
#else
#echo "set blockzone exist. flush set..."
#$ipset -! flush blockzone
#fi
#$ipset -! save > /tmp/ipset_blockzone.txt
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
#$ipset -! restore < /tmp/ipset_blockzone.txt

# iptables rules
#$iptables -w -A INPUT -m set --match-set blockzone src,dst -j DROP
#$iptables -w -A FORWARD -m set --match-set blockzone src,dst -j DROP
#$iptables -w -t mangle -A PREROUTING -m set --match-set blockzone src,dst -j DROP
echo "done"

echo "OK"

###############
## ACL RULES ##
###############

echo "Loading ACL Rules. Wait..."

# MACPROXY (Port 8000 to 3128 - Opcion 252 DHCP)
for mac in $(awk -F";" '{print $2}' $aclroute/mac-proxy.txt); do
    $iptables -w -A INPUT -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -w -A FORWARD -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -w -t mangle -A PREROUTING -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
done

# MACTRANSPARENT (Not recommended)
#for mac in $(awk -F";" '{print $2}' $aclroute/mac-transparent.txt); do
#    $iptables -w -t nat -A PREROUTING -i $lan -p tcp --dport 80 -m mac --mac-source $mac -j REDIRECT --to-port 8080
#    $iptables -w -A INPUT -i $lan -p tcp --dport 8080 -m mac --mac-source $mac -j ACCEPT
#    $iptables -w -A FORWARD -i $lan -p tcp -m multiport --dports 443,8080 -o $internet -m mac --mac-source $mac -j ACCEPT
#done

# MACLIMITED (Port 8000 to 3128 - Opcion 252 DHCP)
# Important: Limited MAC addresses are blocked by the "by MAC" rule in Squid
limited=$(awk -F";" '{print $2}' $aclroute/mac-limited.txt)
echo -e "$limited" >$aclroute/squid_maclimited.txt
for mac in $(echo -e "$limited"); do
    $iptables -w -A INPUT -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -w -A FORWARD -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -w -t mangle -A PREROUTING -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
done

echo "OK"

#########
## END ##
#########

echo "Drop All..."
# Optional
#$iptables -w -A INPUT -i $lan -s $local/$netmask -p tcp -m multiport --dports 3128,80,443,8080,8081,8000,53,853 -j DROP
# Drop All
$iptables -w -A INPUT -d 0/0 -j DROP
$iptables -w -A FORWARD -d 0/0 -j DROP
echo "iptables Load at: $(date)" | tee -a /var/log/syslog
