#!/bin/bash
# maravento.com
#
################################################################################
#
## Iptables/Ipset Firewall O(1)
## Verify: iptables -L -n / iptables -nvL / iptables -Ln -t mangle / iptables -Ln -t nat
## Sockets: ss -ltuna
# Ports: /etc/services
# ============================
# Ports 0-1023: "Well-known ports" (System/Privileged)
# - Require superuser privileges to bind
# - Standard services: HTTP(80), HTTPS(443), SSH(22), DNS(53)
# - FTP(21), Telnet(23), SMTP(25), etc.
# Ports 1024-49151: "Registered ports" (IANA Assigned)
# - Assigned by Internet Assigned Numbers Authority
# - User/application services without root privileges
# - Examples: MySQL(3306), PostgreSQL(5432), Skype(1000-10000)
# Ports 49152-65535: "Dynamic/Private ports" (Ephemeral)
# - Available for any use, not registered by IANA
# - Used for temporary/outbound connections
# - Client-side dynamic port assignments
# REFERENCES:
# - https://gutl.jovenclub.cu/wiki/doku.php?id=definiciones:puertos_tcp_udp
# - https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
# - RFC 6335 - Internet Assigned Numbers Authority (IANA) Procedures
# - https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt
#
################################################################################

set -euo pipefail

# logging
log_file="/var/log/iptables.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

log "Iptables Start..."

## VARIABLES ##

# MAC/IP validation before feeding external ACL data into ipset
is_valid_mac() {
    [[ "$1" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$ ]]
}

is_valid_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# paths
acl_path="/etc/acl"
acl_mac_path="$acl_path/acl_mac"
acl_ipt_path="$acl_path/acl_ipt"
# interfaces
wan=eth0
lan=eth1
# LAN localnet/netmask
localnet=192.168.0.0
netmask=24
# server IP
# Command to get active interfaces (except lo) (Name/IPv4/MAC) (Replace with your server IPv4/MAC):
# join <(ip -o -br link | sort) <(ip -o -br addr | sort) | awk '$2=="UP" {print $1,$6,$3}' | sed -Ee 's./[0-9]+..'
serverip=192.168.0.10

# ACL/config files used by this script (existence verified below)
mac_proxy_file="$acl_mac_path/mac-proxy.txt"
mac_unlimited_file="$acl_mac_path/mac-unlimited.txt"
blockports_file="$acl_ipt_path/blockports.txt"
dhcp_conf="/etc/pydhcp/pydhcpd.conf"
path_ips="$acl_ipt_path/dhcp_ip.txt"
path_macs="$acl_ipt_path/dhcp_mac.txt"

for f in "$mac_proxy_file" "$mac_unlimited_file" "$blockports_file" "$dhcp_conf"; do
    if [ ! -f "$f" ]; then
        log "ERROR: required file not found: $f"
        exit 1
    fi
done
if [ ! -d "$acl_mac_path" ] || [ -z "$(ls -A "$acl_mac_path" 2>/dev/null)" ]; then
    log "ERROR: acl_mac_path missing or empty: $acl_mac_path"
    exit 1
fi

logrotate_conf="/etc/logrotate.d/iptables"
if [ ! -f "$logrotate_conf" ]; then
    cat > "$logrotate_conf" <<'EOF'
/var/log/iptables.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF
    chmod 644 "$logrotate_conf"
    chown root:root "$logrotate_conf"
fi

## KERNEL RULES ##
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
##### SYSTEM OPTIMIZATION #####
sysctl -w fs.file-max=2097152 >/dev/null 2>&1
sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1
sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1
sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1

##### CONNECTION TRACKING #####
# Increase connection tracking table size for high concurrency
sysctl -w net.netfilter.nf_conntrack_max=524288 >/dev/null 2>&1
sysctl -w net.netfilter.nf_conntrack_buckets=131072 >/dev/null 2>&1

