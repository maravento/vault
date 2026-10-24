#!/bin/bash
# maravento.com
#
################################################################################
#
# Iptables/Ipset Firewall O(1)
# FILE: scr/iptables.sh
#
# USAGE:
# sudo ./iptables.sh
#
# LOG: /var/log/iptables.log
#
################################################################################

set -euo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/iptables.log"
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# ACL PREPARATION
# Canonical block -- copied byte for byte into every script that creates a
# directory or a list under /etc/acl. Prepare /etc/acl first, then only the
# subdirectory and the lists this script needs. Never recursive.
# Usage: acl_prepare <dir> <dir_mode> <file_mode> [file ...]
acl_prepare() {
    local acl_dir="$1" dir_mode="$2" file_mode="$3" acl_file
    shift 3

    # mkdir without -p fails when the directory already exists, so a success
    # means this run created it and no concurrent run did.
    if mkdir -m "$dir_mode" -- "$acl_dir" 2>/dev/null; then
        if ! chown root:root -- "$acl_dir"; then
            log "ERROR: cannot set owner of $acl_dir -abort"
            exit 1
        fi
        log "WARNING: created ACL directory $acl_dir -alert"
    elif [ -d "$acl_dir" ] && [ ! -L "$acl_dir" ]; then
        acl_fix_perms "$acl_dir" "$dir_mode"
    else
        log "ERROR: $acl_dir is not a regular directory -abort"
        exit 1
    fi

    for acl_file in "$@"; do
        # Checked before the redirection: noclobber only protects regular
        # files, and opening a FIFO for writing blocks until a reader shows up.
        if [ -L "$acl_file" ] || { [ -e "$acl_file" ] && [ ! -f "$acl_file" ]; }; then
            log "ERROR: $acl_file is not a regular file -abort"
            exit 1
        fi
        # noclobber makes the redirection fail when the file already exists,
        # and umask 077 keeps the new file closed until chmod sets its mode.
        if (set -C; umask 077; : > "$acl_file") 2>/dev/null; then
            if ! { chmod "$file_mode" -- "$acl_file" \
                && chown root:root -- "$acl_file"; }; then
                log "ERROR: cannot set perms of $(basename "$acl_file") -abort"
                exit 1
            fi
            log "WARNING: created empty $(basename "$acl_file") -alert"
        elif [ -f "$acl_file" ] && [ ! -L "$acl_file" ]; then
            acl_fix_perms "$acl_file" "$file_mode"
        else
            log "ERROR: $acl_file is not a regular file -abort"
            exit 1
        fi
    done
}

# Repairs mode and owner of an existing ACL object, per Autorreparación
acl_fix_perms() {
    local acl_path="$1" want_mode="$2" cur_mode cur_owner
    cur_mode=$(stat -c '%a' -- "$acl_path" 2>/dev/null) || {
        log "ERROR: cannot stat $acl_path -abort"; exit 1; }
    cur_owner=$(stat -c '%U:%G' -- "$acl_path" 2>/dev/null) || {
        log "ERROR: cannot stat $acl_path -abort"; exit 1; }
    [[ "$cur_mode" == "$want_mode" && "$cur_owner" == "root:root" ]] && return 0
    if ! { chmod "$want_mode" -- "$acl_path" \
        && chown root:root -- "$acl_path"; }; then
        log "ERROR: cannot fix $acl_path perms -abort"
        exit 1
    fi
    log "INFO: $acl_path perms fixed -fixed"
}

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies
for dep_pkg in iptables ipset arptables ebtables kmod procps util-linux ulogd2 coreutils grep; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: dependency '$dep_pkg' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_NETMASK='^(0\.0\.0\.0|128\.0\.0\.0|192\.0\.0\.0|224\.0\.0\.0|240\.0\.0\.0|248\.0\.0\.0|252\.0\.0\.0|254\.0\.0\.0|255\.0\.0\.0|255\.128\.0\.0|255\.192\.0\.0|255\.224\.0\.0|255\.240\.0\.0|255\.248\.0\.0|255\.252\.0\.0|255\.254\.0\.0|255\.255\.0\.0|255\.255\.128\.0|255\.255\.192\.0|255\.255\.224\.0|255\.255\.240\.0|255\.255\.248\.0|255\.255\.252\.0|255\.255\.254\.0|255\.255\.255\.0|255\.255\.255\.128|255\.255\.255\.192|255\.255\.255\.224|255\.255\.255\.240|255\.255\.255\.248|255\.255\.255\.252|255\.255\.255\.254|255\.255\.255\.255)$'
UH_DNS='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])(,(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9]))*$'
UH_UINT='^(0|[1-9][0-9]*)$'
UH_MAC_RE='([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'
UH_MAC="^${UH_MAC_RE}$"
UH_PREFIX='0.0.0.0:0 128.0.0.0:1 192.0.0.0:2 224.0.0.0:3 240.0.0.0:4 248.0.0.0:5 252.0.0.0:6 254.0.0.0:7 255.0.0.0:8 255.128.0.0:9 255.192.0.0:10 255.224.0.0:11 255.240.0.0:12 255.248.0.0:13 255.252.0.0:14 255.254.0.0:15 255.255.0.0:16 255.255.128.0:17 255.255.192.0:18 255.255.224.0:19 255.255.240.0:20 255.255.248.0:21 255.255.252.0:22 255.255.254.0:23 255.255.255.0:24 255.255.255.128:25 255.255.255.192:26 255.255.255.224:27 255.255.255.240:28 255.255.255.248:29 255.255.255.252:30 255.255.255.254:31 255.255.255.255:32'

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# Network config -- pydhcp.env holds pydhcp's own values and is read here;
# gateproxy never writes into it. The proxy ports are gateproxy's own and
# live in OWN VALUES below.

