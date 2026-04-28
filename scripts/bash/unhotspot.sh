#!/bin/bash
# maravento.com
#
# UniFi Network Hotspot - ACL Manager v4
#
# USAGE:
#   Manual : sudo /etc/scr/unhotspot.sh
#   Cron   : * * * * * /etc/scr/unhotspot.sh >> /var/log/unhotspot.log 2>&1
#
# DEPENDENCIES:
#   isc-dhcp-server, iptables, ipset, jq, curl, bash, UniFi Controller
#
# TESTED ON:
#   Ubuntu 24.04.x — UniFi OS Network 10.3.55
#
# UNIFI PRE-REQUISITES:
#   - Create a guest SSID (e.g.: Guests) with Hotspot / Captive Portal
#   - On Landing Page: disable "HTTPS Redirection Support" and "Encrypted URL"
#   - On Pre-Authorization Allowances: add LAN range (e.g.: 192.168.10.0/24)
#   - Optional: disable "Client Device Isolation"
#
# LOGIC:
#   The script runs every minute via cron and executes 4 steps:
#
#   1. DEDUP: verifies that no MAC appears in more than one list.
#      If a MAC is in guest-pending.txt or in any mac-*.txt,
#      it is automatically removed from blockdhcp.txt and dhcpd.leases.
#
#   2. EXPIRED: iterates over mac-hotspot.txt looking for expired vouchers
#      (END_TIME < now). Moves them to guest-pending.txt preserving IP and hostname.
#
#   3. PENDING: queries stat/guest on the UniFi API. Clients connected
#      to the portal without a voucher receive a random IP from the configured
#      range and a sequential hostname (guest1, guest2...), are added to
#      guest-pending.txt and their lease is removed from dhcpd.leases.
#
#   4. SESSIONS: queries stat/session. Clients that completed the voucher
#      are moved from guest-pending.txt to mac-hotspot.txt with their end_time.
#      If ACLs changed, the DHCP server (isc-dhcp-server) must be restarted
#      and iptables rules reloaded for changes to take effect.
#
# ACL FORMAT:
#   mac-hotspot.txt   → a;MAC;IP;HOSTNAME;END_TIME_EPOCH;
#   guest-pending.txt → a;MAC;IP;HOSTNAME;
#
# DISCLAIMER:
#   Distributed without warranty. Use at your own risk.
#   Always test in a controlled environment before production.

# ─── Bootstrap ────────────────────────────────────────────────────────────────
# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# Detect local user (used as owner for generated files)
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
CONFIG_FILE="/etc/unhotspot/config.conf"
COOKIE_FILE="/etc/unhotspot/unifi-session.cookie"
MAC_LIST="/etc/acl/mac-hotspot.txt"
PENDING_LIST="/etc/acl/guest-pending.txt"
LOG_FILE="/var/log/unhotspot.log"
LEASES_CHANGED=0

# ─── Permanent MAC block list ─────────────────────────────────────────────────
# ACL file for MAC addresses that must be permanently denied a DHCP lease,
# regardless of voucher or guest status (e.g. banned or untrusted devices).
# Add one MAC per line using the standard ACL format: a;MAC;IP;HOSTNAME;
#
# To enforce this list you must configure a deny class in your dhcpd.conf:
#   class "blocked" {
#       match if binary-to-ascii(16,8,":",substring(option dhcp-client-identifier,1,6)) = <MAC>;
#   }
#   subclass "blocked" <MAC>;   # repeat for each blocked MAC
#   deny members of "blocked";  # place inside your subnet { } block
#
# This script automatically removes any entry found here from dhcpd.leases.

# Defaults — overridden by config.conf
HOTSPOT_ESSID=""
HOTSPOT_IP_RANGE="192.168.10"
HOTSPOT_RANGE_START=160
HOTSPOT_RANGE_END=170

UNIFI_CONTROLLER_URL=""
UNIFI_USERNAME=""
UNIFI_PASSWORD=""
UNIFI_SITE="default"
UNIFI_TYPE=""      # "unifi-os" or "classic"
CSRF_TOKEN=""
VOUCHER_CACHE=""

