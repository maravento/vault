#!/bin/bash
# maravento.com

## Iptables/Ipset Firewall O(1)
## Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
## Sockets: ss -ltuna
# Ports: /etc/services
# ============================
# Ports 0-1023:     "Well-known ports" (System/Privileged)
#                   - Require superuser privileges to bind
#                   - Standard services: HTTP(80), HTTPS(443), SSH(22), DNS(53)
#                   - FTP(21), Telnet(23), SMTP(25), etc.
# Ports 1024-49151: "Registered ports" (IANA Assigned)
#                   - Assigned by Internet Assigned Numbers Authority
#                   - User/application services without root privileges
#                   - Examples: MySQL(3306), PostgreSQL(5432), Skype(1000-10000)
# Ports 49152-65535: "Dynamic/Private ports" (Ephemeral)
#                    - Available for any use, not registered by IANA
#                    - Used for temporary/outbound connections
#                    - Client-side dynamic port assignments
# REFERENCES:
# - https://gutl.jovenclub.cu/wiki/doku.php?id=definiciones:puertos_tcp_udp
# - https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
# - RFC 6335 - Internet Assigned Numbers Authority (IANA) Procedures
# - https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

echo "Iptables Start. Wait..."
#printf "\n"

## VARIABLES ##
# paths
aclroute=/etc/acl
# interfaces
wan=eth0
lan=eth1
# LAN localnet/netmask
localnet=192.168.0.0
netmask=24
# IP/MAC server
# Command to get active interfaces (except lo) (Name/IPv4/MAC) (Replace with your server IPv4/MAC):
# join <(ip -o -br link | sort) <(ip -o -br addr | sort) | awk '$2=="UP" {print $1,$6,$3}' | sed -Ee 's./[0-9]+..'
serverip=192.168.0.10
#
# Optional
# LAN Broadcast
# broadcast=192.168.0.255
# WAN localnet/netmask 
# wan_net=$(ip -o -f inet addr show "$wan" | awk '{split($4,a,"/"); split(a[1],b,"."); print b[1]"."b[2]"."b[3]".0/"a[2]; exit}')

## KERNEL RULES ##
echo "Kernel Rules..."

# Zero all packets and counters
# Reset tables
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
# Reset counters
iptables -Z
iptables -t nat -Z
iptables -t mangle -Z
# Clear ARP and bridge
arptables -F 2>/dev/null || true
arptables -X 2>/dev/null || true
ebtables -F 2>/dev/null || true
ebtables -X 2>/dev/null || true
# Flush routing cache and blackhole (Optional)
#ip route flush cache
#ip route del blackhole 0.0.0.0/0 2>/dev/null || true
# Conntrack (Optional)
#conntrack -F 2>/dev/null || true

# IPv4
##### 🧩 SYSTEM OPTIMIZATION #####
sysctl -w fs.file-max=2097152 >/dev/null 2>&1
sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1
sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1
sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1

##### ⚙️ CONNECTION TRACKING #####
# Increase connection tracking table size for high concurrency
sysctl -w net.netfilter.nf_conntrack_max=524288 >/dev/null 2>&1
sysctl -w net.netfilter.nf_conntrack_buckets=131072 >/dev/null 2>&1

##### 🔒 SECURITY & NETWORK HARDENING #####
# Disable IP source routing (prevents IP spoofing and routing attacks)
sysctl -w net.ipv4.conf.all.accept_source_route=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.accept_source_route=0 >/dev/null 2>&1
# Disable secure redirects (protects against malicious router advertisements)
# If you experience LAN routing issues, you can temporarily set this to 1.
sysctl -w net.ipv4.conf.all.secure_redirects=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.secure_redirects=0 >/dev/null 2>&1
# Log packets with impossible or spoofed source addresses ("martians")
sysctl -w net.ipv4.conf.all.log_martians=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.log_martians=1 >/dev/null 2>&1

##### 🛡️ FILTER #####
# Enable strict reverse path filtering (drops packets with spoofed source IPs)
# Loose Mode = 2 (for networks with bonding, multiple gateways, or complex routing)
# Strict Mode = 1 (The packet must return through the same interface it arrived on.)
# Disable = 0
sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null 2>&1

