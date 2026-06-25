#!/bin/bash
# maravento.com

################################################################################
# THIS IS AN EXAMPLE SCRIPT — DO NOT USE IN PRODUCTION
# Adapt interface names, IPs, and ACL paths to your environment.
# See the full reference implementation and README at:
# https://github.com/maravento/vault/tree/master/uhotspot
################################################################################

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

# logging
log_file="/var/log/uhotspot.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg"
}

log "Iptables Start..."
printf "\n"

# VARIABLES ##
 
# Load all configuration from uhotspot.conf (network, paths, interfaces).
# Safe key=value parsing — file is never sourced to prevent code execution.
_UHOTSPOT_CONF="/etc/uhotspot/uhotspot.conf"
 
_load_conf() {
    local file="$1" key value
    [[ ! -f "$file" ]] && { log "WARNING: $file not found — using built-in defaults"; return 1; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$line" =~ ^[[:space:]]*$    ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        case "$key" in
            WAN_IF|LAN_IF|\
            SERV_DHCP|SERV_SUBNET|SERV_MASK|SERV_DNS|\
            ACL_MAC_PATH|ACL_DHCP_PATH|HOTSPOT_PATH|\
            ACL_MAC_PROXY|ACL_MAC_UNLIMITED)
                printf -v "$key" '%s' "$value"
                ;;
        esac
    done < "$file"
}
 
_load_conf "$_UHOTSPOT_CONF"
 
wan="${WAN_IF:-eno1}"
lan="${LAN_IF:-eno20}"
localnet="${SERV_SUBNET:-192.168.0.0}"
serverip="${SERV_DHCP:-192.168.0.10}"
netmask=$(python3 -c \
    "import ipaddress; print(ipaddress.IPv4Network('0.0.0.0/${SERV_MASK:-255.255.255.0}').prefixlen)" \
    2>/dev/null || echo "24")
 
acl_mac_path="${ACL_MAC_PATH:-/etc/acl/acl_mac}"
acl_path="${acl_mac_path%/acl_mac}"
acl_ipt_path="${acl_path}/acl_ipt"
hotspot_path="${HOTSPOT_PATH:-/etc/uhotspot}"
 
log "Config: wan=$wan lan=$lan localnet=$localnet/$netmask serverip=$serverip"
 
# ACL/config files used by this script (existence verified below)
mac_proxy_file="${ACL_MAC_PROXY:-$acl_mac_path/mac-proxy.txt}"
mac_unlimited_file="${ACL_MAC_UNLIMITED:-$acl_mac_path/mac-unlimited.txt}"
blockports_file="$acl_ipt_path/blockports.txt"
dhcp_conf="/etc/pydhcp/pydhcpd.conf"
path_ips="$acl_ipt_path/dhcp_ip.txt"
path_macs="$acl_ipt_path/dhcp_mac.txt"
 
for f in "$mac_proxy_file" "$mac_unlimited_file" "$blockports_file" "$dhcp_conf"; do
    [ -f "$f" ] || log "WARNING: required file not found: $f"
done
if [ ! -d "$acl_mac_path" ] || [ -z "$(ls -A "$acl_mac_path" 2>/dev/null)" ]; then
    log "WARNING: acl_mac_path missing or empty: $acl_mac_path"
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
    log "Created logrotate config: $logrotate_conf"
fi

## KERNEL RULES ##
log "Kernel Rules..."
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
# Enable strict reverse path filtering (drops packets with spoofed source IPs)
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
sysctl -w net.ipv6.conf.${lan}.disable_ipv6=1 >/dev/null 2>&1
# ICMPv6 esencial (NDP, SLAAC, Path MTU)
ip6tables -A OUTPUT -o $wan -p ipv6-icmp -j ACCEPT
# DHCPv6
ip6tables -A OUTPUT -o $wan -p udp --sport 546 --dport 547 -j ACCEPT
# Established traffic
ip6tables -A INPUT -i $wan -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

log "OK"

## GLOBAL RULES ##
log "Global Rules..."

# Global Policies IPv4 (ACCEPT y luego drops explícitos)
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

# MACUNLIMITED (MAC + IP for Access Points, Switch, etc.)
if ! ipset list macunlimited &>/dev/null; then
    ipset create macunlimited hash:mac -exist
else
    ipset flush macunlimited
fi
for mac in $(awk -F";" '$2 != "" {print $2}' "$mac_unlimited_file" 2>/dev/null); do
    ipset add macunlimited $mac -exist
