#!/bin/bash
# by maravento.com

## Iptables Firewall
## Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
## Sockets: ss -ltuna
## Ports: /etc/services
## check: https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt

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

echo "Iptables Start. Wait..."
#printf "\n"

## VARIABLES ##
# paths
ip6tables=/usr/sbin/ip6tables
iptables=/usr/sbin/iptables
ipset=/usr/sbin/ipset
aclroute=/etc/acl
# interfaces
wan=eth0
lan=eth1
# IP/netmask
local=192.168.0.0
netmask=24
# IP/MAC server
# Command to get active interfaces (except lo) (Name/IPv4/MAC) (Replace with your server IPv4/MAC):
# join <(ip -o -br link | sort) <(ip -o -br addr | sort) | awk '$2=="UP" {print $1,$6,$3}' | sed -Ee 's./[0-9]+..'
ipserver=192.168.0.10
macserver=00:00:00:00:00:00

## KERNEL RULES ##
echo "Kerner Rules..."

# Zero all packets and counters
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

# Flush routing cache and blackhole
ip route flush cache
ip route del blackhole 0.0.0.0/0 2>/dev/null

# IPv4 Rules
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
#$iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o $wan -j TCPMSS --clamp-mss-to-pmtu
# load balancing or multiple wan
#echo 0 /proc/sys/net/ipv4/conf/all/rp_filter  # default 2

# IPv6 Rules
# Important: If you set "echo 1" (disable IPv6), Squid it will display the message:
# WARNING: BCP 177 violation. Detected non-functional IPv6 loopback
echo 0 >/proc/sys/net/ipv6/conf/all/disable_ipv6     # default 0
echo 0 >/proc/sys/net/ipv6/conf/default/disable_ipv6 # default 0
echo 0 >/proc/sys/net/ipv6/conf/lo/disable_ipv6      # default 0

## GLOBAL RULES ##
echo "Global Rules..."

# Global Policies IPv4 (DROP or ACCEPT)
$iptables -P INPUT ACCEPT
$iptables -P FORWARD ACCEPT
$iptables -P OUTPUT ACCEPT

# Global Policies IPv6 (DROP or ACCEPT)
$ip6tables -P INPUT DROP
$ip6tables -P FORWARD DROP
$ip6tables -P OUTPUT DROP

# LOOPBACK
$iptables -t nat -A PREROUTING -i lo -j ACCEPT
$iptables -t mangle -A PREROUTING -i lo -j ACCEPT
$iptables -t filter -A INPUT -i lo -j ACCEPT
$iptables -t filter -A FORWARD -i lo -j ACCEPT
$iptables -t filter -A OUTPUT -o lo -j ACCEPT

# LOCALHOST
$iptables -t mangle -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP

## GATEWAY RULES ##
echo "Gateway Rules..."

# SYADMIN
# Audit Ports: ssh (8282) webmin (10000), smbaudit (10100), sqstat audit (10200), sarg audit (10300)
aports="8282,10000,10100,10200,10300"
# add your sysadmin mac address to control audit ports
sysadmin="00:00:00:00:00:00"
for mac in $sysadmin; do
    for protocol in tcp udp; do
        $iptables -t mangle -A PREROUTING -i $lan -p $protocol -m multiport --dports $aports -m mac --mac-source $mac -j ACCEPT
        $iptables -A INPUT -i $lan -p $protocol -m multiport --dports $aports -m mac --mac-source $mac -j ACCEPT
        $iptables -A FORWARD -i $lan -p $protocol -m multiport --dports $aports -m mac --mac-source $mac -j ACCEPT
    done
done
# Block Audit Ports
for protocol in tcp udp; do
    $iptables -t mangle -A PREROUTING -i $lan -p $protocol -m multiport --dports $aports -j DROP
    $iptables -A INPUT -i $lan -p $protocol -m multiport --dports $aports -j DROP
    $iptables -A FORWARD -i $lan -p $protocol -m multiport --dports $aports -j DROP
done

# MASQUERADE (share internet with LAN)
$iptables -t nat -A POSTROUTING -s $local/$netmask -o $wan -j MASQUERADE