##### 🌐 NETWORK PERFORMANCE & TCP PROTECTION #####
# ⚙️ Optimized TCP/IP parameters for high-performance and secure routing
# Enable TCP SYN cookies (protects against SYN flood attacks)
sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
# Increase SYN backlog queue and tune retries (helps prevent SYN flood)
sysctl -w net.ipv4.tcp_max_syn_backlog=20000 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_syn_retries=2 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_synack_retries=2 >/dev/null 2>&1
# Enable RFC1337 fix (protects against TCP TIME-WAIT assassination)
sysctl -w net.ipv4.tcp_rfc1337=1 >/dev/null 2>&1
# Expand available local port range (default: 32768–60999)
sysctl -w net.ipv4.ip_local_port_range="10000 65535" >/dev/null 2>&1
# Reduce TCP FIN timeout (faster cleanup for orphaned sockets)
sysctl -w net.ipv4.tcp_fin_timeout=30 >/dev/null 2>&1
# TCP keepalive settings (balance connection stability and resource usage)
sysctl -w net.ipv4.tcp_keepalive_time=300 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_intvl=15 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_keepalive_probes=5 >/dev/null 2>&1
# Enable TCP Fast Open (reduces latency for repeated connections)
sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
# Enable TCP performance features
sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
# Increase socket buffers
sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
sysctl -w net.core.rmem_default=262144 >/dev/null 2>&1
sysctl -w net.core.wmem_default=262144 >/dev/null 2>&1
# TCP buffer auto-tuning
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1
sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1
# Enable PMTU discovery (recommended: automatic MTU adjustment)
sysctl -w net.ipv4.ip_no_pmtu_disc=0 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
# Increase network queue size (handles bursts of incoming packets)
sysctl -w net.core.netdev_max_backlog=20000 >/dev/null 2>&1
# Increase TIME_WAIT socket capacity (important for busy NAT or proxy servers)
sysctl -w net.ipv4.tcp_max_tw_buckets=1000000 >/dev/null 2>&1
# Allow safe TIME_WAIT socket reuse (improves connection efficiency)
sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1

##### 🔁 ROUTING & FORWARDING #####
# Enable packet forwarding (required for NAT/routing)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

##### 🧩 ARP OPTIMIZATION #####
# Enable ARP filtering (prevents incorrect replies when multiple interfaces exist)
sysctl -w net.ipv4.conf.all.arp_filter=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.arp_filter=1 >/dev/null 2>&1
# ARP announce mode - only reply for local addresses
sysctl -w net.ipv4.conf.all.arp_announce=2 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.arp_announce=2 >/dev/null 2>&1
# ARP ignore mode - only respond to ARPs for IPs on receiving interface
sysctl -w net.ipv4.conf.all.arp_ignore=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.arp_ignore=1 >/dev/null 2>&1
# ARP cache tuning: reduce broadcast frequency and improve efficiency
sysctl -w net.ipv4.neigh.default.gc_stale_time=300 >/dev/null 2>&1
sysctl -w net.ipv4.neigh.default.gc_thresh1=128 >/dev/null 2>&1
sysctl -w net.ipv4.neigh.default.gc_thresh2=512 >/dev/null 2>&1
sysctl -w net.ipv4.neigh.default.gc_thresh3=1024 >/dev/null 2>&1
# Reduce ARP broadcast retries (limits ARP noise in large LANs)
sysctl -w net.ipv4.neigh.default.ucast_solicit=3 >/dev/null 2>&1
sysctl -w net.ipv4.neigh.default.mcast_solicit=2 >/dev/null 2>&1
# Base reachable time for neighbor entries
sysctl -w net.ipv4.neigh.default.base_reachable_time_ms=300000 >/dev/null 2>&1

##### 🧱 KERNEL & FILESYSTEM HARDENING #####
# Enable full ASLR (Address Space Layout Randomization)
sysctl -w kernel.randomize_va_space=2 >/dev/null 2>&1
# Protect hardlinks (prevents privilege escalation attacks)
sysctl -w fs.protected_hardlinks=1 >/dev/null 2>&1
# Protect symlinks (prevents unauthorized link access in shared directories)
sysctl -w fs.protected_symlinks=1 >/dev/null 2>&1

