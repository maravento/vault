#!/bin/bash
# maravento.com
#
# Unifi Hotspot Client Access via Linux Server with Iptables - v4
#
# DISCLAIMER:
# This script is provided "as is", without warranty of any kind. It interacts
# directly with iptables, rsyslog, and the UniFi Controller API, and depends
# on external components (DHCP, DNS, iptables, curl, jq, flock) being correctly
# installed and configured. Misconfiguration or unexpected behavior in any of
# these components may result in loss of network access or incomplete firewall
# enforcement. All iptables rules are applied in memory only and are not
# persisted across reboots. Test in a non-production environment before
# deploying. Use at your own risk.
#
# DESCRIPTION:
# Manages Unifi Hotspot access on Ubuntu 24.04. Supports both:
#   - UniFi OS  (unifi-core, port 11443, endpoint /api/auth/login)
#   - UniFi Network standalone (port 8443, endpoint /api/login)
#
# Queries the Unifi API for active hotspot sessions, correlates each client MAC
# with its voucher (via used_by_sta[] or voucher_code in session data), calculates
# real expiration from create_time + duration*60, and enforces iptables rules.
#
# Expired clients: all ports blocked except captive portal ports so they can
# re-authenticate without calling support.
#
#
# ACL FORMAT:
# Active clients are stored in MAC_LIST (default: /etc/acl/mac-hotspot.txt).
# Each line follows the format:
#   a;MAC;IP;HOSTNAME;END_TIME_EPOCH
# Example:
#   a;aa:bb:cc:dd:ee:ff;192.168.0.165;guest-eeff;1750000000
# If UniFi cannot resolve the hostname, it is automatically set to
# guest-XXXX where XXXX are the last 4 characters of the MAC address.
# Blacklisted MACs are stored in MAC_BLACKLIST (default: /etc/acl/bl-hotspot.txt),
# one MAC address per line.
#
# DHCP CONFIGURATION (isc-dhcp-server):
# The hotspot IP range defined by HOTSPOT_IP_RANGE, HOTSPOT_RANGE_START, and
# HOTSPOT_RANGE_END must match a pool in your /etc/dhcp/dhcpd.conf. Example
# for the default range (192.168.0.160 - 192.168.0.200):
#
#   subnet 192.168.0.0 netmask 255.255.255.0 {
#       option routers 192.168.0.1;
#       option domain-name-servers 8.8.8.8, 8.8.4.4;
#       pool {
#           range 192.168.0.160 192.168.0.200;
#           default-lease-time 3600;
#           max-lease-time 7200;
#       }
#   }
#
# After editing dhcpd.conf, restart the service:
#   sudo systemctl restart isc-dhcp-server
#
# REQUIREMENTS:
# This script is designed exclusively for the following stack:
#   - DHCP server: isc-dhcp-server (dhcpd). NOT compatible with dnsmasq or
#     any other DHCP implementation. Guest pending management depends on
#     /var/lib/dhcp/dhcpd.leases file format.
#   - Firewall: iptables + ipset. NOT compatible with nftables or ufw.
#   - OS: Ubuntu 24.04 or compatible Debian-based system.
#
# This script assumes the following are already configured and active before
# running start or reload:
#   - ip_forward enabled:       sysctl -w net.ipv4.ip_forward=1
#   - NAT/MASQUERADE active:    iptables -t nat -A POSTROUTING -s <LAN> -o <WAN> -j MASQUERADE
#   - ESTABLISHED/RELATED:      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
#                               iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
#                               iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
#
# If you run a script that flushes iptables (iptables -F / iptables -X),
# all hotspot rules will be wiped. Run reload afterwards to restore them.
# Recommended order: (1) your network/iptables script, (2) hotspot reload.
#
# CRON USAGE:
# The recommended way to run this script is via cron using the reload action,
# which syncs vouchers, cleans expired clients and refreshes iptables rules.
# start and stop are intended for manual use and testing only.
# reload builds all rules from scratch on first run, then syncs on every
# subsequent execution. No need to run start before adding it to cron.
# Example (every 5 minutes):
#   */5 * * * * /path/to/unifihotspot.sh reload
#
# UNIFI SITE ID:
# The script uses "default" as the UniFi site ID, which is the standard value
# for single-site installations. The site ID appears in the captive portal URL:
#   https://SERVER_IP:8843/guest/s/default/  (HTTPS portal, SSL enabled)
#   http://SERVER_IP:8880/guest/s/default/   (HTTP portal, SSL disabled)
# Both ports (8880 and 8843) are always open in PORTAL_PORTS to cover either
# configuration. The active one depends on how the portal is configured in
# the UniFi controller (Guest Portal > SSL certificate settings).
# Both UniFi Network and UniFi OS use the same portal ports.
# The site ID is also used in all API calls:
#   /api/s/default/stat/voucher
# If the site ID was changed in the UniFi controller, update UNIFI_SITE in
# /etc/unifihotspot/config.conf accordingly. To find the correct site ID,
# check the captive portal URL or the browser URL when navigating the
# UniFi controller dashboard.
# NOTE: pending verification during testing.
#
# OPERATION FLOW:
# On every reload (cron):
#   1. Login to UniFi API and load all vouchers into memory
#   2. clean_expired_macs: remove expired clients from mac-hotspot.txt
#      and move them to guest-pending.txt (no access, not blacklisted)
#   3. process_pending_guests: query stat/guest (clients on portal without
#      voucher), remove them from dhcpd.leases, add to guest-pending.txt
#   4. process_sessions: query stat/session (clients with valid voucher),
#      move from guest-pending.txt to mac-hotspot.txt, apply access rules
#   5. apply_iptables_rules: update ipset machotspot with authorized MACs
#
# Client lifecycle:
#   New client connects to AP
#     → gets IP from DHCP hotspot pool
#     → enters dhcpd.leases
#     → unifihotspot detects via stat/guest
#     → moved to guest-pending.txt (safe from leases.sh blacklist)
#   Client enters voucher
#     → UniFi registers in stat/session
#     → moved from guest-pending.txt to mac-hotspot.txt
#     → ipset rule applied → internet access granted
#   Voucher expires
#     → removed from mac-hotspot.txt
#     → moved back to guest-pending.txt
#     → ipset rule removed → internet access revoked
#     → client can re-authenticate via captive portal (portal ports always open)
#   Client re-authenticates with new voucher
#     → already in guest-pending.txt (no dhcpd.leases interaction needed)
#     → moved directly to mac-hotspot.txt on next reload
# USAGE:
# ./unifihotspot.sh [config|start|stop|status|reload]