# LAN ---> PROXY <--- INTERNET
$iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
$iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
$iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# MACUNLIMITED (For Access Points, Switch, etc)
for mac in $(awk -F";" '{print $2}' $aclroute/mac-unlimited.txt); do
    $iptables -t mangle -A PREROUTING -i $lan -m mac --mac-source $mac -j ACCEPT
    $iptables -A INPUT -i $lan -m mac --mac-source $mac -j ACCEPT
    $iptables -A FORWARD -i $lan -m mac --mac-source $mac -j ACCEPT
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
        $iptables -t mangle -A PREROUTING -i $lan -m mac --mac-source $mac -s $ip -j ACCEPT
        ips="$ips\n$ip"
        macs="$macs\n$mac"
    done
    echo -e $ips >$path_ips
    echo -e $macs >$path_macs
}
create_acl $mac2ip
$iptables -t mangle -A PREROUTING -i $lan -j DROP

## GATEWAY PORTS ##
echo "Gateway Ports..."

# RFC 2131 DHCP BOOTP protocol (67,68), NETBios (137:139), Microsoft-DS and SMB (445), SNMP (162), NTP (123), Open cups (printing service) udp/tcp for lan users IPP (631)
gports="67,68,137:139,445,162,123,631"
for mac in $(awk -F";" '{print $2}' $aclroute/mac-*); do
    for protocol in tcp udp; do
            $iptables -t mangle -A PREROUTING -i $lan -p $protocol -m multiport --dports $gports -m mac --mac-source $mac -j ACCEPT
            $iptables -A INPUT -i $lan -p $protocol -m multiport --dports $gports -m mac --mac-source $mac -j ACCEPT
            $iptables -A FORWARD -i $lan -p $protocol -m multiport --dports $gports -m mac --mac-source $mac -j ACCEPT
    done
done

## DNS PORTS ##
echo "DNS Ports..."

# DNS Public Server (Google) + Stubby (127.0.0.1 192.168.X.X)
dns="8.8.8.8 8.8.4.4 192.168.1.2 127.0.0.1"
# DNS OpenDNS (Optional)
#dns="208.67.222.222 208.67.220.220"
# DNS Ports
dnsports="53,853,5353,5355"
for mac in $(awk -F";" '{print $2}' $aclroute/mac-*); do
    for ip in $dns; do
       for protocol in tcp udp; do
            # mDNS (multicast DNS) (port 5353) and 239.255.255.250 UPnP/SSDP
            $iptables -A INPUT -i $lan -s 224.0.0.0/4 -m mac --mac-source $mac -j ACCEPT
            # Link local networks
            $iptables -A INPUT -i $lan -s 169.254.0.0/16 -m mac --mac-source $mac -j ACCEPT
            # DNS PORTS: DNS (53), DNS over TLS DoT (853), Multicast DNS Bonjour-Apple, LLMNR-Microsoft, Avanhi-Linux, Link-Local Multicast LLMNR (5353)
            $iptables -A INPUT -i $lan -s $ip -p $protocol -m multiport --dports $dnsports -m state --state ESTABLISHED -m mac --mac-source $mac -j ACCEPT
            $iptables -A FORWARD -i $lan -d $ip -p $protocol -m multiport --dports $dnsports -m mac --mac-source $mac -j ACCEPT
            $iptables -A OUTPUT -d $ip -p $protocol -m multiport --dports $dnsports -j ACCEPT
        done
    done
done

## INTERNET PORTS (FOR CLIENTS) ##
echo "Internet Ports..."