##### 📡 ICMP #####
# Disable sending ICMP redirects (prevents MITM via route manipulation)
sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.send_redirects=0 >/dev/null 2>&1
# Disable accepting ICMP redirects from other hosts (security hardening)
sysctl -w net.ipv4.conf.all.accept_redirects=0 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.accept_redirects=0 >/dev/null 2>&1
# Allow normal ICMP echo requests (ping)
sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
# Ignore ICMP echo requests sent to broadcast addresses (Smurf attack prevention)
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 >/dev/null 2>&1
# Ignore bogus or malformed ICMP error responses
sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 >/dev/null 2>&1
# Rate limit ICMP message generation (100 ms minimum interval)
sysctl -w net.ipv4.icmp_ratelimit=100 >/dev/null 2>&1

# IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1
sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1
# LAN IPv6
sysctl -w net.ipv6.conf.eth1.disable_ipv6=1 >/dev/null 2>&1
echo OK

## GLOBAL RULES ##
echo "Global Rules..."

# IPv4
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# IPv6
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

# LOOPBACK
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP

# WAN DROP: Local Ranges
iptables -A INPUT -i $wan -s 10.0.0.0/8 -j DROP
iptables -A INPUT -i $wan -s 172.16.0.0/12 -j DROP
#iptables -A INPUT -i $wan -s 192.168.0.0/16 -j DROP
# WAN DROP: Local Ports
iptables -A INPUT -i $wan -p tcp -m multiport --dports 80,3128,5636,10000,18100,18080,18081,18082 -j NFLOG --nflog-prefix "WAN-DROP Local Ports: "
iptables -A INPUT -i $wan -p tcp -m multiport --dports 80,3128,5636,10000,18100,18080,18081,18082 -j DROP

# MASQUERADE: NAT for LAN to share dynamic WAN IP
iptables -t nat -A POSTROUTING -s $localnet/$netmask -o $wan -j MASQUERADE
#
# SNAT example for static WAN IP (more efficient)
# wan_ip=$(ip -4 -o addr show dev "$wan" | awk '{print $4}' | cut -d/ -f1)
# iptables -t nat -A POSTROUTING -s $localnet/$netmask -o $wan -j SNAT --to-source $wan_ip

# LAN ---> PROXY <--- WAN
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# DHCP
iptables -A OUTPUT -o $wan -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A INPUT -i $wan -p udp --sport 67 --dport 68 -j ACCEPT
iptables -A INPUT -i $lan -p udp --sport 68 --dport 67 -s $localnet/$netmask -j ACCEPT
iptables -A OUTPUT -o $lan -p udp --sport 67 --dport 68 -d $localnet/$netmask -j ACCEPT

# NTP
iptables -A INPUT -i $lan -p udp --dport 123 -s $localnet/$netmask -j ACCEPT
iptables -A FORWARD -i $lan -p udp --dport 123 -s $localnet/$netmask -j ACCEPT

# Windows Update Delivery Optimization WUDO
for proto in tcp udp; do
    iptables -A FORWARD -p $proto --dport 7680 -s $localnet/$netmask -d $localnet/$netmask -j ACCEPT
done

echo OK

## MAC2IP RULES ##
echo "MAC2IP Rules..."

# MACUNLIMITED (Access Points, Switch, etc.)
if ! ipset list macunlimited &>/dev/null; then
    ipset create macunlimited hash:mac -exist
else
    ipset flush macunlimited
fi
for mac in $(awk -F";" '$2 != "" {print $2}' $aclroute/mac-unlimited.txt); do
    ipset add macunlimited $mac -exist
done
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macunlimited src -j ACCEPT
for chain in INPUT FORWARD; do
    iptables -A $chain -i $lan -m set --match-set macunlimited src -j ACCEPT
done

# MAC2IP
dhcp_conf=/etc/dhcp/dhcpd.conf
# path ips-mac dhcp
path_ips=$aclroute/dhcp_ip.txt
path_macs=$aclroute/dhcp_mac.txt
# mac2ip
mac2ip=$(sed -n '/^\s\+hardware\|^\s\+fixed/ s:hardware ethernet \|fixed-address ::p' $dhcp_conf | sed 's/;//')
# rule mac2ip
if ! ipset list macip &>/dev/null; then
    ipset create macip hash:ip,mac -exist