# ─── BLOCKDHCP.TXT ────────────────────────────────────────────────────────────
# File: /etc/acl/blockdhcp.txt
# Format: a;MAC;IP;HOSTNAME
# Purpose: Temporary blacklist for MAC addresses that are not yet authorized.
#          When a new client connects via DHCP, its MAC is added here.
#          Once authenticated (moved to mac-hotspot.txt or guest-pending.txt),
#          it should be removed from blockdhcp.txt by your DHCP management logic.
#
# Requirements in dhcpd.conf:
#   class "blockdhcp" {
#       match pick-first-value (option dhcp-client-identifier, hardware);
#   }
#
#   pool {
#       deny members of "blockdhcp";
#       range 192.168.10.230 192.168.10.250;
#   }
#
# How it works: leases.sh reads blockdhcp.txt and adds each MAC as:
#   subclass "blockdhcp" 1:MAC;
BLOCK_DHCP="/etc/acl/blockdhcp.txt"

# ─── Reload script ───────────────────────────────────────────────────────────
# Script invoked automatically whenever the ACL files change (new authorizations,
# expirations, or revocations). Use it to restart or reload every service that
# depends on the ACL files, for example:
#   systemctl restart isc-dhcp-server
#   bash /etc/iptables/rules.sh
# The script must exist and be executable (chmod +x).
# Set the path in config.conf via SERVER_RELOAD_SCRIPT="/path/to/serverload.sh"
SERVER_RELOAD_SCRIPT="/etc/scr/serverload.sh" # overridden by config.conf

# ─── Setup input helpers ──────────────────────────────────────────────────────

# Generic prompt — if default provided, accepts Enter; otherwise loops until non-empty
ask() {
    local prompt="$1" default="$2" var="$3" answer
    if [[ -n "$default" ]]; then
        read -rp "  ${prompt} [${default}]: " answer
        printf -v "$var" '%s' "${answer:-$default}"
    else
        while true; do
            read -rp "  ${prompt}: " answer
            [[ -n "$answer" ]] && break
            echo "  ✗ This field is required."
        done
        printf -v "$var" '%s' "$answer"
    fi
}

# Prompt for a network interface — validates it exists on the system
ask_interface() {
    local prompt="$1" default="$2" var="$3" answer
    while true; do
        read -rp "  ${prompt} [${default}]: " answer
        answer="${answer:-$default}"
        if ip link show "$answer" &>/dev/null; then
            printf -v "$var" '%s' "$answer"
            break
        fi
        echo "  ✗ Interface '$answer' not found. Available: $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | tr '\n' ' ')"
    done
}

# Prompt for a full IPv4 address — validates x.x.x.x format, each octet 0-255
ask_ip() {
    local prompt="$1" var="$2" answer
    while true; do
        read -rp "  ${prompt}: " answer
        if [[ "$answer" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            local valid=1
            IFS='.' read -ra octs <<< "$answer"
            for o in "${octs[@]}"; do
                (( o < 0 || o > 255 )) && valid=0 && break
            done
            [[ $valid -eq 1 ]] && printf -v "$var" '%s' "$answer" && break
        fi
        echo "  ✗ '$answer' is not a valid IPv4 address (e.g. 192.168.10.2)."
    done
}

# Prompt for the first 3 octets of an IP range — validates x.x.x format
ask_ip_range() {
    local prompt="$1" default="$2" var="$3" answer
    while true; do
        read -rp "  ${prompt} [${default}]: " answer
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]]; then
            local valid=1
            IFS='.' read -ra octs <<< "$answer"
            for o in "${octs[@]}"; do
                (( o < 0 || o > 255 )) && valid=0 && break
            done
            [[ $valid -eq 1 ]] && printf -v "$var" '%s' "$answer" && break
        fi
        echo "  ✗ '$answer' is not valid. Enter 3 octets only (e.g. 192.168.10)."
    done
}

# Prompt for a host octet (1-254) — also checks START < END when var is END
ask_octet() {
    local prompt="$1" default="$2" var="$3" ref_start="${4:-0}" answer
    while true; do
        read -rp "  ${prompt} [${default}]: " answer
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= 254 )); then
            if [[ -n "$ref_start" ]] && (( answer <= ref_start )); then
                echo "  ✗ End octet must be greater than start octet (${ref_start})."
                continue
            fi
            printf -v "$var" '%s' "$answer"
            break
        fi
        echo "  ✗ '$answer' is not valid. Enter a number between 1 and 254."
    done
}