# Commons Ports (Optional)
for mac in $(awk -F";" '{print $2}' $aclroute/mac-*); do
    for protocol in tcp udp; do
        # skype for business, lync -SfB/Lync-, teams (TCP 5061, UDP 40000–49999, TCP/UDP 40000–59999, TCP 55000–65535, TCP 8057, UDP 8104)
        #$iptables -A INPUT -i $lan -p $protocol -m multiport --dports 3478:3481,8104,50000:60000,8104 -m mac --mac-source $mac -j ACCEPT
        #$iptables -A FORWARD -i $lan -p $protocol -m multiport --dports 3478:3481,8104,50000:60000,8104 -m mac --mac-source $mac -j ACCEPT
        # whatsapp (TCP: 4244,5223,5228,5242 TCP/UDP: 59234, 50318 UDP: 3478,45395)
        #$iptables -A INPUT -i $lan -p $protocol -m multiport --dports 4244:5242,3478,45395,50318,59234 -m mac --mac-source $mac -j ACCEPT
        #$iptables -A FORWARD -i $lan -p $protocol -m multiport --dports 4244:5242,3478,45395,50318,59234 -m mac --mac-source $mac -j ACCEPT
        # XMPP (TCP/UDP 5222,5233,5298 TCP 5223,5269,8010), Whatsapp, iChat (TCP/UDP 5222)
        #$iptables -A INPUT -i $lan -p $protocol --dport xmpp-client -m mac --mac-source $mac -j ACCEPT
        #$iptables -A INPUT -i $lan -p $protocol -m multiport --dports 5222,5269,5298,8010,5190,5220 -m mac --mac-source $mac -j ACCEPT
        #$iptables -A FORWARD -i $lan -p $protocol --dport xmpp-client -j ACCEPT
        #$iptables -A FORWARD -i $lan -p $protocol -m multiport --dports 5222,5269,5298,8010,5190,5220 -m mac --mac-source $mac -j ACCEPT
        # anydesk
        #$iptables -A INPUT -i $lan -p $protocol -m multiport --dports 6568,7070 -m mac --mac-source $mac -j ACCEPT
        #$iptables -A FORWARD -i $lan -p $protocol -m multiport --dports 6568,7070 -m mac --mac-source $mac -j ACCEPT
        # SMTP/SSMTP/IMAP/IMAPS/POP3/POP3S/POP3PASS (25,106,143,465,587,993,110,995)
        #$iptables -A INPUT -i $lan -p $protocol -m multiport --dports 25,106,143,465,587,993,110,995 -m mac --mac-source $mac -j ACCEPT
        #$iptables -A FORWARD -i $lan -p $protocol -m multiport --dports 25,106,143,465,587,993,110,995 -m mac --mac-source $mac -j ACCEPT
    done
done

## SECURITY RULES ##
echo "Security Rules..."

# syn_flood
$iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
$iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
$iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
$iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
$iptables -A INPUT -p tcp --tcp-flags ACK,FIN FIN -j DROP
$iptables -A INPUT -p tcp --tcp-flags ACK,PSH PSH -j DROP
$iptables -A INPUT -p tcp --tcp-flags ACK,URG URG -j DROP

$iptables -N syn_flood
$iptables -A INPUT -p tcp --syn -j syn_flood
$iptables -A syn_flood -m limit --limit 500/s --limit-burst 2000 -j RETURN
$iptables -A syn_flood -j NFLOG --nflog-prefix 'synflood'
$iptables -A syn_flood -j DROP

# Invalid Packages
#$iptables -t mangle -A PREROUTING -i $lan -m conntrack --ctstate INVALID -j NFLOG --nflog-prefix 'invalid'
$iptables -t mangle -A PREROUTING -i $lan -m conntrack --ctstate INVALID -j DROP

# ICMP (ping) (Optional)
#$iptables -t mangle -A PREROUTING -p icmp -j NFLOG --nflog-prefix 'icmp'
$iptables -t mangle -A PREROUTING -p icmp -j DROP

# Limit the available bandwidth for each IP (Optional)
#$iptables -A INPUT -p tcp -m connlimit --connlimit-above 50 -j NFLOG --nflog-prefix 'bw_limit'
#$iptables -A INPUT -p tcp -m connlimit --connlimit-above 50 -j REJECT

# Number of connections per minute from an IP address (Optional)
#$iptables -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 10/minute --limit-burst 10 -j NFLOG --nflog-prefix 'conn_limit'
#$iptables -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 10/minute --limit-burst 10 -j ACCEPT

# Block Spoofed Packets (Optional)
#for ip in $(sed '/#.*/d' $aclroute/ipsreserved.txt); do
#    $iptables -A INPUT -i $lan -s $ip -j NFLOG --nflog-prefix 'spoof'
#    $iptables -A INPUT -i $lan -s $ip -j DROP
#done

# Protection against port scanning (Optional)
#$iptables -N port-scanning
#$iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN
#$iptables -A port-scanning -j NFLOG --nflog-prefix 'portscan'
#$iptables -A port-scanning -j DROP