else
    ipset flush macip
fi
create_acl() {
    ips="# ips"
    macs="# macs"
    while [ "$1" ]; do
        mac="$1"
        shift
        ip="$1"
        shift
        # Add MAC+IP to set
        ipset add macip $ip,$mac -exist
        ips="$ips\n$ip"
        macs="$macs\n$mac"
    done
    echo -e $ips > $path_ips
    echo -e $macs > $path_macs
}
create_acl $mac2ip
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macip src,src -j ACCEPT
iptables -t mangle -A PREROUTING -i $lan -j DROP

echo OK

## PORT RULES ##
echo "Port Rules..."

# BLOCKPORTS
# path: /etc/acl/blockports.txt
# Block Direct Connections:
# HTTPs (443), HTTPs Fallback (4444,8443,9443), DoT (853,8053), DNS over QUIC DoQ (784), DoQ Fallback (8853), OpenVPN (1194), L2TP/IPsec (1701), IPsec IKE (500), IPsec NAT-T (4500), WireGuard (51820), SOCKS5 proxies (1080), Shadowsocks (7300), HTTP-Proxy Alternative (8080,8000,3129,3130).
# Block legacy, risky or potentially abusive services:
# Echo (7), CHARGEN (19), FTP (20,21), SSH (22), 6to4 (41,43,44,58,59,60,3544), FINGER (79), TOR Ports (9001,9050,9150), Brave Tor (9001:9004,9090,9101:9103,9030,9031,9050), IRC (6660-6669), Trojans/Metasploit (4444), SQL inyection/XSS (8088,8888), bittorrent (6881-6889,58251,58252,58687,6969), others P2P (1000,1007,1337,2760,4662,4672), Cryptomining (3333,5555,6666,7777,8848,9999,14444,14433,45560), WINS (42), BTC/ETH (8332,8333,8545,30303), IPP (631).
# Verificar si el set blockports existe
if ! ipset list blockports &>/dev/null; then
    ipset create blockports bitmap:port range 0-65535 -exist
else
    ipset flush blockports
fi
for blports in $(cat $aclroute/blockports.txt | sort -V -u); do
    ipset add blockports $blports -exist
done
for proto in tcp udp; do
    for chain in INPUT FORWARD; do
        iptables -A $chain -i $lan -p $proto -m set --match-set blockports dst -j NFLOG --nflog-prefix "BLOCK PORTS-${chain,,}-$proto "
        iptables -A $chain -i $lan -p $proto -m set --match-set blockports dst -j DROP
    done
done

# MAC Ports
if ! ipset list macports &>/dev/null; then
    ipset create macports hash:mac -exist
else
    ipset flush macports
fi
for mac in $(awk -F";" '$2 != "" {print $2}' $aclroute/mac-*); do
    ipset add macports $mac -exist
done
# DNS
dns="8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1"
for dnsip in $dns; do
    iptables -A FORWARD -i $lan -o $wan -m set --match-set macports src -d $dnsip -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i $lan -o $wan -m set --match-set macports src -d $dnsip -p tcp --dport 53 -j ACCEPT
done