# ─── Controller discovery ──────────────────────────────────────────────────────
discover_unifi_controller() {
    local user="$1" pass="$2" scan_base="$3"
    local ports=(443 8443 11443)
    local candidates=()

    echo "  Scanning ${scan_base}.0/24 on ports 443, 8443, 11443 ..."
    echo "  (This may take a few seconds)"

    for port in "${ports[@]}"; do
        while IFS= read -r host; do
            [[ -n "$host" ]] && candidates+=("${host}:${port}")
        done < <(
            for i in $(seq 1 254); do
                (
                    if bash -c ">/dev/tcp/${scan_base}.${i}/${port}" 2>/dev/null; then
                        echo "${scan_base}.${i}"
                    fi
                ) &
            done
            wait
        )
    done

    for candidate in "${candidates[@]}"; do
        local host port test_url http_code
        host="${candidate%%:*}"
        port="${candidate##*:}"
        test_url="https://${host}:${port}"

        # Try UniFi OS endpoint first
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "${test_url}/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${user}\",\"password\":\"${pass}\"}" \
            --connect-timeout 3 || echo "000")
        if [[ "$http_code" == "200" ]]; then
            echo "  ✔ Found UniFi OS controller at ${test_url}"
            DISCOVERED_URL="$test_url"
            DISCOVERED_TYPE="unifi-os"
            return 0
        fi

        # Try classic endpoint
        http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "${test_url}/api/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"${user}\",\"password\":\"${pass}\"}" \
            --connect-timeout 3 || echo "000")
        if [[ "$http_code" == "200" ]]; then
            echo "  ✔ Found classic UniFi controller at ${test_url}"
            DISCOVERED_URL="$test_url"
            DISCOVERED_TYPE="classic"
            return 0
        fi
    done

    return 1
}

# ─── Interactive setup (runs only when config.conf is missing) ────────────────
setup_config() {
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  UniFi Network Hotspot ACL Manager — First-time setup"
    echo "══════════════════════════════════════════════════"
    echo "  Config file not found: $CONFIG_FILE"
    echo "  Answer the following questions to create it."
    echo "══════════════════════════════════════════════════"
    echo ""

    # ── Network interfaces ────────────────────────────────────────────────────
    echo "── Network ──────────────────────────────────────"
    local ifaces
    ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | tr '\n' '  ')
    echo "  Available interfaces: $ifaces"
    ask_interface "WAN interface" "eth0" CFG_WAN_IF
    ask_interface "LAN interface" "eth1" CFG_LAN_IF
    ask_ip        "Server IP (this machine)" CFG_SERVER_IP

    # ── Hotspot IP range ──────────────────────────────────────────────────────
    echo ""
    echo "── Hotspot IP range ─────────────────────────────"
    ask_ip_range "IP range base (first 3 octets)" "192.168.10" CFG_IP_RANGE
    ask_octet    "Range start (last octet)" "160" CFG_RANGE_START
    ask_octet    "Range end   (last octet)" "170" CFG_RANGE_END "$CFG_RANGE_START"

    # ── Guest SSID ────────────────────────────────────────────────────────────
    echo ""
    echo "── Hotspot SSID ─────────────────────────────────"
    ask "Guest SSID name (must match exactly in UniFi)" "" CFG_ESSID

    # ── UniFi credentials ─────────────────────────────────────────────────────
    echo ""
    echo "── UniFi credentials ────────────────────────────"
    ask "UniFi admin username" "admin" CFG_UNIFI_USER
    while true; do
        read -rsp "  UniFi admin password: " CFG_UNIFI_PASS; echo ""
        [[ -n "$CFG_UNIFI_PASS" ]] && break
        echo "  ✗ Password cannot be empty."
    done

    # ── Controller discovery ──────────────────────────────────────────────────
    echo ""
    echo "── Scanning for UniFi Controller ───────────────"
    local scan_base found_url="" found_type=""
    scan_base=$(echo "$CFG_SERVER_IP" | awk -F'.' '{print $1"."$2"."$3}')
    DISCOVERED_URL=""
    DISCOVERED_TYPE=""

    if discover_unifi_controller "$CFG_UNIFI_USER" "$CFG_UNIFI_PASS" "$scan_base"; then
        found_url="$DISCOVERED_URL"
        found_type="$DISCOVERED_TYPE"
    else
        echo "  ✗ No UniFi controller detected automatically."
        ask "Enter controller URL manually (e.g. https://192.168.1.1:8443)" "" found_url
        echo "  Enter controller type:"
        select found_type in "unifi-os" "classic"; do
            [[ -n "$found_type" ]] && break
        done
    fi

    # ── Write config.conf ─────────────────────────────────────────────────────
    echo ""
    echo "── Writing $CONFIG_FILE ─────────────────────────"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    chmod 700 "$(dirname "$CONFIG_FILE")"

    cat > "$CONFIG_FILE" <<EOF
# UniFi Network Hotspot - ACL Manager v4
# Auto-generated by setup on $(date '+%Y-%m-%d %H:%M:%S')
# Edit this file to adjust any value.