# PERMS
# Owner and mode of every .env this script reads
pydhcp_env="/etc/pydhcp/pydhcp.env"
env_specs=("$pydhcp_env root:pydhcpd 640")
for env_spec in "${env_specs[@]}"; do
    read -r env_path env_owner_want env_perms_want <<< "$env_spec"
    if [ ! -f "$env_path" ]; then
        log "ERROR: $(basename "$env_path") not found -abort"
        exit 1
    fi
    env_owner=$(stat -c '%U:%G' "$env_path" 2>/dev/null)
    env_perms=$(stat -c '%a' "$env_path" 2>/dev/null)
    if [[ "$env_owner" != "$env_owner_want" ]] \
       || [[ "$env_perms" != "$env_perms_want" ]]; then
        if chown "$env_owner_want" "$env_path" 2>/dev/null \
           && chmod "$env_perms_want" "$env_path" 2>/dev/null; then
            log "INFO: $(basename "$env_path") perms fixed -fixed"
        else
            log "ERROR: cannot fix $(basename "$env_path") perms -abort"
            exit 1
        fi
    fi
done
unset env_specs env_spec env_path env_owner_want env_perms_want
unset env_owner env_perms

# LOAD_CONF
# Read known key=value pairs from a config file, without sourcing it
load_conf() {
    local conf_file="$1" env_key env_value env_line
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            log "ERROR: malformed line in $(basename "$conf_file"): '$env_line' -abort"
            exit 1
        fi
        case "$env_key" in
            INTERFACESv4|SERVER_IP|SERV_SUBNET|SERV_MASK|SERV_DNS|ACL_PATH|WAN_IFACE|WPAD_PORT|SQUID_MGR_PORT|SQUID_INTERCEPT_PORT)
                printf -v "$env_key" '%s' "$env_value"
                ;;
            *)
                ;;
        esac
    done < "$conf_file"
}

# LOAD
# Reads pydhcp.env; a missing key is handled by the check below
load_conf "$pydhcp_env" || true

# KEY CHECK
# Collect every failure first, then decide -- a single abort reports them all
key_errors=()
for env_key in WAN_IFACE INTERFACESv4 ACL_PATH; do
    if ! grep -q "^${env_key}=" "$pydhcp_env"; then
        key_errors+=("$env_key missing line")
    elif [[ -z "${!env_key:-}" ]]; then
        key_errors+=("$env_key not set")
    fi
done
for env_key in SERVER_IP SERV_SUBNET; do
    if ! grep -q "^${env_key}=" "$pydhcp_env"; then
        key_errors+=("$env_key missing line")
    elif [[ -z "${!env_key:-}" ]]; then
        key_errors+=("$env_key not set")
    elif ! [[ "${!env_key}" =~ $UH_IPV4 ]]; then
        key_errors+=("$env_key invalid IPv4")
    fi
done
if ! grep -q "^SERV_MASK=" "$pydhcp_env"; then
    key_errors+=("SERV_MASK missing line")
elif [[ -z "${SERV_MASK:-}" ]]; then
    key_errors+=("SERV_MASK not set")
elif ! [[ "$SERV_MASK" =~ $UH_NETMASK ]]; then
    key_errors+=("SERV_MASK invalid netmask")
fi
if ! grep -q "^SERV_DNS=" "$pydhcp_env"; then
    key_errors+=("SERV_DNS missing line")
elif [[ -z "${SERV_DNS:-}" ]]; then
    key_errors+=("SERV_DNS not set")
elif ! [[ "$SERV_DNS" =~ $UH_DNS ]]; then
    key_errors+=("SERV_DNS invalid DNS list")
fi
if ! grep -q "^WPAD_PORT=" "$pydhcp_env"; then
    key_errors+=("WPAD_PORT missing line")
elif [[ -z "${WPAD_PORT:-}" ]]; then
    key_errors+=("WPAD_PORT not set")
elif ! [[ "$WPAD_PORT" =~ $UH_UINT ]] \
     || [ "${#WPAD_PORT}" -gt 5 ] \
     || [ "$WPAD_PORT" -lt 1 ] || [ "$WPAD_PORT" -gt 65535 ]; then
    key_errors+=("WPAD_PORT invalid port")