for chain in INPUT FORWARD; do
    # WARNING PAGE HTTP (TCP 18081)
    iptables -A $chain -i $lan -p tcp --dport 18081 -m set --match-set macports src -j ACCEPT
    # PRINTERS & SCANNERS UDP: SNMP (161,162) + prnrequest/prnstatus (3910/3911)
    iptables -A $chain -i $lan -p udp -m multiport --dports 161,162,3910,3911 -m set --match-set macports src -j ACCEPT
    # PRINTERS & SCANNERS TCP: JetDirect/RAW (9100) + prnrequest/prnstatus (3910/3911)
    iptables -A $chain -i $lan -p tcp -m multiport --dports 9100,3910,3911 -m set --match-set macports src -j ACCEPT
    # STUN / TURN - VoIP, WebRTC, Videoconference
    iptables -A $chain -i $lan -p udp -m multiport --dports 3478,19302:19309 -m set --match-set macports src -j ACCEPT
    # FILE SHARING SAMBA (SMB)
    iptables -A $chain -i $lan -p tcp --dport 445 -m set --match-set macports src -j ACCEPT
    # EMAIL (SMTP, IMAP, POP3)
    iptables -A $chain -i $lan -p tcp -m multiport --dports 465,587,143,993,110,995 -m set --match-set macports src -j ACCEPT
    # MESSAGING & XMPP (Jabber, FCM)
    iptables -A $chain -i $lan -p tcp -m multiport --dports 5222,5223,5228,5269 -m set --match-set macports src -j ACCEPT
    # mDNS / Bonjour / AirPrint
    iptables -A $chain -i $lan -d 224.0.0.251 -p udp --dport 5353 -m set --match-set macports src -j ACCEPT
    # LLMNR (Link-Local Multicast Name Resolution)
    iptables -A $chain -i $lan -d 224.0.0.252 -p udp --dport 5355 -m set --match-set macports src -j ACCEPT
    # SSDP / UPnP (Universal Plug and Play)
    iptables -A $chain -i $lan -d 239.255.255.250 -p udp --dport 1900 -m set --match-set macports src -j ACCEPT
    # WSD (Web Services Discovery) - UDP
    iptables -A $chain -i $lan -d 239.255.255.250 -p udp --dport 3702 -m set --match-set macports src -j ACCEPT
    # WSD (Web Services Discovery) - TCP
    iptables -A $chain -i $lan -p tcp -m multiport --dports 5357,5358 -m set --match-set macports src -j ACCEPT
    # NETBIOS NMBD (disabled in smb.conf)
    #iptables -A $chain -i $lan -p udp -m multiport --dports 137,138 -m set --match-set macports src -j ACCEPT
    #iptables -A $chain -i $lan -p tcp --dport 139 -m set --match-set macports src -j ACCEPT
done

# LAN 2 LAN TRAFFIC
# mDNS / Bonjour / AirPrint
iptables -A FORWARD -i $lan -o $lan -d 224.0.0.251 -p udp --dport 5353 -m set --match-set macports src -j ACCEPT
# LLMNR (Link-Local Multicast Name Resolution)
iptables -A FORWARD -i $lan -o $lan -d 224.0.0.252 -p udp --dport 5355 -m set --match-set macports src -j ACCEPT
iptables -A OUTPUT -o $lan -p udp --sport 5355 -j ACCEPT
# SSDP / UPnP (Universal Plug and Play)
iptables -A FORWARD -i $lan -o $lan -d 239.255.255.250 -p udp --dport 1900 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i $lan -o $lan -p udp -m multiport --dports 1900,5000 -m set --match-set macports src -j ACCEPT
# WSD (Web Services Discovery)
iptables -A FORWARD -i $lan -o $lan -d 239.255.255.250 -p udp --dport 3702 -m set --match-set macports src -j ACCEPT
# MULTIMEDIA & STREAMING
iptables -A FORWARD -i $lan -o $lan -p tcp -m multiport --dports 2869,8200,10243 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i $lan -o $lan -p igmp -m set --match-set macports src -j ACCEPT

## SECURITY RULES ##
echo "Sec Rules..."

# invalid and fragmented packets
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
iptables -A FORWARD -f -j DROP

# syncflood
iptables -N syn_flood
iptables -A INPUT -i $wan -p tcp --syn -j syn_flood
iptables -A INPUT -i $lan -p tcp --syn -j syn_flood
iptables -A syn_flood -i $wan -m limit --limit 50/s --limit-burst 200 -j RETURN
iptables -A syn_flood -i $lan -m limit --limit 200/s --limit-burst 500 -j RETURN
iptables -A syn_flood -m limit --limit 1/min -j NFLOG --nflog-prefix "SYNFLOOD: "
iptables -A syn_flood -j DROP

# Protection against port scanning (Optional)
#iptables -N PORTSCAN
#iptables -A INPUT -m recent --name portscan_blocked --rcheck --seconds 3600 -j DROP
#iptables -A INPUT -p tcp --syn -m recent --name portscan --rcheck --seconds 30 --hitcount 8 -j PORTSCAN
#iptables -A INPUT -p tcp --syn -m recent --name portscan --set
#iptables -A PORTSCAN -j NFLOG --nflog-prefix "PORTSCAN_DETECTED: "
#iptables -A PORTSCAN -m recent --name portscan_blocked --set
#iptables -A PORTSCAN -j DROP