done
iptables -t nat -A PREROUTING -i $lan -m set --match-set macunlimited src -j ACCEPT
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macunlimited src -j ACCEPT
for chain in INPUT FORWARD; do
    iptables -A $chain -i $lan -m set --match-set macunlimited src -j ACCEPT
done

# WAN DROP: CIDR
iptables -A INPUT -i $wan -s 10.0.0.0/8 -j DROP
iptables -A INPUT -i $wan -s 172.16.0.0/12 -j DROP
#iptables -A INPUT -i $wan -s 192.168.0.0/16 -j DROP
# WAN DROP: Local Ports (reduce noise)
# 25     TCP - Postfix SMTP (master)
# 80     TCP - HTTP
# 3128   TCP - Squid proxy
# 4330   TCP - PCP pmlogger (Performance Co-Pilot)
# 5005   TCP - UniFi/Podman (pasta userspace network)
# 5636   TCP - UniFi/Podman (pasta userspace network)
# 5671   TCP - UniFi/Podman AMQP (pasta userspace network)
# 6789   TCP - UniFi speed test (pasta userspace network)
# 8443   TCP - UniFi HTTPS GUI (pasta userspace network)
# 8444   TCP - UniFi OS HTTPS GUI (pasta userspace network)
# 9543   TCP - UniFi/Podman (pasta userspace network)
# 10000  TCP - Webmin
# 11084  TCP - UniFi/Podman (pasta userspace network)
# 11443  TCP - UniFi OS self-hosted GUI (pasta userspace network)
# 18100  TCP - PAC proxy
# 18080  TCP - Internal HTTP
# 18081  TCP - Warning page (bandata)
# 18082  TCP - Internal HTTP alternate
# 44321  TCP - PCP pmcd (Performance Co-Pilot daemon)
# 44322  TCP - PCP pmproxy
# 44323  TCP - PCP pmproxy HTTPS
iptables -A INPUT -i $wan -p tcp -m multiport --dports 25,80,3128,4330,5005,5636,5671,6789,8443,8444,9543,10000,11084,11443,18100 -j DROP
iptables -A INPUT -i $wan -p tcp -m multiport --dports 18080,18081,18082,44321,44322,44323 -j DROP
iptables -A INPUT -i $wan -p udp --dport 5353 -j DROP

# MACUNLIMITED (infrastructure bypass: APs, switches, printers, etc.)
# Add MACs that should bypass the captive portal entirely.
if ! ipset list macunlimited &>/dev/null; then
    ipset create macunlimited hash:mac -exist
else
    ipset flush macunlimited
fi
for mac in $(awk -F";" '$2 != "" {print $2}' "$mac_unlimited_file" 2>/dev/null); do
    ipset add macunlimited $mac -exist
done
iptables -t nat    -A PREROUTING -i $lan -m set --match-set macunlimited src -j ACCEPT
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macunlimited src -j ACCEPT
for chain in INPUT FORWARD; do
    iptables -A $chain -i $lan -m set --match-set macunlimited src -j ACCEPT
done

# MASQUERADE: NAT for LAN to share dynamic WAN IP
iptables -t nat -A POSTROUTING -s $localnet/$netmask -o $wan -j MASQUERADE
#
# SNAT example for static WAN IP (more efficient)
# wan_ip=$(ip -4 -o addr show dev "$wan" | awk '{print $4}' | cut -d/ -f1)
# iptables -t nat -A POSTROUTING -s $localnet/$netmask -o $wan -j SNAT --to-source $wan_ip

# LAN ---> PROXY <--- WAN
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
# Squid proxy outbound traffic
iptables -A OUTPUT -o $wan -m owner --uid-owner proxy -j ACCEPT

# DHCP
iptables -t mangle -A PREROUTING -i $lan -p udp --dport 67 -j ACCEPT
iptables -A OUTPUT -o $wan -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A INPUT -i $wan -p udp --sport 67 --dport 68 -j ACCEPT
iptables -A INPUT -i $lan -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A OUTPUT -o $lan -p udp --sport 67 --dport 68 -j ACCEPT