##### SECURITY & NETWORK HARDENING #####
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
# Enable strict reverse path filtering (drops packets with spoofed source IPs)
sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null 2>&1
sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null 2>&1

##### NETWORK PERFORMANCE & TCP PROTECTION #####
# Optimized TCP/IP parameters for high-performance and secure routing
# Enable TCP SYN cookies (protects against SYN flood attacks)
sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
# Increase SYN backlog queue and tune retries (helps prevent SYN flood)
sysctl -w net.ipv4.tcp_max_syn_backlog=20000 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_syn_retries=2 >/dev/null 2>&1
sysctl -w net.ipv4.tcp_synack_retries=2 >/dev/null 2>&1
# Enable RFC1337 fix (protects against TCP TIME-WAIT assassination)
sysctl -w net.ipv4.tcp_rfc1337=1 >/dev/null 2>&1
# Expand available local port range (default: 32768-60999)
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

##### ROUTING & FORWARDING #####
# Enable packet forwarding (required for NAT/routing)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

##### ARP OPTIMIZATION #####
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

##### KERNEL & FILESYSTEM HARDENING #####
# Enable full ASLR (Address Space Layout Randomization)
sysctl -w kernel.randomize_va_space=2 >/dev/null 2>&1
# Protect hardlinks (prevents privilege escalation attacks)
sysctl -w fs.protected_hardlinks=1 >/dev/null 2>&1
# Protect symlinks (prevents unauthorized link access in shared directories)
sysctl -w fs.protected_symlinks=1 >/dev/null 2>&1

##### ICMP #####
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
sysctl -w "net.ipv6.conf.${lan}.disable_ipv6=1" >/dev/null 2>&1
# ICMPv6 esencial (NDP, SLAAC, Path MTU)
ip6tables -A OUTPUT -o "$wan" -p ipv6-icmp -j ACCEPT
# DHCPv6
ip6tables -A OUTPUT -o "$wan" -p udp --sport 546 --dport 547 -j ACCEPT
# Established traffic
ip6tables -A INPUT -i "$wan" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

## GLOBAL RULES ##

# Global Policies IPv4 (ACCEPT y luego drops explicitos)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Global Policies IPv6 (cerrado por defecto)
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP

# LOOPBACK
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP

# BOGONS
bogonslst=/etc/acl/acl_ipt/bogons.txt
if ! ipset list bogons &>/dev/null; then
    ipset create bogons hash:net -exist
else
    ipset flush bogons
fi
for bogonscidr in $(grep -vE '^\s*#|^\s*$' "$bogonslst" | awk '{print $1}' | sort -V -u 2>/dev/null); do
    ipset add bogons "$bogonscidr" -exist
done
iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set bogons src -j DROP
iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set bogons dst -j DROP

# MASQUERADE: NAT for LAN to share dynamic WAN IP
iptables -t nat -A POSTROUTING -s "$localnet/$netmask" -o "$wan" -j MASQUERADE
#
# SNAT example for static WAN IP (more efficient)
# wan_ip=$(ip -4 -o addr show dev "$wan" | awk '{print $4}' | cut -d/ -f1)
# iptables -t nat -A POSTROUTING -s "$localnet/$netmask" -o "$wan" -j SNAT --to-source "$wan_ip"

# LAN ---> PROXY <--- WAN
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
# Squid proxy outbound traffic
iptables -A OUTPUT -o "$wan" -m owner --uid-owner proxy -j ACCEPT

# DHCP
iptables -t mangle -A PREROUTING -i "$lan" -p udp --dport 67 -j ACCEPT
iptables -A OUTPUT -o "$wan" -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A INPUT -i "$wan" -p udp --sport 67 --dport 68 -j ACCEPT
iptables -A INPUT -i "$lan" -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A OUTPUT -o "$lan" -p udp --sport 67 --dport 68 -j ACCEPT

# NTP
iptables -A INPUT -i "$lan" -p udp --dport 123 -s "$localnet/$netmask" -j ACCEPT
iptables -A FORWARD -i "$lan" -p udp --dport 123 -s "$localnet/$netmask" -j ACCEPT