set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Defaults ─────────────────────────────────────────────────────────────────
CONFIG_FILE="/etc/unifihotspot/config.conf"
COOKIE_FILE="/etc/unifihotspot/unifi-session.cookie"
LOCK_FILE="/var/lock/unifihotspot.lock"
MAC_LIST="/etc/acl/mac-hotspot.txt"
MAC_BLACKLIST="/etc/acl/bl-hotspot.txt"
PENDING_LIST="/etc/acl/guest-pending.txt"
LOG_FILE="/var/log/hotspot.log"

WAN_IF=""
LAN_IF=""
SERVER_IP=""
LOCAL_USER=""
HOTSPOT_IP_RANGE="192.168.0"
HOTSPOT_RANGE_START=160
HOTSPOT_RANGE_END=200

# Always open: captive portal re-auth (DNS, DHCP, portal HTTP/HTTPS)
PORTAL_PORTS="53,67,68,8880,8881,8882,8843"
# Open only for clients with a valid voucher
LOCAL_PORTS="137:139,445,162,631,8000,3128,853"

UNIFI_CONTROLLER_URL=""
UNIFI_USERNAME=""
UNIFI_PASSWORD=""
UNIFI_SITE="default"
UNIFI_TYPE=""      # "unifi-os" or "classic"
CSRF_TOKEN=""

# Populated once per run by load_all_vouchers()
VOUCHER_CACHE=""

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# ─── Config ───────────────────────────────────────────────────────────────────
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
    fi
}

save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << EOF
WAN_IF="$WAN_IF"
LAN_IF="$LAN_IF"
SERVER_IP="$SERVER_IP"
LOCAL_USER="$LOCAL_USER"
HOTSPOT_IP_RANGE="$HOTSPOT_IP_RANGE"
HOTSPOT_RANGE_START=$HOTSPOT_RANGE_START
HOTSPOT_RANGE_END=$HOTSPOT_RANGE_END
PORTAL_PORTS="$PORTAL_PORTS"
LOCAL_PORTS="$LOCAL_PORTS"
UNIFI_CONTROLLER_URL="$UNIFI_CONTROLLER_URL"
UNIFI_USERNAME="$UNIFI_USERNAME"
UNIFI_PASSWORD="$UNIFI_PASSWORD"
UNIFI_SITE="$UNIFI_SITE"
UNIFI_TYPE="$UNIFI_TYPE"
EOF
    chmod 600 "$CONFIG_FILE"
    chown root:root "$CONFIG_FILE"
}

# ─── Guards ───────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}ERROR: This script must be run as root${NC}"
        exit 1
    fi
}

check_dependencies() {
    local deps=("iptables" "ipset" "systemctl" "awk" "grep" "sed" "curl" "jq" "ss" "flock")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            echo -e "${RED}ERROR: $dep is required but not installed${NC}"
            exit 1
        fi
    done
}

# ─── Local user detection ─────────────────────────────────────────────────────
detect_local_user() {
    LOCAL_USER=$(who | grep -m1 '(:0)' | awk '{print $1}' 2>/dev/null || true)
    if [[ -z "$LOCAL_USER" ]]; then
        LOCAL_USER=$(who | head -1 | awk '{print $1}' 2>/dev/null || true)
    fi
    if [[ -z "$LOCAL_USER" ]]; then
        LOCAL_USER=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}' 2>/dev/null || true)
    fi
    if [[ -z "$LOCAL_USER" ]]; then
        echo -e "${YELLOW}WARNING: Cannot determine local user.${NC}"
        LOCAL_USER="nobody"
    else
        echo "Detected local user: $LOCAL_USER"
    fi
}

# ─── Interface detection ──────────────────────────────────────────────────────
detect_interfaces() {
    echo "Detecting network interfaces..."
    WAN_IF=$(ip route | grep default | awk '{print $5}' | head -1)
    [[ -z "$WAN_IF" ]] && { echo -e "${RED}ERROR: Could not detect WAN interface${NC}"; exit 1; }

    LAN_IF=$(ip -o link | awk -v wan="$WAN_IF:" '$2 != "lo:" && $2 != wan {print $2}' \
        | sed 's/:$//' | head -1)
    [[ -z "$LAN_IF" ]] && { echo -e "${RED}ERROR: Could not detect LAN interface${NC}"; exit 1; }

    echo "Detected WAN: $WAN_IF, LAN: $LAN_IF"
}