## UNIFI PORTS
# https://help.ui.com/hc/en-us/articles/218506997-Required-Ports-Reference
## UNIFI WAN
# STUN responses from Ubiquiti (3478) and Google (19302) — needed for APs behind NAT
iptables -A INPUT -i $wan -p udp -m multiport --sports 3478,19302 -j ACCEPT
# Device discovery from management LAN via WAN interface
iptables -A INPUT -i $wan -p udp --dport 10001 -j ACCEPT
## UNIFI LAN
# Uncomment if using Ubiquiti remote access cloud service
# iptables -A INPUT -i $wan -p tcp -s 66.203.125.0/24 --sport 443 -d $wan -j ACCEPT
# LAN Unifi — ports required for LAN clients and APs to communicate with self-hosted controller
# 8080  TCP - AP to controller communication
# 8880  TCP - captive portal HTTP
# 8881  TCP - captive portal HTTP alternate
# 8882  TCP - captive portal HTTP alternate
# 8843  TCP - captive portal HTTPS
# 6789  TCP - UniFi speed test / throughput measurement (Podman/pasta userspace network)
# 3478  UDP - STUN for APs
# 53    UDP - DNS (local on gateway)
# 123   UDP - NTP
# 10001 UDP - device discovery
# Removed (administrative/internal only):
# 8443  TCP - GUI/API admin access
# 8444  TCP - UniFi OS HTTPS GUI admin
# 11443 TCP - UniFi OS self-hosted GUI admin
# 27117 TCP - MongoDB internal database
# 1900  UDP - UPnP optional discovery
unifi_tcp="8080,6789"
unifi_udp_local="10001"
unifi_udp_wan="3478,123"
iptables -t mangle -A PREROUTING -i $lan -p tcp -m multiport --dports $unifi_tcp -j ACCEPT
iptables -t mangle -A PREROUTING -i $lan -p udp -m multiport --dports $unifi_udp_local,$unifi_udp_wan -j ACCEPT
iptables -A INPUT -i $lan -p tcp -m multiport --dports $unifi_tcp -j ACCEPT
iptables -A INPUT -i $lan -p udp --dport $unifi_udp_local -j ACCEPT
iptables -A FORWARD -i $lan -o $wan -p udp -m multiport --dports $unifi_udp_wan -j ACCEPT

# Unifi Portal Acess
# Optional https: 8843
cpd_tcp="8880,8881,8882"

# MAC pending rules
# Create ipsets
if ! ipset list macpending &>/dev/null; then
    ipset create macpending hash:mac -exist
else
    ipset flush macpending
fi

# Populate ipsets
if [ -f "$hotspot_path/guest-pending.txt" ]; then
    for mac in $(awk -F";" '$2 != "" {print $2}' $hotspot_path/guest-pending.txt); do
        ipset add macpending $mac -exist
    done
fi
# DNS
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macpending src -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i $lan -m set --match-set macpending src -p udp --dport 53 -j ACCEPT
# HTTP
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macpending src -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -i $lan -m set --match-set macpending src -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -i $lan -m set --match-set macpending src -p tcp --dport 80 -j ACCEPT
iptables -t nat -A PREROUTING -i $lan -m set --match-set macpending src -p tcp --dport 80 -j REDIRECT --to-port 8880
# CDP
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macpending src -p tcp -m multiport --dports $cpd_tcp -j ACCEPT
iptables -A INPUT -i $lan -m set --match-set macpending src -p tcp -m multiport --dports $cpd_tcp -j ACCEPT
iptables -A FORWARD -i $lan -m set --match-set macpending src -p tcp -m multiport --dports $cpd_tcp -j ACCEPT

## MAC2IP RULES ##
log "MAC2IP Rules..."

# MACPORTS — all known MACs (mac-*.txt + mac-hotspot.txt) allowed specific ports
if ! ipset list macports &>/dev/null; then
    ipset create macports hash:mac -exist
else
    ipset flush macports
fi
for mac in $(awk -F";" '$2 != "" {print $2}' $acl_mac_path/mac-* 2>/dev/null); do
    ipset add macports $mac -exist
done
if [ -f "$hotspot_path/mac-hotspot.txt" ]; then
    for mac in $(awk -F";" '$2 != "" {print $2}' $hotspot_path/mac-hotspot.txt); do
        ipset add macports $mac -exist
    done
fi

# DNS for macports — must be BEFORE macip ACCEPT/DROP in mangle
dns=$(echo "${SERV_DNS:-8.8.8.8,1.1.1.1}" | tr ',' ' ')
for dnsip in $dns; do
    iptables -t mangle -A PREROUTING -i $lan -m set --match-set macports src -d $dnsip -p udp --dport 53 -j ACCEPT
    iptables -t mangle -A PREROUTING -i $lan -m set --match-set macports src -d $dnsip -p tcp --dport 53 -j ACCEPT
    iptables -A FORWARD -i $lan -o $wan -m set --match-set macports src -d $dnsip -p udp --dport 53 -j ACCEPT
    iptables -A FORWARD -i $lan -o $wan -m set --match-set macports src -d $dnsip -p tcp --dport 53 -j ACCEPT