# WARNING PAGE HTTP FOR BANDATA (TCP 18081)
# https://github.com/maravento/proxymon
iptables -A INPUT -i "$lan" -p tcp --dport 18081 -j ACCEPT

# Invalid and fragmented packets
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP
iptables -A FORWARD -f -j DROP
# TCP scans / malformed packets
iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
iptables -A FORWARD -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP
iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
# Invalid NEW connections with SYN+ACK
iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m conntrack --ctstate NEW -j DROP
iptables -A FORWARD -p tcp --tcp-flags SYN,ACK SYN,ACK -m conntrack --ctstate NEW -j DROP

# MACUNLIMITED (MAC + IP for Access Points, Switch, etc.)
if ! ipset list macunlimited &>/dev/null; then
    ipset create macunlimited hash:mac -exist
else
    ipset flush macunlimited
fi
for mac in $(awk -F";" '$2 != "" {print $2}' "$mac_unlimited_file" 2>/dev/null); do
    is_valid_mac "$mac" && ipset add macunlimited "$mac" -exist
done
iptables -t nat -A PREROUTING -i "$lan" -m set --match-set macunlimited src -j ACCEPT
iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set macunlimited src -j ACCEPT
# Unlimited devices never use the proxy -- block PAC access so DHCP option 252
# (WPAD, if enabled) has no effect on them, since pydhcpd is ACL-agnostic and
# sends it to every client regardless of classification.
iptables -A INPUT -i "$lan" -p tcp -m multiport --dports 3128,18100 -m set --match-set macunlimited src -j DROP
for chain in INPUT FORWARD; do
    iptables -A "$chain" -i "$lan" -m set --match-set macunlimited src -j ACCEPT
done