# ── Network ───────────────────────────────────────────────────────────────────
WAN_IF="${CFG_WAN_IF}"
LAN_IF="${CFG_LAN_IF}"
SERVER_IP="${CFG_SERVER_IP}"
LOCAL_USER="${local_user}"

# ── Hotspot IP range ──────────────────────────────────────────────────────────
HOTSPOT_IP_RANGE="${CFG_IP_RANGE}"
HOTSPOT_RANGE_START=${CFG_RANGE_START}
HOTSPOT_RANGE_END=${CFG_RANGE_END}

# ── Guest SSID ────────────────────────────────────────────────────────────────
HOTSPOT_ESSID="${CFG_ESSID}"

# ── UniFi Controller ──────────────────────────────────────────────────────────
UNIFI_CONTROLLER_URL="${found_url}"
UNIFI_USERNAME="${CFG_UNIFI_USER}"
UNIFI_PASSWORD="${CFG_UNIFI_PASS}"
UNIFI_SITE="default"
UNIFI_TYPE="${found_type}"

# ── Fixed ports (edit only if your setup differs) ─────────────────────────────
# Ports kept open on the captive portal for DNS, DHCP, and UniFi traffic
PORTAL_PORTS="53,67,68,8880,8881,8882,8843"
# Ports allowed on the LAN for local services (SMB, SNMP, printing, proxy, etc.)
LOCAL_PORTS="137:139,445,162,631,8000,3128,853"

# ── Reload script ─────────────────────────────────────────────────────────────
# Create this script and add every service/rule to reload after ACL changes.
# Example contents:
#   systemctl restart isc-dhcp-server
#   bash /etc/iptables/rules.sh
# The script must be executable: chmod +x /etc/unhotspot/serverload.sh
SERVER_RELOAD_SCRIPT="/etc/unhotspot/serverload.sh"
EOF

    chmod 600 "$CONFIG_FILE"
    echo "  ✔ Config saved to $CONFIG_FILE"
    echo ""
}