# TCP flags (Optional)
#iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
#iptables -A INPUT -p tcp --tcp-flags ALL FIN,URG,PSH -j DROP
#iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
#iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
#iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
#iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j DROP

# Block Hex Strings: BitTorrent, Tor, etc. (Experimental)
#bt=$(curl -s https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/ipt/torrent.txt)
#tor=$(curl -s https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/ipt/tor.txt)
#for string in $(echo -e "$bt\n$tor" | sed -e '/^#/d' -e 's:#.*::g'); do
#   iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo bm -j NFLOG --nflog-prefix "BLOCK STRINGS: "
#   iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo bm -j DROP
#done

# Block Spoofed Packets (Optional)
#for ip in $(sed '/^\s*#/d;/^\s*$/d' "$aclroute/bogons.txt"); do
#   iptables -A INPUT -i $lan -s $ip -j NFLOG --nflog-prefix "SPOOF: "
#   iptables -A INPUT -i $lan -s $ip -j DROP
#done

# WIN ICS (192.168.137.0/24) (Optional)
#iptables -t mangle -A PREROUTING -i $lan -m ttl --ttl-lt 64 -j MARK --set-mark 999
#iptables -A FORWARD -m mark --mark 999 -j NFLOG --nflog-prefix "TTL-ICS-BLOCKED: "
#iptables -A FORWARD -m mark --mark 999 -j DROP

# ICMP (ping) (Optional)
# WARNING: You need to change the following kernel parameter in the header of this script: 
# sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
# ICMP essential
#iptables -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT
#iptables -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT
#iptables -A INPUT -p icmp --icmp-type parameter-problem -j ACCEPT
# WAN → SERVER
#iptables -A INPUT -i $wan -p icmp --icmp-type echo-request -j DROP
# LAN → SERVER 
#iptables -A INPUT -i $lan -p icmp --icmp-type echo-request -j ACCEPT
# LAN → INTERNET
#iptables -A FORWARD -i $lan -o $wan -p icmp --icmp-type echo-request -j ACCEPT
#iptables -A FORWARD -i $wan -o $lan -p icmp --icmp-type echo-reply -j ACCEPT

echo OK

## MAC RULES ##
echo "MAC Rules"

# MACTRANSPARENT (WARNING: Not recommended) (check blockports.txt)
#if ! ipset list mactransparent &>/dev/null; then
#    ipset create mactransparent hash:mac -exist
#else
#    ipset flush mactransparent
#fi
#for mac in $(awk -F";" '$2 != "" {print $2}' $aclroute/mac-transparent.txt); do
#   ipset add mactransparent $mac -exist
#done
#for chain in INPUT FORWARD; do
#    iptables -A $chain -i $lan -p tcp -m multiport --dports 80,443,853 -m set --match-set mactransparent src -j ACCEPT
#done

# MACPROXY (PAC 18100 - Opcion 252 DHCP, HTTP 80 to 3128)
if ! ipset list macproxy &>/dev/null; then
    ipset create macproxy hash:mac -exist
else
    ipset flush macproxy
fi
for mac in $(awk -F";" '$2 != "" {print $2}' $aclroute/mac-proxy.txt); do
    ipset add macproxy $mac -exist
done
iptables -t nat -A PREROUTING -i $lan -p tcp --dport 80 -m set --match-set macproxy src -j REDIRECT --to-port 3128
for chain in INPUT FORWARD; do
    iptables -A $chain -i $lan -p tcp -m multiport --dports 18100,3128 -m set --match-set macproxy src -j ACCEPT
done

echo OK

## END ## 
echo "DROP All..."
iptables -A INPUT -j NFLOG --nflog-prefix "FINAL-DROP-INPUT: "
iptables -A INPUT -j DROP
iptables -A FORWARD -j NFLOG --nflog-prefix "FINAL-DROP-FORWARD: "
iptables -A FORWARD -j DROP

echo "iptables Load at: $(date)" | tee -a /var/log/syslog
echo "Done"