get_server_ip() {
    SERVER_IP=$(ip addr show "$LAN_IF" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    [[ -z "$SERVER_IP" ]] && { echo -e "${RED}ERROR: Could not get server IP on $LAN_IF${NC}"; exit 1; }
    echo "Server IP: $SERVER_IP"
}

# ─── UniFi type detection ─────────────────────────────────────────────────────
# Priority: UniFi OS (11443) > classic Network (8443).
# Both ports can coexist; UniFi OS always takes precedence.
detect_unifi_type() {
    local base_ip="${1:-127.0.0.1}"
    echo "Detecting UniFi controller type on $base_ip..."

    if ss -tlnp | grep -q ':11443 '; then
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "https://${base_ip}:11443/api/auth/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"x","password":"x"}' 2>/dev/null || echo "000")
        if [[ "$code" == "200" || "$code" == "401" || "$code" == "403" ]]; then
            UNIFI_TYPE="unifi-os"
            UNIFI_CONTROLLER_URL="https://${base_ip}:11443"
            echo -e "${GREEN}Detected: UniFi OS at $UNIFI_CONTROLLER_URL${NC}"
            return 0
        fi
    fi

    if ss -tlnp | grep -q ':8443 '; then
        local code
        code=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "https://${base_ip}:8443/api/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"x","password":"x"}' 2>/dev/null || echo "000")
        if [[ "$code" == "200" || "$code" == "401" || "$code" == "400" ]]; then
            UNIFI_TYPE="classic"
            UNIFI_CONTROLLER_URL="https://${base_ip}:8443"
            echo -e "${GREEN}Detected: UniFi Network classic at $UNIFI_CONTROLLER_URL${NC}"
            return 0
        fi
    fi

    echo -e "${RED}ERROR: Could not detect UniFi controller on ports 11443 or 8443${NC}"
    return 1
}

# ─── API path builder ─────────────────────────────────────────────────────────
api_path() {
    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        echo "${UNIFI_CONTROLLER_URL}/proxy/network/api/s/${UNIFI_SITE}/${1}"
    else
        echo "${UNIFI_CONTROLLER_URL}/api/s/${UNIFI_SITE}/${1}"
    fi
}

# ─── Authentication ───────────────────────────────────────────────────────────
# Uses mktemp for header file — safe against concurrent runs.
# Saves cookie + CSRF token for subsequent calls.
# IMPORTANT: The UniFi account must NOT have 2FA enabled. Use a dedicated
# local read-only account created exclusively for this script.
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
        echo -e "${RED}ERROR: UniFi login failed (HTTP $http_code)${NC}"
        log "ERROR: UniFi login failed HTTP $http_code at $login_url"
        rm -f "$header_file"
        return 1
    fi

    # Extract CSRF token from response headers (UniFi OS only)
    CSRF_TOKEN=$(grep -i 'x-updated-csrf-token\|x-csrf-token' "$header_file" \
        | tail -1 | awk '{print $2}' | tr -d '\r\n' || true)

    rm -f "$header_file"

    echo -e "${GREEN}UniFi login successful (type: $UNIFI_TYPE)${NC}"
    log "INFO: UniFi login OK type=$UNIFI_TYPE"
}

# ─── Authenticated GET with auto-reauth on 401 ────────────────────────────────
# Returns the response body. Detects 401 → re-logins → retries once.
api_get() {
    local url="$1"
    local args=(-sk -b "$COOKIE_FILE" -w "\n__CODE__:%{http_code}")
    [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")

    local raw code body
    raw=$(curl "${args[@]}" "$url")
    code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2)
    body=$(echo "$raw" | grep -v '__CODE__:')

    if [[ "$code" == "401" ]]; then
        log "INFO: Session expired (401 on $url), re-authenticating..."
        echo -e "${YELLOW}Session expired, re-authenticating...${NC}"
        unifi_login || return 1

        # Retry once with fresh cookie
        args=(-sk -b "$COOKIE_FILE" -w "\n__CODE__:%{http_code}")
        [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
        raw=$(curl "${args[@]}" "$url")
        code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2)
        body=$(echo "$raw" | grep -v '__CODE__:')
    fi

    if [[ "$code" != "200" ]]; then
        log "WARNING: API GET $url returned HTTP $code"
    fi

    echo "$body"
}