# ─── Load config ──────────────────────────────────────────────────────────────
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        setup_config
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    if [[ -z "$UNIFI_CONTROLLER_URL" || -z "$UNIFI_USERNAME" || -z "$UNIFI_PASSWORD" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: UNIFI_CONTROLLER_URL, UNIFI_USERNAME and UNIFI_PASSWORD must be set in $CONFIG_FILE"
        exit 1
    fi
}

# ─── Logging ──────────────────────────────────────────────────────────────────
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"; }

# ─── ACL file init ────────────────────────────────────────────────────────────
init_acl_files() {
    mkdir -p "$(dirname "$MAC_LIST")" "$(dirname "$LOG_FILE")"
    touch "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"
    chmod 644 "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"

    if [[ ! -s "$MAC_LIST" ]]; then
        echo "a;02:00:00:00:00:00;0.0.0.0;guest-placeholder" >> "$MAC_LIST"
    fi
}

# ─── UniFi API ────────────────────────────────────────────────────────────────
api_path() {
    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        echo "${UNIFI_CONTROLLER_URL}/proxy/network/api/s/${UNIFI_SITE}/${1}"
    else
        echo "${UNIFI_CONTROLLER_URL}/api/s/${UNIFI_SITE}/${1}"
    fi
}

unifi_login() {
    mkdir -p "$(dirname "$COOKIE_FILE")"
    chmod 700 "$(dirname "$COOKIE_FILE")"

    local login_url header_file http_code
    header_file=$(mktemp /tmp/unifi-hdr-XXXXXX)

    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        login_url="${UNIFI_CONTROLLER_URL}/api/auth/login"
    else
        login_url="${UNIFI_CONTROLLER_URL}/api/login"
    fi

    http_code=$(curl -sk \
        -c "$COOKIE_FILE" \
        -D "$header_file" \
        -o /dev/null \
        -w "%{http_code}" \
        -X POST "$login_url" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}")

    chmod 600 "$COOKIE_FILE"

    if [[ "$http_code" != "200" ]]; then
        log "ERROR: UniFi login failed (HTTP $http_code) at $login_url"
        rm -f "$header_file"
        return 1
    fi

    CSRF_TOKEN=$(grep -i 'x-updated-csrf-token\|x-csrf-token' "$header_file" \
        | tail -1 | awk '{print $2}' | tr -d '\r\n' || true)
    rm -f "$header_file"
    log "INFO: UniFi login OK (type=$UNIFI_TYPE)"
}

# Authenticated GET — auto-reauth on 401, retries once
api_get() {
    local url="$1"
    local args=(-sk -b "$COOKIE_FILE" -w "\n__CODE__:%{http_code}")
    [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")

    local raw code body
    raw=$(curl "${args[@]}" "$url")
    code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2)
    body=$(echo "$raw" | grep -v '__CODE__:')

    if [[ "$code" == "401" ]]; then
        log "INFO: Session expired, re-authenticating..."
        unifi_login || return 1
        args=(-sk -b "$COOKIE_FILE" -w "\n__CODE__:%{http_code}")
        [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
        raw=$(curl "${args[@]}" "$url")
        code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2)
        body=$(echo "$raw" | grep -v '__CODE__:')
    fi

    [[ "$code" != "200" ]] && log "WARNING: API GET $url → HTTP $code"
    echo "$body"
}

# ─── Voucher cache (fetched once per run) ─────────────────────────────────────
load_all_vouchers() {
    local url rc count
    url=$(api_path "stat/voucher")
    VOUCHER_CACHE=$(api_get "$url")
    rc=$(echo "$VOUCHER_CACHE" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    if [[ "$rc" != "ok" ]]; then
        log "WARNING: Could not load vouchers (rc=$rc)"
        VOUCHER_CACHE=""
        return
    fi
    count=$(echo "$VOUCHER_CACHE" | jq '.data | length' 2>/dev/null || echo 0)
    log "INFO: Loaded $count vouchers"
}

# Returns epoch end_time for a MAC, or empty if no valid voucher found.
# Strategy 1: match by voucher_code from session data
# Strategy 2: match by MAC in used_by_sta[]
get_voucher_end_for_mac() {
    local mac="$1" voucher_code="${2:-}" result=""
    [[ -z "$VOUCHER_CACHE" ]] && return 0

    if [[ -n "$voucher_code" && "$voucher_code" != "null" ]]; then
        result=$(echo "$VOUCHER_CACHE" | jq -r \
            --arg code "$voucher_code" '
            .data[]
            | select(.code == $code)
            | select(.status == "VALID_ONE" or .status == "VALID_MULTI")
            | (.create_time + ((.duration // 0) * 60)) | tostring
        ' 2>/dev/null | sort -n | tail -1 || true)
    fi

    if [[ -z "$result" ]]; then
        result=$(echo "$VOUCHER_CACHE" | jq -r \
            --arg mac "$mac" '
            .data[]
            | select(.status == "VALID_ONE" or .status == "VALID_MULTI")
            | select(.used > 0)
            | select(
                (.used_by_sta // []) | map(ascii_downcase) | contains([$mac | ascii_downcase])
              )
            | (.create_time + ((.duration // 0) * 60)) | tostring
        ' 2>/dev/null | sort -n | tail -1 || true)
    fi

    echo "$result"
}

# ─── IP / hostname assignment ─────────────────────────────────────────────────
# Returns the next sequential guest number not already used in either file
get_next_guest_number() {
    local used n=1
    used=$(grep -oh 'guest[0-9]*' "$MAC_LIST" "$PENDING_LIST" 2>/dev/null \
        | sed 's/guest//' | sort -n | uniq)
    while echo "$used" | grep -q "^${n}$"; do (( n++ )); done
    echo "$n"
}

# Returns "IP;HOSTNAME" — IP chosen randomly from available range
assign_ip_and_hostname() {
    local available=()
    for (( i=HOTSPOT_RANGE_START; i<=HOTSPOT_RANGE_END; i++ )); do
        local candidate="${HOTSPOT_IP_RANGE}.${i}"
        grep -q ";${candidate};" "$MAC_LIST"     2>/dev/null && continue
        grep -q ";${candidate};" "$PENDING_LIST" 2>/dev/null && continue
        available+=("$candidate")
    done

    if [[ ${#available[@]} -eq 0 ]]; then
        log "ERROR: Hotspot IP range exhausted (${HOTSPOT_IP_RANGE}.${HOTSPOT_RANGE_START}-${HOTSPOT_RANGE_END})"
        echo ";"
        return 1
    fi

    local idx=$(( RANDOM % ${#available[@]} ))
    local guest_num
    guest_num=$(get_next_guest_number)
    echo "${available[$idx]};guest${guest_num}"
}

# ─── dhcpd.leases cleanup ─────────────────────────────────────────────────────
# Removes ALL lease blocks matching the given MAC from dhcpd.leases.
# Searches by MAC (not IP) so it works even when UniFi reports no IP for the client.
remove_from_leases() {
    local mac="$1"
    local dhcpd_leases="/var/lib/dhcp/dhcpd.leases"
    [[ ! -f "$dhcpd_leases" ]] && return 0

    local tmp in_block=0 block="" removed=0
    tmp=$(mktemp)
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^lease [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ \{"; then
            in_block=1; block="$line"; continue
        fi
        if [[ $in_block -eq 1 ]]; then
            block+=$'\n'"$line"
            if echo "$line" | grep -qE "^\}"; then
                in_block=0
                if echo "$block" | grep -qi "hardware ethernet ${mac};"; then
                    (( removed++ )) || true
                else
                    echo "$block" >> "$tmp"
                fi
                block=""
            fi
            continue
        fi
        echo "$line" >> "$tmp"
    done < "$dhcpd_leases"
    mv "$tmp" "$dhcpd_leases"

    if [[ $removed -gt 0 ]]; then
        log "INFO: Removed $removed lease(s) for $mac from dhcpd.leases"
    else
        log "INFO: No lease found in dhcpd.leases for $mac"
    fi
}

# ─── MAC list deduplication ───────────────────────────────────────────────────
# Rule: if a MAC is in guest-pending.txt or in any mac-*.txt,
# it must NOT appear in blockdhcp.txt or in dhcpd.leases.
# Runs at the start of every run to guarantee consistency.
dedup_mac_lists() {
    local acl_dir
    acl_dir="$(dirname "$MAC_LIST")"

    # Collect all managed MACs (guest-pending + mac-*.txt)
    local managed_macs
    managed_macs=$(
        {
            grep -ih '^a;' "$PENDING_LIST" 2>/dev/null
            grep -rih '^a;' "$acl_dir"/mac-*.txt 2>/dev/null
        } | awk -F';' '{print tolower($2)}' | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' | sort -u
    )

    [[ -z "$managed_macs" ]] && return 0

    local removed_block=0 removed_leases=0

    # 1. Clean blockdhcp.txt
    if [[ -f "$BLOCK_DHCP" ]]; then
        local tmp_block
        tmp_block=$(mktemp)
        while IFS= read -r line; do
            local bmac
            bmac=$(echo "$line" | awk -F';' '{print tolower($2)}')
            if echo "$managed_macs" | grep -q "^${bmac}$"; then
                log "INFO: dedup → removed $bmac from blockdhcp.txt"
                (( removed_block++ )) || true
            else
                echo "$line" >> "$tmp_block"
            fi
        done < "$BLOCK_DHCP"
        mv "$tmp_block" "$BLOCK_DHCP" && chmod 644 "$BLOCK_DHCP"
    fi

    # 2. Clean dhcpd.leases
    local dhcpd_leases="/var/lib/dhcp/dhcpd.leases"
    if [[ -f "$dhcpd_leases" ]]; then
        local tmp_leases in_block=0 block=""
        tmp_leases=$(mktemp)
        while IFS= read -r line; do
            if echo "$line" | grep -qE "^lease [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ \{"; then
                in_block=1; block="$line"; continue
            fi
            if [[ $in_block -eq 1 ]]; then
                block+=$'\n'"$line"
                if echo "$line" | grep -qE "^\}"; then
                    in_block=0
                    local lmac
                    lmac=$(echo "$block" | grep -i 'hardware ethernet' \
                        | sed -E 's/.*hardware ethernet ([0-9a-f:]+);.*/\1/I' \
                        | tr '[:upper:]' '[:lower:]')
                    if [[ -n "$lmac" ]] && echo "$managed_macs" | grep -q "^${lmac}$"; then
                        log "INFO: dedup → removed lease for $lmac from dhcpd.leases"
                        (( removed_leases++ )) || true
                    else
                        echo "$block" >> "$tmp_leases"
                    fi
                    block=""
                fi
                continue
            fi
            echo "$line" >> "$tmp_leases"
        done < "$dhcpd_leases"
        mv "$tmp_leases" "$dhcpd_leases"
    fi

    log "INFO: dedup complete — blockdhcp=$removed_block leases=$removed_leases"
}

# ─── ACL helpers ──────────────────────────────────────────────────────────────
add_mac_to_acl() {
    local mac="$1" ip="$2" hostname="$3" end_time="$4"
    local new_line="a;${mac};${ip};${hostname};${end_time};"

    # If it was in pending, moving it means the fixed IP changed → leases.sh must re-scan
    if grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null; then
        sed -i "/^a;${mac};/Id" "$PENDING_LIST"
        LEASES_CHANGED=1
    fi

    if grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
        local existing_end
        existing_end=$(grep -i "^a;${mac};" "$MAC_LIST" | awk -F';' '{print $5}')
        if [[ "$end_time" != "$existing_end" ]]; then
            sed -i "s|^a;${mac};.*|${new_line}|I" "$MAC_LIST"
            log "INFO: Updated end_time for $mac ($existing_end → $end_time)"
        fi
    else
        echo "$new_line" >> "$MAC_LIST"
        LEASES_CHANGED=1
        log "INFO: Authorized $mac ip=$ip hostname=$hostname expires=$(date -d "@$end_time" 2>/dev/null || echo "$end_time")"
    fi
}

expire_to_pending() {
    local mac="$1"
    grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null && return 0

    local entry ip hostname
    entry=$(grep -i "^a;${mac};" "$MAC_LIST" 2>/dev/null | head -1 || true)
    ip=$(echo "$entry"       | awk -F';' '{print $3}')
    hostname=$(echo "$entry" | awk -F';' '{print $4}')

    if [[ -z "$ip" || -z "$hostname" ]]; then
        local iph
        iph=$(assign_ip_and_hostname) || return 0
        ip=$(echo "$iph"       | cut -d';' -f1)
        hostname=$(echo "$iph" | cut -d';' -f2)
    fi

    echo "a;${mac};${ip};${hostname};" >> "$PENDING_LIST"
    LEASES_CHANGED=1
    log "INFO: Expired $mac → guest-pending.txt ip=$ip hostname=$hostname"
}

# ─── Step 1: remove expired MACs from mac-hotspot.txt ────────────────────────
clean_expired_macs() {
    local now tmp
    now=$(date +%s)
    tmp=$(mktemp)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if echo "$line" | grep -q "guest-placeholder"; then
            echo "$line" >> "$tmp"; continue
        fi
        local end_time mac
        end_time=$(echo "$line" | awk -F';' '{print $5}')
        mac=$(echo "$line"      | awk -F';' '{print $2}')
        if [[ -z "$end_time" ]] || (( now <= end_time )); then
            echo "$line" >> "$tmp"
        else
            log "INFO: Expired $mac at $(date -d "@$end_time" 2>/dev/null || echo "$end_time")"
            expire_to_pending "$mac"
        fi
    done < "$MAC_LIST"

    mv "$tmp" "$MAC_LIST" && chmod 644 "$MAC_LIST"

    if [[ ! -s "$MAC_LIST" ]]; then
        echo "a;02:00:00:00:00:00;0.0.0.0;guest-placeholder" >> "$MAC_LIST"
    fi
}

# ─── Step 2: detect new portal clients (stat/sta) ─────────────────────────────
process_pending_guests() {
    local endpoint guests_data rc
    endpoint=$(api_path "stat/sta")
    guests_data=$(api_get "$endpoint")
    rc=$(echo "$guests_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/sta unavailable (rc=$rc) — skipping"
        return
    fi

    local count=0
    while IFS=$'\t' read -r mac ip hostname; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue

        grep -qi "^a;${mac};" "$MAC_LIST"     2>/dev/null && continue
        grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null && continue

        local assigned_ip assigned_hostname
        # If the IP is invalid (contains letters or is empty), assign a new one
        if [[ -z "$ip" || "$ip" == "PCRINVITADOS" || "$ip" =~ [a-zA-Z] ]]; then
            local iph
            iph=$(assign_ip_and_hostname) || continue
            assigned_ip=$(echo "$iph" | cut -d';' -f1)
            assigned_hostname=$(echo "$iph" | cut -d';' -f2)
        else
            assigned_ip="$ip"
            assigned_hostname="guest$(get_next_guest_number)"
        fi

        echo "a;${mac};${assigned_ip};${assigned_hostname};" >> "$PENDING_LIST"
        log "INFO: Pending guest $mac → ip=$assigned_ip hostname=$assigned_hostname"

        remove_from_leases "$mac"
        (( count++ )) || true

    done < <(echo "$guests_data" | jq -r \
        --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.mac != null and .mac != "")
        | select((.is_guest // false) == true)
        | select((.authorized // false) == false)
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (.ip // ""), (.hostname // .essid // "unknown")]
        | join("\t")
    ' 2>/dev/null || true)

    log "INFO: process_pending_guests: $count new"
}

# ─── Step 3: detect voucher-authenticated clients (stat/guest) ────────────────
process_sessions() {
    local endpoint sessions_data rc added=0
    endpoint=$(api_path "stat/guest")
    sessions_data=$(api_get "$endpoint")
    rc=$(echo "$sessions_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/guest unavailable (rc=$rc) — skipping sessions"
        return
    fi

    while IFS=$'\t' read -r mac end_time; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        [[ -z "$end_time" || "$end_time" == "null" ]] && continue

        grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null && continue

        local assigned_ip="" assigned_hostname="" entry=""
        entry=$(grep -i "^a;${mac};" "$PENDING_LIST" 2>/dev/null | head -1 || true)
        assigned_hostname=$(echo "$entry" | awk -F';' '{print $4}')

        local iph
        iph=$(assign_ip_and_hostname) || continue
        assigned_ip=$(echo "$iph" | cut -d';' -f1)
        [[ -z "$assigned_hostname" ]] && assigned_hostname=$(echo "$iph" | cut -d';' -f2)

        add_mac_to_acl "$mac" "$assigned_ip" "$assigned_hostname" "$end_time"
        (( added++ )) || true

    done < <(echo "$sessions_data" | jq -r '
        .data[]
        | select(.mac != null and .mac != "")
        | select((.expired // false) == false)
        | select(.end != null)
        | [(.mac | ascii_downcase), (.end | tostring)]
        | join("\t")
    ' 2>/dev/null || true)

    log "INFO: process_sessions: $added authorized"
}

revoke_unauthorized() {
    local endpoint sta_data rc
    endpoint=$(api_path "stat/sta")
    sta_data=$(api_get "$endpoint") || true
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/sta unavailable (rc=$rc) — skipping revoke"
        return
    fi

    # Read MAC_LIST into memory to avoid modifying the file while reading it
    local revoked=0
    local macs_to_revoke=()
    while IFS=';' read -r status mac ip hostname end_time; do
        [[ "$status" != "a" ]] && continue
        [[ "$mac" == "02:00:00:00:00:00" ]] && continue
        [[ -z "$mac" ]] && continue

        local authorized
        authorized=$(echo "$sta_data" | jq -r \
            --arg mac "$mac" '
            .data[]
            | select((.mac | ascii_downcase) == $mac)
            | .authorized // "absent"
        ' 2>/dev/null | tail -1 || true)

        if [[ "$authorized" == "false" ]]; then
            macs_to_revoke+=("$mac")
        fi
    done < "$MAC_LIST"

    for mac in "${macs_to_revoke[@]:-}"; do
        [[ -z "$mac" ]] && continue
        log "INFO: Revoking $mac — authorized=false in UniFi"
        expire_to_pending "$mac"
        sed -i "/^a;${mac};/Id" "$MAC_LIST" 2>/dev/null || true
        (( revoked++ )) || true
    done

    [[ $revoked -gt 0 ]] && log "INFO: revoke_unauthorized: $revoked revoked" || true
}

unauthorize_pending() {
    local endpoint sta_data rc
    endpoint=$(api_path "stat/sta")
    sta_data=$(api_get "$endpoint") || true
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    [[ "$rc" != "ok" ]] && return

    while IFS=';' read -r status mac ip hostname; do
        [[ "$status" != "a" ]] && continue
        [[ "$mac" == "02:00:00:00:00:00" ]] && continue
        [[ -z "$mac" ]] && continue

        local authorized
        authorized=$(echo "$sta_data" | jq -r \
            --arg mac "$mac" '
            .data[]
            | select((.mac | ascii_downcase) == $mac)
            | .authorized // false
        ' 2>/dev/null | tail -1 || true)

        [[ "$authorized" != "true" ]] && continue

        local unauth_url
        unauth_url=$(api_path "cmd/stamgr")
        curl -sk -b "$COOKIE_FILE" \
            ${CSRF_TOKEN:+-H "x-csrf-token: $CSRF_TOKEN"} \
            -X POST "$unauth_url" \
            -H "Content-Type: application/json" \
            -d "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}" > /dev/null || true
        log "INFO: Unauthorized $mac in UniFi"

    done < "$PENDING_LIST"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    load_config
    log "INFO: --- run start ---"
    init_acl_files
    unifi_login || exit 1
    load_all_vouchers
    dedup_mac_lists
    clean_expired_macs
    process_pending_guests
    process_sessions
    revoke_unauthorized
    unauthorize_pending

    if [[ $LEASES_CHANGED -eq 1 ]]; then
        if [[ -n "$SERVER_RELOAD_SCRIPT" && -x "$SERVER_RELOAD_SCRIPT" ]]; then
            log "INFO: ACL changed — invoking $SERVER_RELOAD_SCRIPT"
            bash "$SERVER_RELOAD_SCRIPT" >> "$LOG_FILE" 2>&1 || log "WARNING: $SERVER_RELOAD_SCRIPT exited with error"
        else
            log "WARNING: LEASES_CHANGED=1 but SERVER_RELOAD_SCRIPT is not set or not executable"
        fi
    fi

    log "INFO: --- run end ---"
}

main