# mac2ip
mac2ip=$(awk '
    /host [^{]+ \{/ { in_block=1; mac=""; ip="" }
    in_block && /hardware ethernet/ { mac=$3; gsub(/;/, "", mac) }
    in_block && /fixed-address/ { ip=$2; gsub(/;/, "", ip) }
    in_block && /\}/ {
        if (mac != "" && ip != "") print mac, ip
        in_block=0
    }
' "$dhcp_conf")
# rule mac2ip
if ! ipset list macip &>/dev/null; then
    ipset create macip hash:ip,mac -exist
else
    ipset flush macip
fi
create_acl() {
    local ips macs mac ip
    ips="# ips"
    macs="# macs"
    while (( $# >= 2 )); do
        mac="$1"
        shift
        ip="$1"
        shift
        # Add MAC+IP to set
        is_valid_mac "$mac" && is_valid_ip "$ip" && ipset add macip "$ip,$mac" -exist
        ips="$ips\n$ip"
        macs="$macs\n$mac"
    done
    echo -e "$ips" > "$path_ips"
    echo -e "$macs" > "$path_macs"
}
if [ -n "$mac2ip" ]; then
    create_acl $mac2ip
    iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set macip src,src -j ACCEPT
    iptables -t mangle -A PREROUTING -i "$lan" -j DROP
else
    log "WARNING: No static DHCP entries found in $dhcp_conf; macip binding skipped"
fi

## PORT RULES ##

# BLOCKPORTS
# path: /etc/acl/acl_ipt/blockports.txt
# Block Direct Connections:
# - HTTPs (443) - TCP/UDP
# - HTTPs Fallback (4444,9443) - TCP
# - DoT (853,8053) - TCP
# - DNS over QUIC DoQ (784) - UDP
# - DoQ Fallback (8853) - UDP
# - OpenVPN (1194) - UDP
# - L2TP/IPsec (1701) - UDP
# - IPsec IKE (500) - UDP
# - IPsec NAT-T (4500) - UDP
# - WireGuard (51820) - UDP
# - SOCKS5 proxies (1080) - TCP
# - Shadowsocks (7300) - TCP/UDP
# - HTTP-Proxy Alternative (8080,8000,3129,3130) - TCP
# - Spotify (4070) - TCP
#
# Block legacy, risky or potentially abusive services:
# - Echo (7) - TCP/UDP
# - CHARGEN (19) - TCP/UDP
# - FTP (20,21) - TCP
# - SSH (22) - TCP
# - 6to4 (41,43,44,58,59,60,3544) - UDP
# - FINGER (79) - TCP
# - PPTP (1723) - TCP
# - TOR Ports (9001,9050,9150) - TCP
# - Brave Tor (9001:9004,9090,9101:9103,9030,9031,9050) - TCP
# - IRC (6660-6669) - TCP
# - Trojans/Metasploit (4444) - TCP
# - SQL inyection/XSS (8088,8888) - TCP
# - bittorrent (6881-6889,58251,58252,58687,6969) - TCP/UDP
# - others P2P (1000,1007,1337,2760,4662,4672,5001) - TCP/UDP
# - Cryptomining (3333,5555,6666,7777,8848,9999,14444,14433,45560) - TCP
# - WINS (42) - TCP/UDP
# - BTC/ETH (8332,8333,8545,30303) - TCP
# - IPP (631) - TCP
if ! ipset list blockports &>/dev/null; then
    ipset create blockports bitmap:port range 0-65535 -exist
else
    ipset flush blockports
fi
for blports in $(sort -V -u "$blockports_file" 2>/dev/null); do
    ipset add blockports "$blports" -exist
done
for proto in tcp udp; do
    iptables -t mangle -A PREROUTING -i "$lan" -p "$proto" -m set --match-set blockports dst -j DROP
done

# MAC Ports
if ! ipset list macports &>/dev/null; then
    ipset create macports hash:mac -exist
else
    ipset flush macports
fi
for mac in $(awk -F";" '$2 != "" {print $2}' "$acl_mac_path"/mac-* 2>/dev/null); do
    is_valid_mac "$mac" && ipset add macports "$mac" -exist
done

# DNS
dns="8.8.8.8 1.1.1.1"
for dnsip in $dns; do
    iptables -A FORWARD -i "$lan" -o "$wan" -m set --match-set macports src -d "$dnsip" -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i "$lan" -o "$wan" -m set --match-set macports src -d "$dnsip" -p tcp --dport 53 -j ACCEPT
    iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set macports src -d "$dnsip" -p udp --dport 53 -j ACCEPT
    iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set macports src -d "$dnsip" -p tcp --dport 53 -j ACCEPT
done
iptables -A FORWARD -i "$lan" -o "$wan" -p udp --dport 53 -j DROP
iptables -A FORWARD -i "$lan" -o "$wan" -p tcp --dport 53 -j DROP

# PRINTERS
for chain in INPUT FORWARD; do
    # PRINTERS & SCANNERS UDP: SNMP (161,162) + prnrequest/prnstatus (3910/3911)
    iptables -A "$chain" -i "$lan" -p udp -m multiport --dports 161,162,3910,3911 -m set --match-set macports src -j ACCEPT
    # PRINTERS & SCANNERS TCP: JetDirect/RAW (9100) + prnrequest/prnstatus (3910/3911)
    iptables -A "$chain" -i "$lan" -p tcp -m multiport --dports 9100,3910,3911 -m set --match-set macports src -j ACCEPT
done
# STUN/TURN (WebRTC, Teams, Meet, Zoom)
iptables -A FORWARD -i "$lan" -o "$wan" -p udp -m multiport --dports 3478:3481 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$lan" -o "$wan" -p tcp -m multiport --dports 3478,5349 -m set --match-set macports src -j ACCEPT
# Google STUN
iptables -A FORWARD -i "$lan" -o "$wan" -p udp -m multiport --dports 19302:19309 -m set --match-set macports src -j ACCEPT
# FILE SHARING SAMBA (SMB)
iptables -A INPUT -i "$lan" -p tcp -m multiport --dports 445,3092 -m set --match-set macports src -j ACCEPT
# EMAIL (SMTP, IMAP, POP3)
iptables -A FORWARD -i "$lan" -p tcp -m multiport --dports 110,143,465,587,993,995 -m set --match-set macports src -j ACCEPT
# MESSAGING & XMPP (Jabber, FCM)
iptables -A FORWARD -i "$lan" -p tcp -m multiport --dports 5222,5223,5228,5269 -m set --match-set macports src -j ACCEPT
# WSD (Web Services Discovery) - TCP
iptables -A FORWARD -i "$lan" -p tcp -m multiport --dports 5357,5358 -m set --match-set macports src -j ACCEPT
# mDNS LAN noise
iptables -A INPUT -i "$lan" -d 224.0.0.251 -p udp --dport 5353 -j DROP
# Drop local multicast (collaboration tools, discovery, etc.)
iptables -A INPUT -i "$lan" -d 239.255.0.0/16 -j DROP
# LAN traffic: discovery, printing, collaboration
# mDNS / Bonjour / AirPrint
iptables -A FORWARD -i "$lan" -o "$lan" -d 224.0.0.251 -p udp --dport 5353 -m set --match-set macports src -j ACCEPT
# LLMNR
iptables -A FORWARD -i "$lan" -o "$lan" -d 224.0.0.252 -p udp --dport 5355 -m set --match-set macports src -j ACCEPT
# SSDP / UPnP
iptables -A FORWARD -i "$lan" -o "$lan" -d 239.255.255.250 -p udp --dport 1900 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$lan" -o "$lan" -p udp --dport 5000 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$lan" -p udp -m multiport --dports 1900,5000 -m set --match-set macports src -j DROP
# WSD
iptables -A FORWARD -i "$lan" -o "$lan" -d 239.255.255.250 -p udp --dport 3702 -m set --match-set macports src -j ACCEPT
# Multimedia & Streaming
iptables -A FORWARD -i "$lan" -o "$lan" -p tcp -m multiport --dports 2869,8200 -m set --match-set macports src -j ACCEPT
# IGMP (required for multicast group management)
iptables -A FORWARD -i "$lan" -o "$lan" -p igmp -m set --match-set macports src -j ACCEPT

## SECURITY RULES ##
# Block 6to4 (IPv6-in-IPv4 tunneling) - prevents LAN clients from bypassing
# IPv4-based firewall rules via IPv6 tunnel encapsulation
iptables -A FORWARD -i "$lan" -p 41 -j DROP

# NETBIOS NMBD (disabled in smb.conf)
for chain in INPUT FORWARD; do
    iptables -A "$chain" -i "$lan" -p udp -m multiport --dports 137,138 -j DROP
    iptables -A "$chain" -i "$lan" -p tcp --dport 139 -j DROP
done
# CoAP/CoAPs 5683/5684
for chain in INPUT FORWARD; do
    iptables -A "$chain" -i "$lan" -p udp -m multiport --dports 5683,5684 -j DROP
done

# syncflood
iptables -N syn_flood
iptables -A INPUT -i "$wan" -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn_flood
iptables -A INPUT -i "$lan" -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn_flood
iptables -A syn_flood -i "$wan" -m limit --limit 50/s --limit-burst 200 -j RETURN
iptables -A syn_flood -i "$lan" -m limit --limit 200/s --limit-burst 500 -j RETURN
iptables -A syn_flood -m limit --limit 1/min -j NFLOG --nflog-prefix "SYNFLOOD: "
iptables -A syn_flood -j DROP

# Windows Update Delivery Optimization (WUDO)
# Allow peer-to-peer update sharing within the local network.
# Block outbound WUDO traffic to WAN and direct connections to the firewall.
for proto in tcp udp; do
    iptables -A FORWARD -i "$lan" -p "$proto" --dport 7680 -s "$localnet/$netmask" -d "$localnet/$netmask" -j ACCEPT
done
for chain in INPUT FORWARD; do
    for proto in tcp udp; do
        iptables -A "$chain" -i "$lan" -p "$proto" --dport 7680 -j DROP
    done
done

# Block GRE (Generic Routing Encapsulation) protocol 47
for chain in INPUT FORWARD; do
    iptables -A "$chain" -i "$lan" -p 47 -j DROP
done
# Block Windows ICS (Internet Connection Sharing) network range
iptables -A FORWARD -i "$lan" -d 192.168.137.0/24 -j DROP
# Block WS-Discovery unicast to server (Windows clients noise)
iptables -A INPUT -i "$lan" -p udp --sport 3702 -d "$serverip" -j DROP
# KMS Windows activation noise
iptables -A INPUT -i "$lan" -p tcp --dport 1688 -j ACCEPT
iptables -A FORWARD -i "$lan" -o "$wan" -p tcp --dport 1688 -j ACCEPT
# Spotify LAN sync broadcast noise
iptables -A INPUT -i "$lan" -p udp --dport 57621 -j DROP
# Cisco IP phones discovery noise
iptables -A INPUT -i "$lan" -p udp -m multiport --dports 2007,2008 -j DROP
# SAP broadcast noise (Optional)
iptables -A INPUT -i "$lan" -p udp --dport 3289 -j DROP
# Dropbox LAN sync broadcast noise
iptables -A INPUT -i "$lan" -p udp --dport 17500 -j DROP

protocols=(
 "torrent:|426974546f7272656e742070726f746f636f6c|"
 "tor:|1cc02bc02fc02cc030c00ac009c013c01400330039002f0035000a00ff01|"
)
for p in "${protocols[@]}"; do
    iptables -A FORWARD -i "$lan" -m string --hex-string "${p#*:}" --algo bm -j NFLOG --nflog-prefix "${p%%:*}: "
    iptables -A FORWARD -i "$lan" -m string --hex-string "${p#*:}" --algo bm -j DROP
done

# ICMP (ping) (Optional)
# WARNING:
# You need to change the following kernel parameter in the header of this script:
# sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
# NOTE: For nmap scans, increase limit to 100/second or use -Pn in nmap options
#iptables -A INPUT -p icmp -m limit --limit 10/second -j ACCEPT
#iptables -A FORWARD -p icmp -m limit --limit 10/second -j ACCEPT
#iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
# Silence ICMP forward noise
iptables -A FORWARD -i "$lan" -o "$wan" -p icmp -j DROP

## MAC RULES ##
# MACPROXY (PAC 18100 - Opcion 252 DHCP, HTTP 80 to 3128)
if ! ipset list macproxy &>/dev/null; then
    ipset create macproxy hash:mac -exist
else
    ipset flush macproxy
fi
for mac in $(awk -F";" '$2 != "" {print $2}' "$mac_proxy_file" 2>/dev/null); do
    is_valid_mac "$mac" && ipset add macproxy "$mac" -exist
done
iptables -t mangle -A PREROUTING -i "$lan" -m set --match-set macproxy src -p tcp -m multiport --dports 18100,80 -j ACCEPT
iptables -t nat -A PREROUTING -i "$lan" -p tcp --dport 80 -m set --match-set macproxy src -j REDIRECT --to-port 3128
for chain in INPUT FORWARD; do
    iptables -A "$chain" -i "$lan" -p tcp -m multiport --dports 18100,3128 -m set --match-set macproxy src -j ACCEPT
done

## END ##
iptables -A INPUT -m hashlimit --hashlimit-name input-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip,dstport -j NFLOG --nflog-prefix "FINAL-INPUT DROP: "
iptables -A INPUT -j DROP
iptables -A FORWARD -m hashlimit --hashlimit-name forward-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip,dstport -j NFLOG --nflog-prefix "FINAL-FORWARD DROP: "
iptables -A FORWARD -j DROP

log "iptables done at: $(date)"