# ─── Voucher cache ────────────────────────────────────────────────────────────
# Fetches ALL vouchers ONCE per run and stores in VOUCHER_CACHE.
# All per-MAC lookups use this cache to avoid N API calls.
load_all_vouchers() {
    local url
    url=$(api_path "stat/voucher")
    VOUCHER_CACHE=$(api_get "$url")

    local rc
    rc=$(echo "$VOUCHER_CACHE" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    if [[ "$rc" != "ok" ]]; then
        echo -e "${YELLOW}WARNING: Could not load voucher list (rc=$rc)${NC}"
        log "WARNING: Failed to load vouchers from $url"
        VOUCHER_CACHE=""
    else
        local count
        count=$(echo "$VOUCHER_CACHE" | jq '.data | length' 2>/dev/null || echo 0)
        echo "Loaded $count vouchers from API"
    fi
}

# Looks up expiration for a given MAC using the in-memory VOUCHER_CACHE.
# Strategy:
#   1. Try voucher_code from session data (most reliable when available)
#   2. Try used_by_sta[] (array of MACs that used this voucher)
# Returns the highest end_time found across all matching vouchers,
# or empty string if no valid voucher found.
# NOTE: Strategy 3 (fallback to any active voucher) has been intentionally
# removed — assigning an unrelated voucher's expiry is a security bypass.
get_voucher_end_for_mac() {
    local mac="$1"
    local voucher_code="${2:-}"   # optional: voucher_code from session data

    [[ -z "$VOUCHER_CACHE" ]] && return 0

    local result=""

    # Strategy 1: match by voucher_code from session (most reliable)
    if [[ -n "$voucher_code" && "$voucher_code" != "null" ]]; then
        result=$(echo "$VOUCHER_CACHE" | jq -r \
            --arg code "$voucher_code" '
            .data[]
            | select(.code == $code)
            | select(.status == "VALID_ONE" or .status == "VALID_MULTI")
            | (.create_time + ((.duration // 0) * 60)) | tostring
        ' 2>/dev/null | sort -n | tail -1 || true)
    fi

    # Strategy 2: match by MAC in used_by_sta[] array
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

# ─── Session processing ───────────────────────────────────────────────────────
# Tries stat/session first; falls back to stat/sta if empty or error.
process_sessions() {
    local sessions_data rc endpoint

    # Primary: stat/session (hotspot guest sessions)
    endpoint=$(api_path "stat/session")
    sessions_data=$(api_get "$endpoint")
    rc=$(echo "$sessions_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    local count_primary
    count_primary=$(echo "$sessions_data" | jq '.data | length' 2>/dev/null || echo 0)

    # Fallback: stat/sta (all associated clients, filter guests)
    if [[ "$rc" != "ok" || "$count_primary" -eq 0 ]]; then
        echo -e "${YELLOW}stat/session empty or unavailable, trying stat/sta...${NC}"
        endpoint=$(api_path "stat/sta")
        sessions_data=$(api_get "$endpoint")
        rc=$(echo "$sessions_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    fi

    if [[ "$rc" != "ok" ]]; then
        echo -e "${YELLOW}WARNING: Could not retrieve client sessions (rc=$rc)${NC}"
        log "WARNING: Failed to retrieve sessions"
        return
    fi

    local added=0
    while IFS=$'\t' read -r mac hostname ip voucher_code; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        [[ "$ip" == "null" ]] && ip=""
        if [[ -z "$hostname" || "$hostname" == "null" || "$hostname" == "unknown" ]]; then
            local mac_suffix
            mac_suffix=$(echo "$mac" | tr -d ':' | tail -c 4)
            hostname="guest-${mac_suffix}"
        fi

        # Skip blacklisted MACs
        grep -qi "^${mac}$" "$MAC_BLACKLIST" 2>/dev/null && continue

        local end_time
        end_time=$(get_voucher_end_for_mac "$mac" "$voucher_code")

        if [[ -z "$end_time" ]]; then
            echo "No valid voucher found for MAC $mac — skipping"
            log "INFO: Skipped MAC $mac — no voucher match"
            continue
        fi

        add_mac_to_acl "$mac" "$ip" "$hostname" "$end_time"
        echo "Client: $mac ip=${ip:-?} expires=$(date -d "@$end_time" 2>/dev/null || echo "$end_time")"
        log "INFO: Added/updated MAC $mac ip=$ip expires=$end_time"
        (( added++ )) || true

    done < <(echo "$sessions_data" | jq -r '
        .data[]
        | select((.is_guest // false) == true)
        | select(.mac != null and .mac != "")
        | [
            (.mac // ""),
            (.hostname // "unknown"),
            (.ip // ""),
            (.voucher_code // "")
          ]
        | join("\t")
    ' 2>/dev/null || true)

    echo "Added/updated $added client(s) in ACL"
}

# ─── Guest pending management ─────────────────────────────────────────────────
# Removes a MAC block from dhcpd.leases and stores it in guest-pending.txt
# so leases.sh never sees it as an unknown client.
remove_from_leases() {
    local mac="$1" ip="$2" hostname="$3"
    local dhcpd_leases="/var/lib/dhcp/dhcpd.leases"
    local tmp_file
    tmp_file=$(mktemp)

    local in_block=0 skip_block=0 block=""
    while IFS= read -r line; do
        if echo "$line" | grep -qE "^lease $ip \{"; then
            in_block=1
            skip_block=1
            block="$line"
            continue
        fi
        if [[ $in_block -eq 1 ]]; then
            block+=$'\n'"$line"
            if echo "$line" | grep -qE "^\}"; then
                in_block=0
                # Only skip if MAC matches
                if echo "$block" | grep -qi "hardware ethernet $mac;"; then
                    log "INFO: Removed MAC $mac from dhcpd.leases"
                else
                    echo "$block" >> "$tmp_file"
                fi
                block=""
                skip_block=0
            fi
            continue
        fi
        echo "$line" >> "$tmp_file"
    done < "$dhcpd_leases"

    mv "$tmp_file" "$dhcpd_leases"

    # Add to guest-pending.txt if not already there
    if ! grep -qi "^$mac$" "$PENDING_LIST" 2>/dev/null; then
        echo "$mac" >> "$PENDING_LIST"
        log "INFO: Added MAC $mac to guest-pending.txt"
    fi
}

# Queries stat/guest for clients connected to portal but without voucher.
# Moves them out of dhcpd.leases into guest-pending.txt.
process_pending_guests() {
    local endpoint guests_data rc

    endpoint=$(api_path "stat/guest")
    guests_data=$(api_get "$endpoint")
    rc=$(echo "$guests_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/guest unavailable (rc=$rc) — skipping pending guests"
        return
    fi

    local count=0
    while IFS=$'\t' read -r mac ip hostname; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        [[ "$ip" == "null" ]] && ip=""

        # Skip if already in mac-hotspot.txt (already authorized)
        grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null && continue

        # Skip blacklisted MACs
        grep -qi "^${mac}$" "$MAC_BLACKLIST" 2>/dev/null && continue

        # Skip if already in guest-pending.txt
        grep -qi "^${mac}$" "$PENDING_LIST" 2>/dev/null && continue

        remove_from_leases "$mac" "$ip" "$hostname"
        echo "Pending guest: $mac ip=${ip:-?} hostname=${hostname:-?}"
        (( count++ )) || true

    done < <(echo "$guests_data" | jq -r '
        .data[]
        | select(.mac != null and .mac != "")
        | select((.authorized // false) == false)
        | [
            (.mac // ""),
            (.ip // ""),
            (.hostname // "unknown")
          ]
        | join("\t")
    ' 2>/dev/null || true)

    echo "Processed $count pending guest(s)"
}

# When a voucher expires, moves MAC from mac-hotspot.txt back to guest-pending.txt
expire_to_pending() {
    local mac="$1"
    if ! grep -qi "^${mac}$" "$PENDING_LIST" 2>/dev/null; then
        echo "$mac" >> "$PENDING_LIST"
        log "INFO: Expired MAC $mac moved to guest-pending.txt"
    fi
}
setup_acl() {
    mkdir -p "$(dirname "$MAC_LIST")" "$(dirname "$MAC_BLACKLIST")" "$(dirname "$LOG_FILE")"
    touch "$MAC_LIST" "$MAC_BLACKLIST" "$PENDING_LIST" "$LOG_FILE"
    chmod 640 "$MAC_LIST" "$MAC_BLACKLIST" "$PENDING_LIST"
    chmod 644 "$LOG_FILE"

    # Inject placeholder if list is empty — an empty list causes conflicts
    # in leases.sh and iptables.sh. Format matches other ACL lists.
    if [[ ! -s "$MAC_LIST" ]]; then
        echo "a;02:00:00:00:00:00;0.0.0.0;guest-placeholder" >> "$MAC_LIST"
    fi
}

# Adds MAC to ACL or updates end_time whenever it differs from stored value.
# Format: a;mac;ip;hostname;end_time
add_mac_to_acl() {
    local mac="$1" ip="$2" hostname="$3" end_time="$4"
    local new_line="a;${mac};${ip};${hostname};${end_time}"

    # Remove from guest-pending.txt if present (client now authorized)
    sed -i "/^${mac}$/Id" "$PENDING_LIST" 2>/dev/null || true

    if grep -q "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
        local existing_end
        existing_end=$(grep "^a;${mac};" "$MAC_LIST" | awk -F';' '{print $5}')
        # Update whenever end_time changed (covers both renewals and shorter vouchers)
        if (( end_time != existing_end )); then
            sed -i "s|^a;${mac};.*|${new_line}|" "$MAC_LIST"
            echo "  Updated end_time for $mac ($existing_end → $end_time)"
        fi
    else
        echo "$new_line" >> "$MAC_LIST"
    fi
}

# Removes expired MACs; uses temp file + atomic mv to avoid race conditions.
clean_expired_macs() {
    local current_time
    current_time=$(date +%s)
    local tmp_file
    tmp_file=$(mktemp)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip placeholder — it has no end_time and must never expire
        echo "$line" | grep -q "guest-placeholder" && { echo "$line" >> "$tmp_file"; continue; }
        local end_time mac
        end_time=$(echo "$line" | awk -F';' '{print $5}')
        if (( current_time <= end_time )); then
            echo "$line" >> "$tmp_file"
        else
            mac=$(echo "$line" | awk -F';' '{print $2}')
            echo "Expired: $mac ($(date -d "@$end_time" 2>/dev/null || echo "$end_time"))"
            log "INFO: Removed expired MAC $mac"
            expire_to_pending "$mac"
        fi
    done < "$MAC_LIST"

    mv "$tmp_file" "$MAC_LIST"
    chmod 640 "$MAC_LIST"

    # Restore placeholder if list is now empty
    if [[ ! -s "$MAC_LIST" ]]; then
        echo "a;02:00:00:00:00:00;0.0.0.0;guest-placeholder" >> "$MAC_LIST"
    fi
}

# ─── iptables helpers ─────────────────────────────────────────────────────────
# Checks before inserting — prevents duplicates on re-run.
# Uses -I (insert at position 1) so rules precede any existing DROP rules.
insert_iptables_rule() {
    local table="$1"; shift
    local chain="$1"; shift
    if ! iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
        iptables -t "$table" -I "$chain" 1 "$@"
    fi
}

# Safe MAC rule removal — no eval, uses line-number based deletion.
remove_mac_rules() {
    local mac="$1"
    local line_num
    # Delete from highest line number downward to avoid index shifting
    while true; do
        line_num=$(iptables -L HOTSPOT --line-numbers -n 2>/dev/null \
            | grep -i "$mac" | tail -1 | awk '{print $1}')
        [[ -z "$line_num" ]] && break
        iptables -D HOTSPOT "$line_num" 2>/dev/null || break
    done
}

# ─── Base rules (portal always open) ─────────────────────────────────────────
setup_base_rules() {
    echo "Setting up base portal rules..."

    # Portal ports always open for everyone on LAN (captive portal re-auth)
    for proto in tcp udp; do
        insert_iptables_rule filter INPUT \
            -i "$LAN_IF" -p "$proto" \
            -m multiport --dports "$PORTAL_PORTS" -j ACCEPT
        insert_iptables_rule filter FORWARD \
            -i "$LAN_IF" -p "$proto" \
            -m multiport --dports "$PORTAL_PORTS" -j ACCEPT
    done
    # DNS
    insert_iptables_rule filter INPUT -i "$LAN_IF" -p udp --dport 53 -j ACCEPT
    insert_iptables_rule filter INPUT -i "$LAN_IF" -p tcp --dport 53 -j ACCEPT
    # DHCP
    insert_iptables_rule filter INPUT -i "$LAN_IF" -p udp --dport 67 -j ACCEPT
}

# ─── UniFi controller communication ports ─────────────────────────────────────
setup_unifi_ports() {
    local UNIFI_PORTS="53,3478,5514,8080,8443,8880,8843,8881,8882,6789,27117,10001,1900,123,11443"
    echo "Setting up UniFi controller ports..."
    for proto in tcp udp; do
        insert_iptables_rule filter INPUT \
            -i "$LAN_IF" -d "$SERVER_IP" -p "$proto" \
            -m multiport --dports "$UNIFI_PORTS" -j ACCEPT
        insert_iptables_rule filter OUTPUT \
            -p "$proto" -m multiport --dports "$UNIFI_PORTS" -j ACCEPT
    done
}

# ─── Hotspot logging ──────────────────────────────────────────────────────────
setup_hotspot_logging() {
    for string in "success" "POST"; do
        insert_iptables_rule filter INPUT \
            -i "$LAN_IF" -p tcp --dport 8880 \
            -m string --string "$string" --algo bm \
            -j LOG --log-prefix "HOTSPOT:"
    done
}

# ─── HOTSPOT chain (per-MAC rules for active clients via ipset) ───────────────
apply_iptables_rules() {
    echo "Applying iptables rules for ACL clients..."

    # Remove chain references first, then destroy ipset
    iptables -D INPUT   -j HOTSPOT 2>/dev/null || true
    iptables -D FORWARD -j HOTSPOT 2>/dev/null || true
    iptables -F HOTSPOT 2>/dev/null || true
    iptables -X HOTSPOT 2>/dev/null || true

    # Build/refresh ipset machotspot
    if ! ipset list machotspot &>/dev/null; then
        ipset create machotspot hash:mac -exist
    else
        ipset flush machotspot
    fi
    for mac in $(awk -F';' '$2 != "" && $2 != "02:00:00:00:00:00" {print $2}' "$MAC_LIST"); do
        ipset add machotspot $mac -exist
    done

    iptables -N HOTSPOT

    for proto in tcp udp; do
        # Local services — restricted to server IP only
        iptables -A HOTSPOT \
            -i "$LAN_IF" -p "$proto" -d "$SERVER_IP" \
            -m multiport --dports "$LOCAL_PORTS" \
            -m set --match-set machotspot src -j ACCEPT
        # Internet access via WAN
        iptables -A HOTSPOT \
            -i "$LAN_IF" -o "$WAN_IF" -p "$proto" \
            -m set --match-set machotspot src -j ACCEPT
    done
    # ICMP (ping) for active clients
    iptables -A HOTSPOT \
        -i "$LAN_IF" -p icmp \
        -m set --match-set machotspot src -j ACCEPT

    # Return to calling chain; portal rules in INPUT/FORWARD cover everyone else
    iptables -A HOTSPOT -j RETURN

    # Insert HOTSPOT jump at position 1 so it runs before any DROP rules
    insert_iptables_rule filter INPUT   -j HOTSPOT
    insert_iptables_rule filter FORWARD -j HOTSPOT
}

# ─── rsyslog + logrotate ──────────────────────────────────────────────────────
setup_rsyslog() {
    local RSYSLOG_CONF="/etc/rsyslog.d/hotspot.conf"
    if [[ ! -f "$RSYSLOG_CONF" ]]; then
        printf ':msg, contains, "HOTSPOT:" %s\n& stop\n' "$LOG_FILE" > "$RSYSLOG_CONF"
        chmod 644 "$RSYSLOG_CONF"
        systemctl restart rsyslog
        echo "rsyslog configured"
    fi

    local LOGROTATE_CONF="/etc/logrotate.d/hotspot"
    if [[ ! -f "$LOGROTATE_CONF" ]]; then
        cat > "$LOGROTATE_CONF" << EOF
$LOG_FILE {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF
        chmod 644 "$LOGROTATE_CONF"
        echo "logrotate configured (14 days retention)"
    fi
}

# ─── Interactive config ───────────────────────────────────────────────────────
interactive_config() {
    echo -e "${CYAN}Interactive Configuration — UniFi Hotspot v4${NC}"
    echo "============================================="

    detect_local_user

    # WAN Interface
    while true; do
        read -rp "WAN Interface: " WAN_IF
        if ip link show "$WAN_IF" &>/dev/null; then break
        else echo -e "${RED}Interface $WAN_IF not found. Available: $(ip -o link | awk '{print $2}' | tr -d : | grep -v lo | tr '\n' ' ')${NC}"; fi
    done

    # LAN Interface
    while true; do
        read -rp "LAN Interface: " LAN_IF
        if ip link show "$LAN_IF" &>/dev/null; then break
        else echo -e "${RED}Interface $LAN_IF not found. Available: $(ip -o link | awk '{print $2}' | tr -d : | grep -v lo | tr '\n' ' ')${NC}"; fi
    done

    # Server IP
    local local_ips
    local_ips=$(ip -o addr show | awk '{print $4}' | cut -d/ -f1)
    while true; do
        read -rp "Server IP: " SERVER_IP
        if ! [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo -e "${RED}Invalid IP address.${NC}"
        elif ! echo "$local_ips" | grep -qx "$SERVER_IP"; then
            echo -e "${RED}$SERVER_IP is not assigned to this server. Available IPs: $(echo "$local_ips" | tr '\n' ' ')${NC}"
        else
            break
        fi
    done

    echo "Detecting UniFi controller on $SERVER_IP..."
    if ! detect_unifi_type "$SERVER_IP"; then
        echo -e "${YELLOW}Could not detect UniFi controller on $SERVER_IP.${NC}"
        while true; do
            read -rp "UniFi Controller IP: " controller_ip
            if [[ "$controller_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                detect_unifi_type "$controller_ip" && break
                echo -e "${RED}Could not detect UniFi controller on $controller_ip${NC}"
            else
                echo -e "${RED}Invalid IP address.${NC}"
            fi
        done
    fi

    # Hotspot IP range
    while true; do
        read -rp "Hotspot IP Range (e.g. 192.168.0): " HOTSPOT_IP_RANGE
        if [[ "$HOTSPOT_IP_RANGE" =~ ^([0-9]{1,3}\.){2}[0-9]{1,3}$ ]]; then break
        else echo -e "${RED}Invalid range format. Use three octets, e.g. 192.168.0${NC}"; fi
    done

    # Range Start
    while true; do
        read -rp "Range Start (1-254): " HOTSPOT_RANGE_START
        if [[ "$HOTSPOT_RANGE_START" =~ ^[0-9]+$ ]] && (( HOTSPOT_RANGE_START >= 1 && HOTSPOT_RANGE_START <= 254 )); then break
        else echo -e "${RED}Invalid value. Enter a number between 1 and 254.${NC}"; fi
    done

    # Range End
    while true; do
        read -rp "Range End (1-254): " HOTSPOT_RANGE_END
        if [[ "$HOTSPOT_RANGE_END" =~ ^[0-9]+$ ]] && (( HOTSPOT_RANGE_END >= 1 && HOTSPOT_RANGE_END <= 254 )) && (( HOTSPOT_RANGE_END > HOTSPOT_RANGE_START )); then break
        else echo -e "${RED}Invalid value. Must be a number between 1-254 and greater than Range Start ($HOTSPOT_RANGE_START).${NC}"; fi
    done

    echo ""
    echo -e "${YELLOW}NOTE: The account used here must NOT have 2FA enabled.${NC}"
    echo "      Create a dedicated read-only local account in UniFi for this script."

    # Username
    while true; do
        read -rp "Username: " UNIFI_USERNAME
        if [[ -n "$UNIFI_USERNAME" ]]; then break
        else echo -e "${RED}Username cannot be empty.${NC}"; fi
    done

    # Password
    while true; do
        read -rs -p "Password: " UNIFI_PASSWORD; echo ""
        if [[ -n "$UNIFI_PASSWORD" ]]; then break
        else echo -e "${RED}Password cannot be empty.${NC}"; fi
    done

    save_config
    echo -e "${GREEN}Configuration saved to $CONFIG_FILE${NC}"

    echo "Testing API connection..."
    if unifi_login; then
        echo -e "${GREEN}Connection test successful.${NC}"
    else
        echo -e "${YELLOW}WARNING: Connection test failed. Check credentials and URL.${NC}"
    fi
}

# ─── Main actions ─────────────────────────────────────────────────────────────
start_hotspot() {
    check_root
    load_config
    check_dependencies

    [[ -z "$UNIFI_CONTROLLER_URL" || -z "$UNIFI_USERNAME" || -z "$UNIFI_PASSWORD" ]] && {
        echo -e "${RED}ERROR: Run '$0 config' first.${NC}"; exit 1
    }
    [[ -z "$WAN_IF" || -z "$LAN_IF" ]] && detect_interfaces
    [[ -z "$SERVER_IP" ]]              && get_server_ip
    [[ -z "$LOCAL_USER" ]]             && detect_local_user
    [[ -z "$UNIFI_TYPE" ]]             && detect_unifi_type "127.0.0.1"

    echo "Starting UniFi Hotspot management..."
    unifi_login || exit 1
    load_all_vouchers

    setup_acl
    setup_rsyslog
    setup_base_rules
    setup_unifi_ports
    setup_hotspot_logging
    clean_expired_macs
    process_pending_guests
    process_sessions
    apply_iptables_rules

    echo -e "${GREEN}UniFi Hotspot started.${NC}"
    log "INFO: Hotspot started WAN=$WAN_IF LAN=$LAN_IF SERVER=$SERVER_IP TYPE=$UNIFI_TYPE"
}

stop_hotspot() {
    check_root

    if ! iptables -L HOTSPOT &>/dev/null && ! ipset list machotspot &>/dev/null; then
        echo -e "${YELLOW}Hotspot is not running.${NC}"
        return 0
    fi

    echo "Stopping UniFi Hotspot management..."

    # Remove HOTSPOT chain and its jumps
    iptables -F HOTSPOT   2>/dev/null || true
    iptables -X HOTSPOT   2>/dev/null || true
    iptables -D INPUT   -j HOTSPOT 2>/dev/null || true
    iptables -D FORWARD -j HOTSPOT 2>/dev/null || true

    # Remove machotspot ipset
    ipset flush machotspot 2>/dev/null || true
    ipset destroy machotspot 2>/dev/null || true

    # Remove base portal rules (setup_base_rules)
    for proto in tcp udp; do
        iptables -D INPUT   -i "$LAN_IF" -p "$proto" -m multiport --dports "$PORTAL_PORTS" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -i "$LAN_IF" -p "$proto" -m multiport --dports "$PORTAL_PORTS" -j ACCEPT 2>/dev/null || true
    done
    iptables -D INPUT -i "$LAN_IF" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$LAN_IF" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$LAN_IF" -p udp --dport 67 -j ACCEPT 2>/dev/null || true

    # Remove UniFi controller port rules (setup_unifi_ports)
    local UNIFI_PORTS="53,3478,5514,8080,8443,8880,8843,8881,8882,6789,27117,10001,1900,123,11443"
    for proto in tcp udp; do
        iptables -D INPUT  -i "$LAN_IF" -d "$SERVER_IP" -p "$proto" -m multiport --dports "$UNIFI_PORTS" -j ACCEPT 2>/dev/null || true
        iptables -D OUTPUT -p "$proto" -m multiport --dports "$UNIFI_PORTS" -j ACCEPT 2>/dev/null || true
    done

    # Remove hotspot logging rules (setup_hotspot_logging)
    for string in "success" "POST"; do
        iptables -D INPUT -i "$LAN_IF" -p tcp --dport 8880 \
            -m string --string "$string" --algo bm \
            -j LOG --log-prefix "HOTSPOT:" 2>/dev/null || true
    done

    echo -e "${GREEN}UniFi Hotspot stopped.${NC}"
    log "INFO: Hotspot stopped"
}

show_status() {
    load_config
    echo -e "${CYAN}UniFi Hotspot Status${NC}"
    echo "===================="
    printf "%-24s %s\n" "Config:"         "$CONFIG_FILE"
    printf "%-24s %s\n" "Controller:"     "${UNIFI_CONTROLLER_URL:-not set} (${UNIFI_TYPE:-unknown})"
    printf "%-24s %s\n" "Site:"           "${UNIFI_SITE:-default}"
    printf "%-24s %s\n" "WAN:"            "${WAN_IF:-not set}"
    printf "%-24s %s\n" "LAN:"            "${LAN_IF:-not set}"
    printf "%-24s %s\n" "Server IP:"      "${SERVER_IP:-not set}"
    printf "%-24s %s\n" "Local user:"     "${LOCAL_USER:-not set}"
    printf "%-24s %s\n" "Hotspot range:"  "$HOTSPOT_IP_RANGE.$HOTSPOT_RANGE_START-$HOTSPOT_RANGE_END"
    printf "%-24s %s\n" "Portal ports:"   "$PORTAL_PORTS"
    printf "%-24s %s\n" "Active ports:"   "$LOCAL_PORTS"
    echo ""

    local mac_count=0 bl_count=0
    if [[ -f "$MAC_LIST" ]]; then
        mac_count=$(grep -v "guest-placeholder" "$MAC_LIST" 2>/dev/null | wc -l || true)
    fi
    if [[ -f "$MAC_BLACKLIST" ]]; then
        bl_count=$(wc -l < "$MAC_BLACKLIST" 2>/dev/null || true)
        bl_count=${bl_count:-0}
    fi
    printf "%-24s %s\n" "ACL entries:"    "$mac_count"
    printf "%-24s %s\n" "Blacklisted:"    "$bl_count"
    echo ""

    echo "Active clients (status;mac;ip;hostname;end_time):"
    local real_entries
    real_entries=$(grep -v "guest-placeholder" "$MAC_LIST" 2>/dev/null || true)
    if [[ -n "$real_entries" ]]; then
        local now
        now=$(date +%s)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local end_time mac expires_in
            end_time=$(echo "$line" | awk -F';' '{print $5}')
            mac=$(echo "$line"      | awk -F';' '{print $2}')
            expires_in=$(( end_time - now ))
            if (( expires_in > 0 )); then
                printf "  %s  [%dm remaining]\n" "$line" $(( expires_in / 60 ))
            else
                printf "  %s  ${RED}[EXPIRED]${NC}\n" "$line"
            fi
        done <<< "$real_entries"
    else
        echo "  (no entries)"
    fi

    echo ""
    echo "iptables HOTSPOT chain:"
    iptables -L HOTSPOT -v -n 2>/dev/null || echo "  (no HOTSPOT chain active)"
}

do_reload() {
    check_root
    load_config
    echo "Reloading sessions and rules..."
    unifi_login || exit 1
    load_all_vouchers
    clean_expired_macs
    process_pending_guests
    process_sessions
    apply_iptables_rules
    echo -e "${GREEN}Reload complete.${NC}"
    log "INFO: Hotspot reloaded"
}

# ─── Dispatcher with flock ────────────────────────────────────────────────────
# flock prevents two cron invocations from running simultaneously.
mkdir -p /var/lock
exec 200>"$LOCK_FILE"

case "${1:-}" in
    config)
        check_root
        load_config
        interactive_config
        ;;
    start)
        flock -n 200 || {
            echo -e "${YELLOW}Another instance is running. Skipping.${NC}"
            exit 0
        }
        start_hotspot 2>&1 | tee -a "$LOG_FILE"
        ;;
    _start)
        # Internal: kept for backward compatibility
        start_hotspot 2>&1 | tee -a "$LOG_FILE"
        ;;
    stop)
        stop_hotspot 2>&1 | tee -a "$LOG_FILE"
        ;;
    status)
        show_status
        ;;
    reload)
        flock -n 200 || {
            echo -e "${YELLOW}Another instance is running. Skipping.${NC}"
            exit 0
        }
        do_reload 2>&1 | tee -a "$LOG_FILE"
        ;;
    _reload)
        # Internal: kept for backward compatibility
        do_reload 2>&1 | tee -a "$LOG_FILE"
        ;;
    *)
        echo "Usage: $0 {config|start|stop|status|reload}"
        echo "  config  — Interactive setup (network, UniFi API credentials)"
        echo "  start   — Start hotspot management (manual/testing only)"
        echo "  stop    — Stop and remove all rules (manual/testing only)"
        echo "  status  — Show ACL entries with expiry countdown"
        echo "  reload  — Re-query API and refresh rules (use this in cron)"
        echo ""
        echo "Recommended cron entry (every 5 minutes):"
        echo "  */5 * * * * $0 reload"
        exit 1
        ;;
esac