# BLOCKPORTS (Remove or add ports to block TCP/UDP):
# path: /etc/acl/blockports.txt
# Echo (7), CHARGEN (19), FTP (20, 21), SSH (22), TELNET (23), 6to4 (41,43,44,58,59,60,3544), FINGER (79), SSDP (2869,1900,5000), RDP-MS WBT Server - Windows Terminal Serve (3389), RFB-VNC (5900), TOR Ports (9001,9050,9150), Brave Tor (8008,8443,9001:9004,9090,9101:9103,9030,9031,9050,9132:9159), IBM HTTP Server administration default (TCP/UDP 8008), SqueezeCenter/Cherokee/Openfire (9090), IPP (631), DCOM TCP Port & RPC Endpoint Mapper & RDC/DCE [Endpoint Mapper] – Microsoft networks (135), WinRM TCP Ports HTTP/HTTPS (5985:5986), TFTP (69) Trojans (10080), IRC (6660-6669), Trojans/Metasploit (4444), SQL inyection/XSS (8088, 8888), bittorrent (6881-6889 58251-58252,58687,6969) others P2P (1337,2760,4662,4672), Cryptomining (3333,5555,6666,7777,8848,9999,14444,14433,45560), Lightweight Directory Access protocol (LDAP) (389,636,3268,3269,10389,10636), Kerberos (88), WINS (42,1512), SUN.RPC - rpcbind [Remote Procedure Calls] (111), Barkley r-services and r-commands [e.g., rlogin, rsh, rexec] (512-514), Microsoft SQL Server [ms-sql-s] (1433), Microsoft SQL Monitor [ms-sql-m] (1434), TFTP (69), SNMP (161), VoIP - H.323 (1719/UDP 1720/TCP), Microsoft Point-to-Point Tunneling protocol PPTP - VPN (1723), SIP (5060, 5061), SANE network scanner (6566), RTSP Nat Slipstreaming (TCP 554,5060:5061,1719:1720), BTC/ETH (8332,8333,8545,30303)
$ipset -L blockports >/dev/null 2>&1
if [ $? -ne 0 ]; then
    $ipset -! create blockports bitmap:port range 0-65535
else
    $ipset -! flush blockports
fi
for blports in $(cat $aclroute/blockports.txt | sort -V -u); do
    $ipset -! add blockports $blports
done
$iptables -t mangle -A PREROUTING -m set --match-set blockports dst -j NFLOG --nflog-prefix 'blockports'
$iptables -t mangle -A PREROUTING -m set --match-set blockports dst -j DROP
$iptables -A INPUT -m set --match-set blockports src -j NFLOG --nflog-prefix 'blockports'
$iptables -A INPUT -m set --match-set blockports src -j DROP
$iptables -A FORWARD -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -A FORWARD -m set --match-set blockports src,dst -j DROP

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
#$iptables -A INPUT -m set --match-set blockzone src,dst -j DROP
#$iptables -A FORWARD -m set --match-set blockzone src,dst -j DROP
#$iptables -t mangle -A PREROUTING -m set --match-set blockzone src,dst -j DROP

## ACL RULES ##
echo "ACL Rules..."

# MACPROXY (Port 8000 to 3128 - Opcion 252 DHCP)
for mac in $(awk -F";" '{print $2}' $aclroute/mac-proxy.txt); do
    $iptables -t mangle -A PREROUTING -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -A INPUT -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -A FORWARD -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
done

# MACTRANSPARENT (Not recommended) (Default for http: 80. Default for squid: 8080 change to squid transparent-intercept port: 8085)
#for mac in $(awk -F";" '{print $2}' $aclroute/mac-transparent.txt); do
#    $iptables -t nat -A PREROUTING -i $lan -p tcp --dport 80 -m mac --mac-source $mac -j REDIRECT --to-port 8085
#    $iptables -A INPUT -i $lan -p tcp --dport 8085 -m mac --mac-source $mac -j ACCEPT
#    $iptables -A FORWARD -i $lan -p tcp -m multiport --dports 443,8085 -m mac --mac-source $mac -j ACCEPT
#done

# MACLIMITED (Port 8000 to 3128 - Opcion 252 DHCP)
# Important: Limited MAC addresses are blocked by the "by MAC" rule in Squid
limited=$(awk -F";" '{print $2}' $aclroute/mac-limited.txt)
echo -e "$limited" >$aclroute/squid_maclimited.txt
for mac in $(echo -e "$limited"); do
    $iptables -t mangle -A PREROUTING -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -A INPUT -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
    $iptables -A FORWARD -i $lan -p tcp -m multiport --dports 8000,3128 -m mac --mac-source $mac -j ACCEPT
done

## END ## 
echo "Drop All..."
$iptables -A INPUT -s 0.0.0.0/0 -j DROP
$iptables -A FORWARD -d 0.0.0.0/0 -j DROP

echo "iptables Load at: $(date)" | tee -a /var/log/syslog
echo "Done"