done
iptables -A FORWARD -i $lan -o $wan -p udp --dport 53 -j DROP
iptables -A FORWARD -i $lan -o $wan -p tcp --dport 53 -j DROP

# mac2ip — master gate: only known MAC+IP pairs pass mangle PREROUTING
mac2ip=$(sed -n '/^\s\+hardware\|^\s\+fixed/ s:hardware ethernet \|fixed-address ::p' "$dhcp_conf" | sed 's/;//')
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
        ipset add macip $ip,$mac -exist
        ips="$ips\n$ip"
        macs="$macs\n$mac"
    done
    echo -e "$ips" > "$path_ips"
    echo -e "$macs" > "$path_macs"
}
create_acl $mac2ip
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macip src,src -j ACCEPT
iptables -t mangle -A PREROUTING -i $lan -j DROP

log "OK"

## MAC RULES ##
log "MAC Rules"

# MACPROXY (PAC 18100 - Opcion 252 DHCP, HTTP 80 to 3128)
if ! ipset list macproxy &>/dev/null; then
    ipset create macproxy hash:mac -exist
else
    ipset flush macproxy
fi
for mac in $(awk -F";" '$2 != "" {print $2}' "$mac_proxy_file" 2>/dev/null); do
    ipset add macproxy $mac -exist
done
iptables -t mangle -A PREROUTING -i $lan -m set --match-set macproxy src -p tcp -m multiport --dports 18100,80 -j ACCEPT
iptables -t nat -A PREROUTING -i $lan -p tcp --dport 80 -m set --match-set macproxy src -j REDIRECT --to-port 3128
for chain in INPUT FORWARD; do
    iptables -A $chain -i $lan -p tcp -m multiport --dports 18100,3128 -m set --match-set macproxy src -j ACCEPT
done

# MACHOTSPOT (PAC 18100 - Opcion 252 DHCP, HTTP 80 to 3128)
if ! ipset list machotspot &>/dev/null; then
    ipset create machotspot hash:mac -exist
else
    ipset flush machotspot
fi
if [ -f "$hotspot_path/mac-hotspot.txt" ]; then
    for mac in $(awk -F";" '$2 != "" {print $2}' $hotspot_path/mac-hotspot.txt); do
        ipset add machotspot $mac -exist
    done
fi
# UNIFI PORTAL ACCESS + PAC (18100)
iptables -t mangle -A PREROUTING -i $lan -m set --match-set machotspot src -p tcp -m multiport --dports $cpd_tcp,18100,80 -j ACCEPT
iptables -A INPUT   -i $lan -m set --match-set machotspot src -p tcp -m multiport --dports $cpd_tcp,18100 -j ACCEPT
iptables -A FORWARD -i $lan -m set --match-set machotspot src -p tcp -m multiport --dports $cpd_tcp,18100 -j ACCEPT
# NAT
iptables -t nat -A PREROUTING -i $lan -p tcp --dport 80 -m set --match-set machotspot src -j REDIRECT --to-port 3128
for chain in INPUT FORWARD; do
    iptables -A $chain -i $lan -p tcp -m multiport --dports 18100,3128 -m set --match-set machotspot src -j ACCEPT
done

# MACTRANSPARENT (WARNING: Not recommended) (check blockports.txt)
#if ! ipset list mactransparent &>/dev/null; then
#    ipset create mactransparent hash:mac -exist
#else
#    ipset flush mactransparent
#fi
#for mac in $(awk -F";" '$2 != "" {print $2}' $acl_mac_path/mac-transparent.txt); do
#   ipset add mactransparent $mac -exist
#done
#for chain in INPUT FORWARD; do
#    iptables -A $chain -i $lan -p tcp -m multiport --dports 80,443,853 -m set --match-set mactransparent src -j ACCEPT
#done

log "OK"

## END ## 
log "Drop All..."
iptables -A INPUT -m hashlimit --hashlimit-name input-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip,dstport -j NFLOG --nflog-prefix "FINAL-INPUT DROP: "
iptables -A INPUT -j DROP
iptables -A FORWARD -m hashlimit --hashlimit-name forward-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip,dstport -j NFLOG --nflog-prefix "FINAL-FORWARD DROP: "
iptables -A FORWARD -j DROP

log "iptables Load at: $(date)"
log "Done"