fi
if (( ${#key_errors[@]} > 0 )); then
    for key_error in "${key_errors[@]}"; do
        log "WARNING: $key_error -alert"
    done
    log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$pydhcp_env") -abort"
    exit 1
fi
unset key_errors key_error env_key

# interfaces
wan_iface="$WAN_IFACE"
# LAN SERV_SUBNET/NETMASK (CIDR prefix derived from pydhcp's own SERV_MASK,
# no separate gateproxy key to keep in sync by hand)
# CIDR prefix derived from SERV_MASK, already validated by KEY CHECK
[[ " $UH_PREFIX " =~ [[:space:]]${SERV_MASK//./\.}:([0-9]+)[[:space:]] ]]
netmask_int="${BASH_REMATCH[1]}"
# PAC port announced by pydhcpd in DHCP option 252

# SQUID PORTS
# Read optional shared ports without changing this script's network variables
proxymon_env="/etc/proxymon/proxymon.env"
if [ -e "$proxymon_env" ]; then
    if [ ! -f "$proxymon_env" ]; then
        log "ERROR: proxymon.env is not a regular file -abort"
        exit 1
    fi
    squid_env_owner=$(stat -c %u "$proxymon_env") || {
        log "ERROR: cannot read proxymon.env owner -abort"; exit 1;
    }
    squid_env_mode=$(stat -c %a "$proxymon_env") || {
        log "ERROR: cannot read proxymon.env permissions -abort"; exit 1;
    }
    if [[ "$squid_env_owner" != 0 ]] || (( (8#$squid_env_mode & 022) != 0 )); then
        log "ERROR: proxymon.env: unsafe owner or permissions -abort"
        exit 1
    fi
    if ! squid_ports=$(
        unset SQUID_MGR_PORT SQUID_INTERCEPT_PORT
        load_conf "$proxymon_env" >/dev/null || exit 1
        printf '%s|%s' "${SQUID_MGR_PORT:-}" "${SQUID_INTERCEPT_PORT:-}"
    ); then
        log "ERROR: cannot read ports from proxymon.env -abort"
        exit 1
    fi
    IFS='|' read -r squid_port squid_intercept_port <<< "$squid_ports"
    for squid_key in SQUID_MGR_PORT SQUID_INTERCEPT_PORT; do
        if [[ "$squid_key" == SQUID_MGR_PORT ]]; then
            squid_value="$squid_port"
        else
            squid_value="$squid_intercept_port"
        fi
        if ! [[ "$squid_value" =~ $UH_UINT ]] || [ "${#squid_value}" -gt 5 ] || [ "$squid_value" -lt 1 ] || [ "$squid_value" -gt 65535 ]; then
            log "ERROR: proxymon.env: invalid $squid_key -abort"
            exit 1
        fi
    done
    unset squid_ports squid_key squid_value squid_env_owner squid_env_mode
else
    squid_port="3128"
    squid_intercept_port="3129"
fi

# ------------------------------------------------------------------------------
# ACL
# ------------------------------------------------------------------------------

# PATHS
# Declare the file and directory paths used below
acl_mac_path="${ACL_PATH:-/etc/acl}/mac"
acl_ipt_path="${ACL_PATH:-/etc/acl}/ipt"

# ACL/config files used by this script (existence verified below)
ACL_MAC_LIMITED="$acl_mac_path/mac-limited.txt"
ACL_MAC_UNLIMITED="$acl_mac_path/mac-unlimited.txt"
blockports_file="$acl_ipt_path/blockports.txt"
dhcp_conf="/etc/pydhcp/core/pydhcpd.conf"
path_ips="$acl_ipt_path/dhcp_ip.txt"
path_macs="$acl_ipt_path/dhcp_mac.txt"

for required_file in "$ACL_MAC_LIMITED" "$ACL_MAC_UNLIMITED" "$blockports_file" "$dhcp_conf"; do
    if [ ! -f "$required_file" ]; then
        log "ERROR: required file not found: $required_file -abort"
        exit 1
    fi
done
unset required_file
if [ ! -d "$acl_mac_path" ] || [ -z "$(ls -A "$acl_mac_path" 2>/dev/null)" ]; then
    log "ERROR: ACL_MAC_PATH missing or empty -abort"
    exit 1
fi

# REQUIRED DIRS
# This script writes its own lists here, so an empty dir is enough
acl_prepare "${ACL_PATH:-/etc/acl}" 755 644
acl_prepare "$acl_ipt_path" 700 600 "$path_ips" "$path_macs"

# start
log "iptables start..."

# ------------------------------------------------------------------------------
# MAC SETS
# ------------------------------------------------------------------------------

# The MAC sets are declared and filled here, in one place, before any rule
# uses them. macports has no list of its own: it is a set of sets, so adding a
# member costs no file read and no duplicated address.
mac_set() {
    local set_name="$1" src_file="$2" mac_addr invalid_count=0
    ipset create "$set_name" hash:mac -exist
    ipset flush "$set_name"
    if [ ! -f "$src_file" ]; then
        log "WARNING: $src_file not found -alert"
        return 0
    fi
    for mac_addr in $(awk -F";" 'NF>=2 && $1 == "a" && $2 != "" {print $2}' "$src_file"); do
        if [[ "$mac_addr" =~ $UH_MAC ]]; then
            ipset add "$set_name" "$mac_addr" -exist
        else
            invalid_count=$((invalid_count + 1))
        fi
    done
    if [ "$invalid_count" -gt 0 ]; then
        log "WARNING: $invalid_count invalid MACs in $(basename "$src_file") -alert"
    fi
    return 0
}

mac_set maclimited   "$ACL_MAC_LIMITED"
mac_set macunlimited "$ACL_MAC_UNLIMITED"

# MACPORTS
# Set of sets. One member today, maclimited; add more with a single ipset add
ipset create macports list:set -exist
ipset flush macports
ipset add macports maclimited -exist

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

# ------------------------------------------------------------------------------
# KERNEL RULES
# ------------------------------------------------------------------------------

# Zero all packets and counters
# Reset tables (IPv4)
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true
iptables -t raw -F 2>/dev/null || true
iptables -t raw -X 2>/dev/null || true
iptables -t security -F 2>/dev/null || true
iptables -t security -X 2>/dev/null || true
# Reset counters (IPv4)
iptables -Z 2>/dev/null || true
iptables -t nat -Z 2>/dev/null || true
iptables -t mangle -Z 2>/dev/null || true
# Reset tables (IPv6)
ip6tables -F 2>/dev/null || true
ip6tables -X 2>/dev/null || true
# Reset counters (IPv6)
ip6tables -Z 2>/dev/null || true
# Clear ARP and bridge
arptables -F 2>/dev/null || true
arptables -X 2>/dev/null || true
ebtables -F 2>/dev/null || true
ebtables -X 2>/dev/null || true
# Conntrack (Optional)
#conntrack -F 2>/dev/null || true

# ------------------------------------------------------------------------------
# IPv4
# ------------------------------------------------------------------------------

# SYSTEM OPTIMIZATION
# File handle, inotify and socket queue limits raised for a router under load
sysctl -w fs.file-max=2097152 >/dev/null 2>&1 || true
sysctl -w fs.inotify.max_user_watches=524288 >/dev/null 2>&1 || true
sysctl -w vm.overcommit_memory=1 >/dev/null 2>&1 || true
sysctl -w net.core.somaxconn=65535 >/dev/null 2>&1 || true

# CONNECTION TRACKING
# nf_conntrack_max/buckets only exist under /proc/sys once the nf_conntrack
# kernel module is loaded. On a cold boot this script can run before
# anything else has triggered that module to load, so the sysctl calls
# below would silently do nothing. Force the module to load first
# so tuning takes effect immediately, instead of depending on boot timing.
modprobe -q nf_conntrack 2>/dev/null || true
# Increase connection tracking table size for high concurrency
sysctl -w net.netfilter.nf_conntrack_max=524288 >/dev/null 2>&1 || true
sysctl -w net.netfilter.nf_conntrack_buckets=131072 >/dev/null 2>&1 || true

# SECURITY & NETWORK HARDENING
# Disable IP source routing (prevents IP spoofing and routing attacks)
sysctl -w net.ipv4.conf.all.accept_source_route=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.accept_source_route=0 >/dev/null 2>&1 || true
# Disable secure redirects (protects against malicious router advertisements)
# If you experience LAN routing issues, you can temporarily set this to 1.
sysctl -w net.ipv4.conf.all.secure_redirects=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.secure_redirects=0 >/dev/null 2>&1 || true
# Log packets with impossible or spoofed source addresses ("martians")
sysctl -w net.ipv4.conf.all.log_martians=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.log_martians=1 >/dev/null 2>&1 || true
# Enable strict reverse path filtering (drops packets with spoofed source IPs)
sysctl -w net.ipv4.conf.all.rp_filter=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.rp_filter=1 >/dev/null 2>&1 || true

# NETWORK PERFORMANCE & TCP PROTECTION
# Optimized TCP/IP parameters for high-performance and secure routing
# Enable TCP SYN cookies (protects against SYN flood attacks)
sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1 || true
# Increase SYN backlog queue and tune retries (helps prevent SYN flood)
sysctl -w net.ipv4.tcp_max_syn_backlog=20000 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_syn_retries=2 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_synack_retries=2 >/dev/null 2>&1 || true
# Enable RFC1337 fix (protects against TCP TIME-WAIT assassination)
sysctl -w net.ipv4.tcp_rfc1337=1 >/dev/null 2>&1 || true
# Expand available local port range (default: 32768-60999)
sysctl -w net.ipv4.ip_local_port_range="10000 65535" >/dev/null 2>&1 || true
# Reduce TCP FIN timeout (faster cleanup for orphaned sockets)
sysctl -w net.ipv4.tcp_fin_timeout=30 >/dev/null 2>&1 || true
# TCP keepalive settings (balance connection stability and resource usage)
sysctl -w net.ipv4.tcp_keepalive_time=300 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_keepalive_intvl=15 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_keepalive_probes=5 >/dev/null 2>&1 || true
# Enable TCP Fast Open (reduces latency for repeated connections)
sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1 || true
# Enable TCP performance features
sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1 || true
# Increase socket buffers
sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1 || true
sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1 || true
sysctl -w net.core.rmem_default=262144 >/dev/null 2>&1 || true
sysctl -w net.core.wmem_default=262144 >/dev/null 2>&1 || true
# TCP buffer auto-tuning
sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1 || true
# Enable PMTU discovery (recommended: automatic MTU adjustment)
sysctl -w net.ipv4.ip_no_pmtu_disc=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1 || true
# Increase network queue size (handles bursts of incoming packets)
sysctl -w net.core.netdev_max_backlog=20000 >/dev/null 2>&1 || true
# Increase TIME_WAIT socket capacity (important for busy NAT or proxy servers)
sysctl -w net.ipv4.tcp_max_tw_buckets=1000000 >/dev/null 2>&1 || true
# Allow safe TIME_WAIT socket reuse (improves connection efficiency)
sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1 || true

# ROUTING & FORWARDING
# Enable packet forwarding (required for NAT/routing)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
# Not a tuning value like the rest: without forwarding this host stops
# routing, and LAN clients get a lease that reaches nothing. Verified by
# its resulting state, not by sysctl's exit code, so a value already set
# by another means is accepted.
if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" != "1" ]; then
    log "ERROR: IPv4 forwarding is off, LAN cannot route -abort"
    exit 1
fi

# ARP OPTIMIZATION
# Enable ARP filtering (prevents incorrect replies when multiple interfaces exist)
sysctl -w net.ipv4.conf.all.arp_filter=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.arp_filter=1 >/dev/null 2>&1 || true
# ARP announce mode - only reply for local addresses
sysctl -w net.ipv4.conf.all.arp_announce=2 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.arp_announce=2 >/dev/null 2>&1 || true
# ARP ignore mode - only respond to ARPs for IPs on receiving interface
sysctl -w net.ipv4.conf.all.arp_ignore=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.arp_ignore=1 >/dev/null 2>&1 || true
# ARP cache tuning: reduce broadcast frequency and improve efficiency
# gc_thresh1/2/3 are global values, exposed under neigh/default only by
# convention. Every other key here is per-interface: neigh/default is just the
# template copied to interfaces created after it is written, so an interface
# that already exists keeps the kernel defaults unless it is set by name.
sysctl -w net.ipv4.neigh.default.gc_thresh1=128 >/dev/null 2>&1 || true
sysctl -w net.ipv4.neigh.default.gc_thresh2=512 >/dev/null 2>&1 || true
sysctl -w net.ipv4.neigh.default.gc_thresh3=1024 >/dev/null 2>&1 || true
sysctl -w "net.ipv4.neigh.${INTERFACESv4}.gc_stale_time=300" >/dev/null 2>&1 || true
# ARP solicitations before a neighbour is declared FAILED and its queued
# packets are dropped. Devices that enter deep sleep (printers, IoT) need
# seconds to answer, so this stays above the kernel default rather than below.
sysctl -w "net.ipv4.neigh.${INTERFACESv4}.ucast_solicit=6" >/dev/null 2>&1 || true
sysctl -w "net.ipv4.neigh.${INTERFACESv4}.mcast_solicit=6" >/dev/null 2>&1 || true
# Base reachable time for neighbor entries. Kept at the kernel default: this is
# how long a MAC is trusted without re-verification, and any DHCP pool recycles
# an IP between different devices, so a longer window would keep sending to the
# previous holder's MAC.
sysctl -w "net.ipv4.neigh.${INTERFACESv4}.base_reachable_time_ms=30000" >/dev/null 2>&1 || true

# KERNEL & FILESYSTEM HARDENING
# Enable full ASLR (Address Space Layout Randomization)
sysctl -w kernel.randomize_va_space=2 >/dev/null 2>&1 || true
# Protect hardlinks (prevents privilege escalation attacks)
sysctl -w fs.protected_hardlinks=1 >/dev/null 2>&1 || true
# Protect symlinks (prevents unauthorized link access in shared directories)
sysctl -w fs.protected_symlinks=1 >/dev/null 2>&1 || true

# ICMP
# Disable sending ICMP redirects (prevents MITM via route manipulation)
sysctl -w net.ipv4.conf.all.send_redirects=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.send_redirects=0 >/dev/null 2>&1 || true
# Disable accepting ICMP redirects from other hosts (security hardening)
sysctl -w net.ipv4.conf.all.accept_redirects=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.accept_redirects=0 >/dev/null 2>&1 || true
# Allow normal ICMP echo requests (ping)
sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1 || true
# Ignore ICMP echo requests sent to broadcast addresses (Smurf attack prevention)
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 >/dev/null 2>&1 || true
# Ignore bogus or malformed ICMP error responses
sysctl -w net.ipv4.icmp_ignore_bogus_error_responses=1 >/dev/null 2>&1 || true
# Rate limit ICMP message generation (100 ms minimum interval)
sysctl -w net.ipv4.icmp_ratelimit=100 >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# IPv6
# ------------------------------------------------------------------------------

sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
# LAN IPv6
sysctl -w "net.ipv6.conf.${INTERFACESv4}.disable_ipv6=1" >/dev/null 2>&1 || true
# Essential ICMPv6 (NDP, SLAAC, Path MTU)
ip6tables -A OUTPUT -o "$wan_iface" -p ipv6-icmp -j ACCEPT || true
# DHCPv6
ip6tables -A OUTPUT -o "$wan_iface" -p udp --sport 546 --dport 547 -j ACCEPT || true
# Established traffic
ip6tables -A INPUT -i "$wan_iface" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true

# ------------------------------------------------------------------------------
# GLOBAL RULES
# ------------------------------------------------------------------------------

# Global policies IPv4 (ACCEPT, then explicit drops)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Global policies IPv6 (closed by default)
ip6tables -P INPUT DROP || true
ip6tables -P FORWARD DROP || true
ip6tables -P OUTPUT DROP || true

# LOOPBACK
# Accept all traffic on the loopback interface
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT || true
ip6tables -A OUTPUT -o lo -j ACCEPT || true
iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j DROP
iptables -A FORWARD -s 127.0.0.0/8 ! -i lo -j DROP

# DHCP
# Let pydhcpd serve the LAN, and this host renew its own lease on the WAN
iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -p udp --dport 67 -j ACCEPT
iptables -A OUTPUT -o "$wan_iface" -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A INPUT -i "$wan_iface" -p udp --sport 67 --dport 68 -j ACCEPT
iptables -A INPUT -i "$INTERFACESv4" -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A OUTPUT -o "$INTERFACESv4" -p udp --sport 67 --dport 68 -j ACCEPT

# MASQUERADE: NAT for LAN to share dynamic WAN IP
iptables -t nat -A POSTROUTING -s "$SERV_SUBNET/$netmask_int" -o "$wan_iface" -j MASQUERADE
#
# SNAT example for static WAN IP (more efficient)
# wan_ip=$(ip -4 -o addr show dev "$wan_iface" | awk '{print $4}' | cut -d/ -f1)
# iptables -t nat -A POSTROUTING -s "$SERV_SUBNET/$netmask_int" -o "$wan_iface" -j SNAT --to-source "$wan_ip"

# LAN ---> PROXY <--- WAN
# Configure DHCP traffic and proxy routing between LAN and WAN
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
# Squid proxy outbound traffic
iptables -A OUTPUT -o "$wan_iface" -m owner --uid-owner proxy -j ACCEPT

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

# DNS (Global Policy)
# Applies to all INTERFACESv4 sources regardless of MAC list -- no list gets a free
# pass on bypassing the resolver or flooding it. Placed before MACUNLIMITED's
# blanket ACCEPT-all further down, so that rule never gets a chance to
# short-circuit this one.
# Burst limit
iptables -A FORWARD -i "$INTERFACESv4" -p udp --dport 53 -m state --state NEW -m recent --set --name DNS_DROPPER
iptables -A FORWARD -i "$INTERFACESv4" -p udp --dport 53 -m state --state NEW -m recent --update --seconds 1 --hitcount 15 --name DNS_DROPPER -j DROP
for dns_ip in ${SERV_DNS//,/ }; do
    for proto_name in tcp udp; do
        iptables -A INPUT -i "$INTERFACESv4" -d "$dns_ip" -p "$proto_name" --dport 53 -j ACCEPT
        iptables -A FORWARD -i "$INTERFACESv4" -d "$dns_ip" -p "$proto_name" --dport 53 -j ACCEPT
    done
done
for proto_name in tcp udp; do
    iptables -A FORWARD -i "$INTERFACESv4" -p "$proto_name" --dport 53 -m hashlimit --hashlimit-name dns-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip -j NFLOG --nflog-prefix "DNS-DROP: "
    iptables -A FORWARD -i "$INTERFACESv4" -p "$proto_name" --dport 53 -j DROP
done

# MAC2IP
# Enforce the configured MAC and IPv4 address bindings
mac2ip_rules=$(awk '
    /host [^{]+ \{/ { in_block=1; mac=""; ip="" }
    in_block && /hardware ethernet/ { mac=$3; gsub(/;/, "", mac) }
    in_block && /fixed-address/ { ip=$2; gsub(/;/, "", ip) }
    in_block && /\}/ {
        if (mac != "" && ip != "") print mac, ip
        in_block=0
    }
' "$dhcp_conf")
# Lowercase MAC-only view of MAC2IP, for the classified-MAC diagnostic below
# (has no static reservation, distinct from the ip,mac pairs macip itself uses).
mac2ip_macs=$(awk '{print tolower($1)}' <<< "$mac2ip_rules")
# rule MAC2IP
if ! ipset list macip &>/dev/null; then
    ipset create macip hash:ip,mac -exist
else
    ipset flush macip
fi
create_acl() {
    local ip_list mac_list mac_addr client_ip
    ip_list="# ips"
    mac_list="# macs"
    while (( $# >= 2 )); do
        mac_addr="$1"
        shift
        client_ip="$1"
        shift
        # Add MAC+IP to set
        [[ "$mac_addr" =~ $UH_MAC ]] && [[ "$client_ip" =~ $UH_IPV4 ]] && ipset add macip "$client_ip,$mac_addr" -exist
        ip_list="$ip_list\n$client_ip"
        mac_list="$mac_list\n$mac_addr"
    done
    echo -e "$ip_list" > "$path_ips"
    echo -e "$mac_list" > "$path_macs"
}
if [ -n "$mac2ip_rules" ]; then
    # create_acl expects a flat MAC IP MAC IP ... arg list (it shifts two at a
    # time). $mac2ip_rules is one "mac ip" pair per line, so it must still be split
    # into individual args -- but building that list explicitly (instead of
    # relying on bare unquoted word-splitting) avoids any accidental glob
    # expansion of a token.
    mac2ip_args=()
    while IFS=' ' read -r m2i_mac m2i_ip; do
        [[ -n "$m2i_mac" ]] && mac2ip_args+=("$m2i_mac")
        [[ -n "$m2i_ip" ]] && mac2ip_args+=("$m2i_ip")
    done <<< "$mac2ip_rules"
    create_acl "${mac2ip_args[@]}"
    iptables -t mangle -N MACCHECK 2>/dev/null || true
    iptables -t mangle -F MACCHECK
    iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -j MACCHECK
    iptables -t mangle -A MACCHECK -m set --match-set macip src,src -j RETURN
    iptables -t mangle -A MACCHECK -j DROP

    # ARP binding: drop ARP claiming a registered static IP from any MAC other
    # than the one it's leased to. iptables/ipset only see the IP layer, not
    # how that IP got resolved to a MAC on the wire -- this closes that gap.
    for ((arp_index=0; arp_index<${#mac2ip_args[@]}; arp_index+=2)); do
        arp_mac="${mac2ip_args[arp_index]}"
        arp_ip="${mac2ip_args[arp_index+1]}"
        [[ "$arp_mac" =~ $UH_MAC ]] && [[ "$arp_ip" =~ $UH_IPV4 ]] && \
            { arptables -A INPUT -i "$INTERFACESv4" --source-ip "$arp_ip" ! --source-mac "$arp_mac" -j DROP || true; }
    done
else
    log "WARNING: no static DHCP entries in $dhcp_conf -alert"
fi

# MACUNLIMITED (MAC + IP for Access Points, Switch, etc.)
iptables -t nat -A PREROUTING -i "$INTERFACESv4" -m set --match-set macunlimited src -j ACCEPT
iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -m set --match-set macunlimited src -j ACCEPT
# Unlimited devices never use the proxy -- block PAC access so DHCP option 252
# (WPAD, if enabled) has no effect on them, since pydhcpd is ACL-agnostic and
# sends it to every client regardless of classification.
iptables -A INPUT -i "$INTERFACESv4" -p tcp -m multiport --dports $squid_port,$WPAD_PORT -m set --match-set macunlimited src -j DROP
for chain_name in INPUT FORWARD; do
    iptables -A "$chain_name" -i "$INTERFACESv4" -m set --match-set macunlimited src -j ACCEPT
done

# ------------------------------------------------------------------------------
# SECURITY RULES
# ------------------------------------------------------------------------------

# BOGONS
# Reserved and unroutable address ranges. Optional and disabled by default:
# enable the whole block only if the LAN range is not listed in bogons.txt,
# or it will block the local network.
#bogons_file="$acl_ipt_path/bogons.txt"
#bogons_url="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/gateproxy/acl/ipt/bogons.txt"
#if [ ! -f "$bogons_file" ]; then
#    if curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$bogons_file" "$bogons_url"; then
#        chown root:root "$bogons_file"
#    else
#        log "WARNING: cannot download $bogons_file -skip"
#    fi
#fi

#if ! ipset list bogons &>/dev/null; then
#    ipset create bogons hash:net -exist
#else
#    ipset flush bogons
#fi
#if [ -f "$bogons_file" ]; then
#    for bogons_cidr in $(grep -vE '^\s*#|^\s*$' "$bogons_file" | awk '{print $1}' | sort -V -u 2>/dev/null); do
#        ipset add bogons "$bogons_cidr" -exist
#    done
#else
#    log "WARNING: $bogons_file not found, bogons -skip"
#fi

# Allow 255.255.255.0/24 before BOGONS DROP
#iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -s 255.255.255.0/24 -j ACCEPT
#iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -d 255.255.255.0/24 -j ACCEPT
# DROP bogons
#iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -m set --match-set bogons src -j DROP
#iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -m set --match-set bogons dst -j DROP

# WAN ingress: drop spoofed traffic claiming a reserved/private source address.
# dst intentionally omitted -- this host may itself sit behind CGNAT/double-NAT
# on a private WAN address, which a dst check would wrongly match and drop.
#iptables -t mangle -A PREROUTING -i "$wan_iface" -m set --match-set bogons src -j DROP

# BLOCKPORTS
# path: /etc/acl/ipt/blockports.txt
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
# - HTTP-Proxy Alternative (8080,8000,3130) - TCP
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
for blocked_ports in $(sort -V -u "$blockports_file" 2>/dev/null); do
    [[ "$blocked_ports" =~ $UH_UINT ]] && [ "${#blocked_ports}" -le 5 ] && [ "$blocked_ports" -le 65535 ] && ipset add blockports "$blocked_ports" -exist
done
for proto_name in tcp udp; do
    iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -p "$proto_name" -m set --match-set blockports dst -j DROP
done

# SURIDATA
# Drop traffic to addresses Suricata flagged, and log the attempt
suridata_file="/etc/suricata/suridata.txt"
if ! ipset list suridata &>/dev/null; then
    ipset create suridata hash:ip -exist
else
    ipset flush suridata
fi
if [ -f "$suridata_file" ]; then
    for suridata_ip in $(grep -vE '^\s*#|^\s*$' "$suridata_file" | sort -u 2>/dev/null); do
        [[ "$suridata_ip" =~ $UH_IPV4 ]] && ipset add suridata "$suridata_ip" -exist
    done
else
    log "WARNING: $suridata_file not found -alert"
fi
iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -m set --match-set suridata dst -j NFLOG --nflog-prefix "SURIDATA DROP: "
iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -m set --match-set suridata dst -j DROP

# Block 6to4 (IPv6-in-IPv4 tunneling) - prevents LAN clients from bypassing
# IPv4-based firewall rules via IPv6 tunnel encapsulation
iptables -A FORWARD -i "$INTERFACESv4" -p 41 -j DROP

# NETBIOS NMBD (disabled in smb.conf)
for chain_name in INPUT FORWARD; do
    iptables -A "$chain_name" -i "$INTERFACESv4" -p udp -m multiport --dports 137,138 -j DROP
    iptables -A "$chain_name" -i "$INTERFACESv4" -p tcp --dport 139 -j DROP
done
# CoAP/CoAPs 5683/5684
for chain_name in INPUT FORWARD; do
    iptables -A "$chain_name" -i "$INTERFACESv4" -p udp -m multiport --dports 5683,5684 -j DROP
done

# syncflood
iptables -N syn_flood 2>/dev/null || true
iptables -A INPUT -i "$wan_iface" -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn_flood
iptables -A INPUT -i "$INTERFACESv4" -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn_flood
iptables -A FORWARD -i "$wan_iface" -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn_flood
iptables -A FORWARD -i "$INTERFACESv4" -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -j syn_flood
iptables -A syn_flood -i "$wan_iface" -m limit --limit 50/s --limit-burst 200 -j RETURN
iptables -A syn_flood -i "$INTERFACESv4" -m limit --limit 200/s --limit-burst 500 -j RETURN
iptables -A syn_flood -m limit --limit 1/min -j NFLOG --nflog-prefix "SYNFLOOD: "
iptables -A syn_flood -j DROP

# Windows Update Delivery Optimization (WUDO)
# Allow peer-to-peer update sharing within the local network.
# Block outbound WUDO traffic to WAN and direct connections to the firewall.
for proto_name in tcp udp; do
    iptables -A FORWARD -i "$INTERFACESv4" -p "$proto_name" --dport 7680 -s "$SERV_SUBNET/$netmask_int" -d "$SERV_SUBNET/$netmask_int" -j ACCEPT
done
for chain_name in INPUT FORWARD; do
    for proto_name in tcp udp; do
        iptables -A "$chain_name" -i "$INTERFACESv4" -p "$proto_name" --dport 7680 -j DROP
    done
done

# Block GRE (Generic Routing Encapsulation) proto_name 47
for chain_name in INPUT FORWARD; do
    iptables -A "$chain_name" -i "$INTERFACESv4" -p 47 -j DROP
done
# Block Windows ICS (Internet Connection Sharing) network range
iptables -A FORWARD -i "$INTERFACESv4" -d 192.168.137.0/24 -j DROP
# Block WS-Discovery unicast to server (Windows clients noise)
iptables -A INPUT -i "$INTERFACESv4" -p udp --sport 3702 -d "$SERVER_IP" -j DROP
# KMS Windows activation noise
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport 1688 -j ACCEPT
iptables -A FORWARD -i "$INTERFACESv4" -o "$wan_iface" -p tcp --dport 1688 -j ACCEPT
# Spotify LAN sync broadcast noise
iptables -A INPUT -i "$INTERFACESv4" -p udp --dport 57621 -j DROP
# Cisco IP phones discovery noise
iptables -A INPUT -i "$INTERFACESv4" -p udp -m multiport --dports 2007,2008 -j DROP
# SAP broadcast noise (Optional)
iptables -A INPUT -i "$INTERFACESv4" -p udp --dport 3289 -j DROP
# Dropbox LAN sync broadcast noise
iptables -A INPUT -i "$INTERFACESv4" -p udp --dport 17500 -j DROP

# ICMP (ping) (Optional)
# WARNING:
# You need to change the following kernel parameter in the header of this script:
# sysctl -w net.ipv4.icmp_echo_ignore_all=0 >/dev/null 2>&1
# NOTE: For nmap scans, increase limit to 100/second or use -Pn in nmap options
#iptables -A INPUT -p icmp -m limit --limit 10/second -j ACCEPT
#iptables -A FORWARD -p icmp -m limit --limit 10/second -j ACCEPT
#iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
# Silence ICMP forward noise
iptables -A FORWARD -i "$INTERFACESv4" -o "$wan_iface" -p icmp -j DROP

# ------------------------------------------------------------------------------
# MAC PORTS
# ------------------------------------------------------------------------------

# PROXYMON: WARNING PAGE HTTP FOR BANDATA
# https://github.com/maravento/proxymon
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport 18081 -m set --match-set macports src -j ACCEPT
# SMBSTACK
# https://github.com/maravento/smbstack
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport 3092 -m set --match-set macports src -j ACCEPT

# PROXYMON: WARNING PAGE HTTP FOR BANDATA
# https://github.com/maravento/proxymon
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport 18081 -m set --match-set macports src -j ACCEPT
# SMBSTACK
# https://github.com/maravento/smbstack
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport 3092 -m set --match-set macports src -j ACCEPT

# COMMONS PORTS
# SMB / Microsoft-DS
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport 445 -m set --match-set macports src -j ACCEPT
# Printers (printer/scanner PROTOCOL traffic addressed to the proxy itself)
iptables -A INPUT -i "$INTERFACESv4" -p udp -m multiport --dports 161,162,3910,3911 -m set --match-set macports src -j ACCEPT
iptables -A INPUT -i "$INTERFACESv4" -p tcp -m multiport --dports 9100,3910,3911 -m set --match-set macports src -j ACCEPT
# Printers & Scanners UDP (SNMP 161,162 + prnrequest/prnstatus 3910/3911)
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -p udp -m multiport --dports 161,162,3910,3911 -m set --match-set macports src -j ACCEPT
# Printers & Scanners TCP (JetDirect/RAW 9100 + prnrequest/prnstatus 3910/3911)
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -p tcp -m multiport --dports 9100,3910,3911 -m set --match-set macports src -j ACCEPT
# STUN/TURN (WebRTC, Teams, Meet, Zoom)
iptables -A FORWARD -i "$INTERFACESv4" -o "$wan_iface" -p udp -m multiport --dports 3478:3481 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$INTERFACESv4" -o "$wan_iface" -p tcp -m multiport --dports 3478,5349 -m set --match-set macports src -j ACCEPT
# Google STUN
iptables -A FORWARD -i "$INTERFACESv4" -o "$wan_iface" -p udp -m multiport --dports 19302:19309 -m set --match-set macports src -j ACCEPT
# Email (SMTP, IMAP, POP3)
iptables -A FORWARD -i "$INTERFACESv4" -p tcp -m multiport --dports 110,143,465,587,993,995 -m set --match-set macports src -j ACCEPT
# Messaging & XMPP (Jabber, FCM)
iptables -A FORWARD -i "$INTERFACESv4" -p tcp -m multiport --dports 5222,5223,5228,5269 -m set --match-set macports src -j ACCEPT
# WSD (Web Services Discovery) - TCP
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -p tcp -m multiport --dports 5357,5358 -m set --match-set macports src -j ACCEPT
# mDNS LAN (noise)
iptables -A INPUT -i "$INTERFACESv4" -d 224.0.0.251 -p udp --dport 5353 -j DROP
# Drop local multicast (collaboration tools, discovery, etc.)
iptables -A INPUT -i "$INTERFACESv4" -d 239.255.0.0/16 -j DROP
# mDNS / Bonjour / AirPrint
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -d 224.0.0.251 -p udp --dport 5353 -m set --match-set macports src -j ACCEPT
# LLMNR (Name resolution between LAN devices when there is no DNS entry)
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -d 224.0.0.252 -p udp --dport 5355 -m set --match-set macports src -j ACCEPT
# SSDP / UPnP
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -d 239.255.255.250 -p udp --dport 1900 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -p udp --dport 5000 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$INTERFACESv4" -p udp -m multiport --dports 1900,5000 -m set --match-set macports src -j DROP
# WSD (Device discovery on the LAN, used by printers and scanners)
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -d 239.255.255.250 -p udp --dport 3702 -m set --match-set macports src -j ACCEPT
# Multimedia & Streaming
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -p tcp -m multiport --dports 2869,8200 -m set --match-set macports src -j ACCEPT
# IGMP (required for multicast group management)
iptables -A FORWARD -i "$INTERFACESv4" -o "$INTERFACESv4" -p igmp -m set --match-set macports src -j ACCEPT
# NTP (Time sync against this host, and out to the internet)
iptables -A INPUT -i "$INTERFACESv4" -p udp --dport 123 -m set --match-set macports src -j ACCEPT
iptables -A FORWARD -i "$INTERFACESv4" -p udp --dport 123 -m set --match-set macports src -j ACCEPT

# ------------------------------------------------------------------------------
# MACRULES
# ------------------------------------------------------------------------------

# MACLIMITED
# PAC on WPAD_PORT - DHCP option 252, HTTP 80 -> Squid intercept port
# Send limited devices through Squid and serve them the PAC file
iptables -t mangle -A PREROUTING -i "$INTERFACESv4" -m set --match-set maclimited src -p tcp -m multiport --dports $WPAD_PORT,80,$squid_port -j ACCEPT
iptables -t nat -A PREROUTING -i "$INTERFACESv4" -p tcp --dport 80 -m set --match-set maclimited src -j REDIRECT --to-port "$squid_intercept_port"
iptables -A INPUT -i "$INTERFACESv4" -p tcp --dport "$squid_intercept_port" -m set --match-set maclimited src -m conntrack --ctstate DNAT -j ACCEPT
iptables -A INPUT -i "$INTERFACESv4" -p tcp -m multiport --dports $WPAD_PORT,$squid_port -m set --match-set maclimited src -j ACCEPT

# Diagnostic only: warn about classified MACs with no static reservation in
# pydhcpd.conf -- MACCHECK drops their traffic regardless of classification.
for check_file in "$acl_mac_path"/mac-*.txt; do
    [ -f "$check_file" ] || continue
    while IFS=';' read -r mac_status client_mac mac_rest; do
        [ "$mac_status" = "a" ] || continue
        [[ "$client_mac" =~ $UH_MAC ]] || continue
        client_mac_lc="${client_mac,,}"
        if ! grep -qxF "$client_mac_lc" <<< "$mac2ip_macs"; then
            log "WARNING: $client_mac ($(basename "$check_file")) has no static reservation"
            log "WARNING: MACCHECK drops it until added or reloaded -alert"
        fi
    done < "$check_file"
done

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# FINAL DROP
# Anything not accepted above is dropped and sampled into the log
iptables -A INPUT -m hashlimit --hashlimit-name input-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip,dstport -j NFLOG --nflog-prefix "FINAL-INPUT DROP: "
iptables -A INPUT -j DROP
iptables -A FORWARD -m hashlimit --hashlimit-name forward-drop --hashlimit-above 3/min --hashlimit-burst 3 --hashlimit-mode srcip,dstport -j NFLOG --nflog-prefix "FINAL-FORWARD DROP: "
iptables -A FORWARD -j DROP

log "iptables done at: $(date '+%Y-%m-%d %H:%M:%S')"
