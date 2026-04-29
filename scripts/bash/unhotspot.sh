#!/bin/bash
# maravento.com
#
# UniFi Network Hotspot - ACL Manager v4
#
# USAGE:
#   Manual : sudo /etc/scr/unhotspot.sh
#   Cron   : * * * * * /etc/scr/unhotspot.sh
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
#   The script runs every minute via cron and executes 5 steps:
#
#   1. DEDUP: verifies that no MAC appears in more than one list.
#      If a MAC is in guest-pending.txt or in any mac-*.txt,
#      it is automatically removed from blockdhcp.txt and dhcpd.leases.
#
#   2. EXPIRED: iterates over mac-hotspot.txt looking for expired vouchers
#      (END_TIME < now). Moves them to guest-pending.txt preserving IP and hostname.
#
#   3. PENDING: queries stat/sta on the UniFi API. Clients connected
#      to the guest SSID without authorization receive a random IP from the
#      configured range and a sequential hostname (guest1, guest2...), and
#      are added to guest-pending.txt. Detection is by SSID match (not the
#      is_guest flag, which UniFi only sets after captive-portal authentication).
#
#   4. SESSIONS: queries stat/guest. UniFi records completed voucher sessions
#      here after the client authenticates (entries may show expired=true even
#      while active — the script filters by end_time > now instead of the
#      expired flag). Clients are moved from guest-pending.txt to
#      mac-hotspot.txt with their end_time.
#
#   5. RELOAD: after all steps complete, compares md5sum snapshots of
#      mac-hotspot.txt and guest-pending.txt taken before processing against
#      their current state. If either file changed, SERVER_RELOAD_SCRIPT is
#      invoked exactly once. This guarantees a single reload per run regardless
#      of how many MACs moved between lists.
#
# ACL FORMAT:
#   mac-hotspot.txt   → a;MAC;IP;HOSTNAME;END_TIME_EPOCH;
#   guest-pending.txt → a;MAC;IP;HOSTNAME;
#
# COOKIE NOTE:
#   UniFi OS uses a JWT cookie with the "partitioned" flag, which curl's
#   Netscape cookie jar discards. The TOKEN value is extracted from the
#   set-cookie header and injected manually in every request.
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
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || true)
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}' || true)
fi
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}' || true)
fi
if [ -z "$local_user" ]; then
    echo "ERROR: Cannot determine local user"
    exit 1
fi

# Hotspot Path
HOTSPOT_PATH="/etc/unhotspot"

# ─── Configuration ────────────────────────────────────────────────────────────
CONFIG_FILE="$HOTSPOT_PATH/config.conf"
# SESSION_TOKEN: stores the raw JWT extracted from the set-cookie header.
# curl's Netscape cookie jar silently drops cookies with the "partitioned"
# flag (used by UniFi OS ≥ 3.x). The token is injected manually instead.
SESSION_TOKEN=""
MAC_LIST="$HOTSPOT_PATH/mac-hotspot.txt"
PENDING_LIST="$HOTSPOT_PATH/guest-pending.txt"
LOG_FILE="/var/log/unhotspot.log"
PENDING_NEW=0
SESSIONS_AUTHORIZED=0
REVOKED=0

# ─── Permanent MAC block list ─────────────────────────────────────────────────
# ACL file for MAC addresses that must be permanently denied a DHCP lease.
# Format: a;MAC;IP;HOSTNAME;   (4 fields — no epoch, no trailing semicolons)
BLOCK_DHCP="/etc/dhcp/blockdhcp.txt"

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
VOUCHER_COUNT=0

# ─── Reload script ───────────────────────────────────────────────────────────
SERVER_RELOAD_SCRIPT="" # overridden by config.conf

# ─── Logging ──────────────────────────────────────────────────────────────────
# Defined early so it is available even if load_config() or setup_config() fail.
log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg"
    # Append to log only if LOG_FILE is writable (may not exist yet at first run)
    if [[ -n "$LOG_FILE" ]]; then
        echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# ─── Setup input helpers ──────────────────────────────────────────────────────

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
    local user="$1" pass="$2" server_ip="$3"
    local ports=(8443 11443)
    local test_url http_code

    echo "  Checking ${server_ip} on ports 8443, 11443 ..."

    for port in "${ports[@]}"; do
        test_url="https://${server_ip}:${port}"

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

    echo "── Network ──────────────────────────────────────"
    local ifaces
    ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | tr '\n' '  ')
    echo "  Available interfaces: $ifaces"
    ask_interface "WAN interface" "eth0" CFG_WAN_IF
    ask_interface "LAN interface" "eth1" CFG_LAN_IF
    ask_ip        "Server IP (this machine)" CFG_SERVER_IP

    echo ""
    echo "── Hotspot IP range ─────────────────────────────"
    CFG_IP_RANGE=$(echo "$CFG_SERVER_IP" | cut -d'.' -f1-3)
    echo "  Hotspot IP range base (auto-detected): $CFG_IP_RANGE"
    ask_octet    "Range start (last octet)" "160" CFG_RANGE_START
    ask_octet    "Range end   (last octet)" "170" CFG_RANGE_END "$CFG_RANGE_START"

    echo ""
    echo "── Hotspot SSID ─────────────────────────────────"
    ask "Guest SSID name (must match exactly in UniFi)" "" CFG_ESSID

    echo ""
    echo "── UniFi credentials ────────────────────────────"
    ask "UniFi admin username" "admin" CFG_UNIFI_USER
    while true; do
        read -rsp "  UniFi admin password: " CFG_UNIFI_PASS; echo ""
        [[ -n "$CFG_UNIFI_PASS" ]] && break
        echo "  ✗ Password cannot be empty."
    done

    echo ""
    echo "── Scanning for UniFi Controller ───────────────"
    local found_url="" found_type=""
    DISCOVERED_URL=""
    DISCOVERED_TYPE=""

    if discover_unifi_controller "$CFG_UNIFI_USER" "$CFG_UNIFI_PASS" "$CFG_SERVER_IP"; then
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

    echo ""
    echo "── Reload script ─────────────────────────────────────"
    echo "  Script to run after ACL changes (restart DHCP, reload iptables, etc.)"
    echo "  Must exist and be executable (chmod +x)"
    while true; do
        read -rp "  Full path to reload script: " CFG_RELOAD_SCRIPT
        if [[ -n "$CFG_RELOAD_SCRIPT" ]]; then
            break
        else
            echo "  ✗ This field is required. The script will not work without it."
        fi
    done

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
PORTAL_PORTS="53,67,68,8880,8881,8882,8843"
LOCAL_PORTS="137:139,445,162,631,8000,3128,853"

# ── Reload script (required) ──────────────────────────────────────────────────
SERVER_RELOAD_SCRIPT="${CFG_RELOAD_SCRIPT}"
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

    if [[ -z "${UNIFI_CONTROLLER_URL:-}" || -z "${UNIFI_USERNAME:-}" || -z "${UNIFI_PASSWORD:-}" ]]; then
        log "ERROR: UNIFI_CONTROLLER_URL, UNIFI_USERNAME and UNIFI_PASSWORD must be set in $CONFIG_FILE"
        exit 1
    fi
}

# ─── ACL file init ────────────────────────────────────────────────────────────
init_acl_files() {
    mkdir -p "$(dirname "$MAC_LIST")" "$(dirname "$LOG_FILE")" "$(dirname "$BLOCK_DHCP")"
    touch "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"
    chmod 600 "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"

    if [[ ! -s "$MAC_LIST" ]]; then
        echo "a;02:00:00:00:00:00;0.0.0.0;guest-placeholder;" >> "$MAC_LIST"
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

# Extract TOKEN from set-cookie header and store in SESSION_TOKEN.
# curl's -c (Netscape jar) silently drops cookies with the "partitioned"
# attribute (used by UniFi OS ≥ 3.x). The token is injected manually
# via -H "Cookie: TOKEN=..." on every subsequent request.
unifi_login() {
    local login_url header_file http_code raw_cookie

    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        login_url="${UNIFI_CONTROLLER_URL}/api/auth/login"
    else
        login_url="${UNIFI_CONTROLLER_URL}/api/login"
    fi

    header_file=$(mktemp /tmp/unifi-hdr-XXXXXX)

    http_code=$(curl -sk \
        -D "$header_file" \
        -o /dev/null \
        -w "%{http_code}" \
        -X POST "$login_url" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
        --connect-timeout 10 --max-time 40 || echo "000")

    if [[ "$http_code" != "200" ]]; then
        log "ERROR: UniFi login failed (HTTP $http_code) at $login_url"
        rm -f "$header_file"
        return 1
    fi

    # Extract CSRF token (UniFi OS sends it in x-updated-csrf-token or x-csrf-token)
    CSRF_TOKEN=$(grep -i 'x-updated-csrf-token\|x-csrf-token' "$header_file" \
        | tail -1 | awk '{print $2}' | tr -d '\r\n' || true)

    # Extract the TOKEN value from set-cookie (works even with partitioned flag)
    raw_cookie=$(grep -i '^set-cookie:' "$header_file" \
        | grep -i 'TOKEN=' \
        | head -1 \
        | sed -E 's/.*TOKEN=([^;]+).*/\1/' \
        | tr -d '\r\n' || true)

    rm -f "$header_file"

    if [[ -z "$raw_cookie" ]]; then
        log "ERROR: Login succeeded (HTTP 200) but TOKEN cookie not found in headers"
        return 1
    fi

    SESSION_TOKEN="$raw_cookie"
    log "INFO: UniFi login OK"
}

# Authenticated GET — sends TOKEN manually; auto-reauth on 401, retries once.
api_get() {
    local url="$1"
    local args=(-sk -w "\n__CODE__:%{http_code}"
        -H "Cookie: TOKEN=${SESSION_TOKEN}")
    [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")

    local raw code body
    raw=$(curl --max-time 30 "${args[@]}" "$url" 2>/dev/null || true)
    code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
    body=$(echo "$raw" | grep -v '__CODE__:')

    if [[ "$code" == "401" ]]; then
        log "INFO: Session expired, re-authenticating..."
        if ! unifi_login; then
            log "ERROR: Re-authentication failed"
            echo "{}"
            return 1
        fi
        args=(-sk -w "\n__CODE__:%{http_code}"
            -H "Cookie: TOKEN=${SESSION_TOKEN}")
        [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
        raw=$(curl --max-time 30 "${args[@]}" "$url" 2>/dev/null || true)
        code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
        body=$(echo "$raw" | grep -v '__CODE__:')
    fi

    if [[ -z "$code" ]]; then
        log "WARNING: API GET $url → no response (timeout or network error)"
        echo "{}"
        return 0
    fi
    if [[ "$code" != "200" ]]; then
        log "WARNING: API GET $url → HTTP $code"
        echo "{}"
        return 0
    fi

    echo "$body"
}

# Authenticated POST (used by unauthorize_pending)
api_post() {
    local url="$1" payload="$2"
    local args=(-sk -w "\n__CODE__:%{http_code}"
        -X POST
        -H "Content-Type: application/json"
        -H "Cookie: TOKEN=${SESSION_TOKEN}")
    [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")

    local raw code
    raw=$(curl --max-time 30 "${args[@]}" -d "$payload" "$url" 2>/dev/null || true)
    code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
    echo "$code"
}

# ─── Voucher cache (fetched once per run) ─────────────────────────────────────
load_all_vouchers() {
    local url rc count
    url=$(api_path "stat/voucher")
    VOUCHER_CACHE=$(api_get "$url")
    rc=$(echo "$VOUCHER_CACHE" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    if [[ "$rc" != "ok" ]]; then
        log "WARNING: Could not load vouchers (rc=${rc:-empty})"
        VOUCHER_CACHE=""
        return
    fi
    count=$(echo "$VOUCHER_CACHE" | jq '.data | length' 2>/dev/null || echo 0)
    VOUCHER_COUNT="$count"
}

# Returns epoch end_time for a MAC, or empty if no valid voucher found.
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
get_next_guest_number() {
    local used n=1
    used=$(grep -oh 'guest[0-9]*' "$MAC_LIST" "$PENDING_LIST" 2>/dev/null \
        | sed 's/guest//' | sort -n | uniq || true)
    while echo "$used" | grep -q "^${n}$"; do (( n++ )); done
    echo "$n"
}

assign_ip_and_hostname() {
    local available=()
    local i
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
    fi
}

# ─── MAC list deduplication ───────────────────────────────────────────────────
# blockdhcp.txt must use format a;MAC;IP;HOSTNAME; (4 fields, no epoch).
# Entries with extra fields are sanitized on each run.
dedup_mac_lists() {
    local acl_dir
    acl_dir="$(dirname "$MAC_LIST")"

    # Collect all managed MACs (guest-pending + mac-*.txt)
    local managed_macs
    managed_macs=$(
        {
            grep -ih '^a;' "$PENDING_LIST" 2>/dev/null || true
            grep -rih '^a;' "$acl_dir"/mac-*.txt 2>/dev/null || true
        } | awk -F';' '{print tolower($2)}' \
          | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' \
          | sort -u
    )

    local removed_block=0 removed_leases=0 sanitized_block=0

    # 1. Sanitize and clean blockdhcp.txt
    if [[ -f "$BLOCK_DHCP" ]]; then
        local tmp_block
        tmp_block=$(mktemp)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            local bmac bip bhostname field_count
            IFS=';' read -r _ bmac bip bhostname _ <<< "$line"
            bmac=$(echo "$bmac" | tr '[:upper:]' '[:lower:]')

            # Skip if this MAC is already managed
            if echo "$managed_macs" | grep -q "^${bmac}$"; then
                log "INFO: dedup → removed $bmac from blockdhcp.txt"
                (( removed_block++ )) || true
                continue
            fi

            # Normalize to 4-field format a;MAC;IP;HOSTNAME;
            # Count semicolons to detect over-long entries (e.g. with epoch)
            field_count=$(echo "$line" | tr -cd ';' | wc -c)
            if (( field_count > 4 )); then
                local clean_line="a;${bmac};${bip};${bhostname};"
                echo "$clean_line" >> "$tmp_block"
                (( sanitized_block++ )) || true
            else
                echo "$line" >> "$tmp_block"
            fi
        done < "$BLOCK_DHCP"
        mv "$tmp_block" "$BLOCK_DHCP" && chmod 600 "$BLOCK_DHCP"
    fi

    # 2. Clean dhcpd.leases
    local dhcpd_leases="/var/lib/dhcp/dhcpd.leases"
    if [[ -f "$dhcpd_leases" && -n "$managed_macs" ]]; then
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

    if (( sanitized_block > 0 )); then
        log "INFO: dedup → sanitized $sanitized_block blockdhcp entries (extra fields removed)"
    fi
    # counts available as removed_block / removed_leases for callers
}

# ─── ACL helpers ──────────────────────────────────────────────────────────────
add_mac_to_acl() {
    local mac="$1" ip="$2" hostname="$3" end_time="$4"
    local new_line="a;${mac};${ip};${hostname};${end_time};"

    if grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null; then
        sed -i "/^a;${mac};/Id" "$PENDING_LIST"
    fi

    if grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
        local existing_end
        existing_end=$(grep -i "^a;${mac};" "$MAC_LIST" | head -1 | awk -F';' '{print $5}')
        if [[ "$end_time" != "$existing_end" ]]; then
            sed -i "s|^a;${mac};.*|${new_line}|I" "$MAC_LIST"
            log "INFO: Updated end_time for $mac ($existing_end → $end_time)"
        fi
    else
        echo "$new_line" >> "$MAC_LIST"
        local exp_human
        exp_human=$(date -d "@$end_time" 2>/dev/null || echo "$end_time")
        log "INFO: Authorized $mac ip=$ip hostname=$hostname expires=$exp_human"
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

    mv "$tmp" "$MAC_LIST" && chmod 600 "$MAC_LIST"

    if [[ ! -s "$MAC_LIST" ]]; then
        echo "a;02:00:00:00:00:00;0.0.0.0;guest-placeholder;" >> "$MAC_LIST"
    fi
}

# ─── Clean guest-pending entries no longer seen in stat/sta ──────────────────
# Removes MACs from guest-pending.txt that are no longer connected to the
# guest SSID according to UniFi. Uses the same stat/sta response to avoid
# an extra API call. If stat/sta is unavailable, skips silently to avoid
# false removals.
clean_disconnected_pending() {
    local guests_data="$1"
    [[ ! -s "$PENDING_LIST" ]] && return

    local active_macs
    active_macs=$(echo "$guests_data" | jq -r \
        --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.mac != null and .mac != "")
        | select(.essid == $essid)
        | (.mac | ascii_downcase)
    ' 2>/dev/null || true)

    local tmp removed=0
    tmp=$(mktemp)
    while IFS=';' read -r status mac rest; do
        [[ "$status" != "a" ]] && continue
        [[ -z "$mac" ]] && continue
        if echo "$active_macs" | grep -qi "^${mac}$"; then
            echo "${status};${mac};${rest}">> "$tmp"
        else
            log "INFO: Removed disconnected pending $mac — not seen on $HOTSPOT_ESSID"
            (( removed++ )) || true
        fi
    done < "$PENDING_LIST"
    mv "$tmp" "$PENDING_LIST" && chmod 600 "$PENDING_LIST"
}

# ─── Step 2: detect new portal clients (stat/sta) ─────────────────────────────
# NOTE: Clients on the guest SSID appear in stat/sta with authorized=false
# before and during portal authentication. Detection is by .essid == HOTSPOT_ESSID
# regardless of the is_guest or authorized flags, both of which are unreliable
# at this stage. The script adds them to guest-pending.txt so they receive a
# fixed IP via DHCP before the voucher is entered.
process_pending_guests() {
    local endpoint guests_data rc
    endpoint=$(api_path "stat/sta")
    guests_data=$(api_get "$endpoint")
    rc=$(echo "$guests_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/sta unavailable (rc=${rc:-empty}) — skipping pending"
        return
    fi

    clean_disconnected_pending "$guests_data"

    local count=0
    while IFS=$'\t' read -r mac ip; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue

        # Skip if already managed
        grep -qi "^a;${mac};" "$MAC_LIST"     2>/dev/null && continue
        grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null && continue

        # Assign IP and hostname from the hotspot range
        local iph assigned_ip assigned_hostname
        iph=$(assign_ip_and_hostname) || continue
        assigned_ip=$(echo "$iph" | cut -d';' -f1)
        assigned_hostname=$(echo "$iph" | cut -d';' -f2)

        echo "a;${mac};${assigned_ip};${assigned_hostname};" >> "$PENDING_LIST"
        log "INFO: Pending guest $mac → ip=$assigned_ip hostname=$assigned_hostname (ssid=$HOTSPOT_ESSID)"

        remove_from_leases "$mac"
        (( count++ )) || true

    done < <(echo "$guests_data" | jq -r \
        --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.mac != null and .mac != "")
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (.ip // "")]
        | join("\t")
    ' 2>/dev/null || true)

    PENDING_NEW=$count
}

# ─── Step 3: detect voucher-authenticated clients (stat/guest) ────────────────
# NOTE: In UniFi OS Network 10.x, stat/guest entries carry expired=true even
# for active sessions — the flag reflects internal state, not whether end_time
# has passed. Filtering on expired==false silently discards all valid sessions.
# Instead, we filter on end_time > now, which is the only reliable indicator
# of an active session. Already-expired entries are skipped silently.
process_sessions() {
    local endpoint sessions_data rc added=0
    local now
    now=$(date +%s)

    endpoint=$(api_path "stat/guest")
    sessions_data=$(api_get "$endpoint")
    rc=$(echo "$sessions_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/guest unavailable (rc=${rc:-empty}) — skipping sessions"
        return
    fi

    while IFS=$'\t' read -r mac end_time; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        [[ -z "$end_time" || "$end_time" == "null" ]] && continue

        # Skip sessions that are already expired
        if (( end_time <= now )); then
            continue
        fi

        # Skip if already authorized with same or later end_time
        if grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
            local existing_end
            existing_end=$(grep -i "^a;${mac};" "$MAC_LIST" | head -1 | awk -F';' '{print $5}')
            if [[ "$end_time" == "$existing_end" ]]; then
                continue
            fi
        fi

        local assigned_ip="" assigned_hostname="" entry=""
        entry=$(grep -i "^a;${mac};" "$PENDING_LIST" 2>/dev/null | head -1 || true)
        assigned_hostname=$(echo "$entry" | awk -F';' '{print $4}')
        assigned_ip=$(echo "$entry" | awk -F';' '{print $3}')

        # If not in pending or missing IP, assign new ones
        if [[ -z "$assigned_ip" ]]; then
            local iph
            iph=$(assign_ip_and_hostname) || continue
            assigned_ip=$(echo "$iph" | cut -d';' -f1)
            [[ -z "$assigned_hostname" ]] && assigned_hostname=$(echo "$iph" | cut -d';' -f2)
        fi
        [[ -z "$assigned_hostname" ]] && assigned_hostname="guest$(get_next_guest_number)"

        add_mac_to_acl "$mac" "$assigned_ip" "$assigned_hostname" "$end_time"
        (( added++ )) || true

    done < <(echo "$sessions_data" | jq -r '
        .data[]
        | select(.mac != null and .mac != "")
        | select(.end != null)
        | [(.mac | ascii_downcase), (.end | tostring)]
        | join("\t")
    ' 2>/dev/null || true)

    SESSIONS_AUTHORIZED=$added
}

# ─── Revoke MACs that UniFi reports as unauthorized ───────────────────────────
revoke_unauthorized() {
    local endpoint sta_data rc
    endpoint=$(api_path "stat/sta")
    sta_data=$(api_get "$endpoint") || true
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)

    if [[ "$rc" != "ok" ]]; then
        log "INFO: stat/sta unavailable (rc=${rc:-empty}) — skipping revoke"
        return
    fi

    local revoked=0
    local macs_to_revoke=()

    while IFS=';' read -r status mac ip hostname end_time _; do
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

    local mac
    for mac in "${macs_to_revoke[@]+"${macs_to_revoke[@]}"}"; do
        [[ -z "$mac" ]] && continue
        log "INFO: Revoking $mac — authorized=false in UniFi"
        expire_to_pending "$mac"
        sed -i "/^a;${mac};/Id" "$MAC_LIST" 2>/dev/null || true
        (( revoked++ )) || true
    done

    REVOKED=$revoked
    return 0
}

# ─── Send unauthorize-guest command to UniFi for pending MACs ─────────────────
unauthorize_pending() {
    [[ ! -s "$PENDING_LIST" ]] && return

    local endpoint sta_data rc
    endpoint=$(api_path "stat/sta")
    sta_data=$(api_get "$endpoint") || true

    if [[ -z "$sta_data" ]]; then
        log "WARNING: unauthorize_pending: cannot fetch stat/sta, skipping"
        return
    fi

    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    if [[ "$rc" != "ok" ]]; then
        log "WARNING: unauthorize_pending: stat/sta returned rc=${rc:-empty}"
        return
    fi

    while IFS=';' read -r status mac ip hostname _; do
        [[ "$status" != "a" ]] && continue
        [[ "$mac" == "02:00:00:00:00:00" ]] && continue
        [[ -z "$mac" ]] && continue

        local authorized
        authorized=$(echo "$sta_data" | jq -r \
            --arg mac "$mac" '
            .data[]
            | select((.mac | ascii_downcase) == $mac)
            | .authorized // false
        ' 2>/dev/null | head -1 || true)

        [[ "$authorized" != "true" ]] && continue

        local unauth_url http_code
        unauth_url=$(api_path "cmd/stamgr")
        http_code=$(api_post "$unauth_url" \
            "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}")

        if [[ "$http_code" == "200" ]]; then
            log "INFO: Successfully unauthorized $mac"
        else
            log "WARNING: Failed to unauthorize $mac (HTTP $http_code)"
        fi
    done < "$PENDING_LIST"
}

# ─── ACL change detector & reload trigger ────────────────────────────────────
# Call snapshot_acls BEFORE the processing functions to record the baseline.
# Call check_and_reload_if_changed AFTER all processing functions; it compares
# the current state of MAC_LIST and PENDING_LIST against the baseline and
# invokes SERVER_RELOAD_SCRIPT exactly once if either file changed.
_ACL_SNAPSHOT_HOTSPOT=""
_ACL_SNAPSHOT_PENDING=""

snapshot_acls() {
    _ACL_SNAPSHOT_HOTSPOT=$(md5sum "$MAC_LIST"     2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_PENDING=$(md5sum "$PENDING_LIST" 2>/dev/null | awk '{print $1}' || echo "absent")
}

check_and_reload_if_changed() {
    local cur_hotspot cur_pending
    cur_hotspot=$(md5sum "$MAC_LIST"     2>/dev/null | awk '{print $1}' || echo "absent")
    cur_pending=$(md5sum "$PENDING_LIST" 2>/dev/null | awk '{print $1}' || echo "absent")

    if [[ "$cur_hotspot" == "$_ACL_SNAPSHOT_HOTSPOT" && \
          "$cur_pending" == "$_ACL_SNAPSHOT_PENDING" ]]; then
        log "INFO: ACLs unchanged — skipping reload"
        return
    fi

    [[ "$cur_hotspot" != "$_ACL_SNAPSHOT_HOTSPOT" ]] && log "INFO: mac-hotspot.txt changed"
    [[ "$cur_pending"  != "$_ACL_SNAPSHOT_PENDING"  ]] && log "INFO: guest-pending.txt changed"

    if [[ -n "${SERVER_RELOAD_SCRIPT:-}" && -x "$SERVER_RELOAD_SCRIPT" ]]; then
        log "INFO: ACL changed — invoking $SERVER_RELOAD_SCRIPT"
        bash "$SERVER_RELOAD_SCRIPT" >> "$LOG_FILE" 2>&1 \
            || log "WARNING: $SERVER_RELOAD_SCRIPT exited with error"
    else
        log "WARNING: ACLs changed but SERVER_RELOAD_SCRIPT is not set or not executable"
    fi
}

# ─── NOTE: set -euo pipefail is intentionally placed AFTER all functions are
# defined and after load_config(), so that early failures (missing config,
# login errors) are handled explicitly and logged rather than causing a silent
# exit. Individual critical sections use explicit error checks instead.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    load_config
    log "INFO: ══════ run start ══════"
    init_acl_files
    if ! unifi_login; then
        log "ERROR: Cannot authenticate to UniFi controller — aborting"
        exit 1
    fi
    load_all_vouchers
    dedup_mac_lists
    snapshot_acls
    clean_expired_macs
    process_pending_guests
    process_sessions
    revoke_unauthorized
    unauthorize_pending
    check_and_reload_if_changed

    # ── Run summary ──────────────────────────────────────────────────────────
    local pending_total authorized_total
    pending_total=$(grep -c "^a;" "$PENDING_LIST" 2>/dev/null || true)
    pending_total=$(( ${pending_total:-0} + 0 ))
    authorized_total=$(grep -c "^a;" "$MAC_LIST" 2>/dev/null || true)
    authorized_total=$(( ${authorized_total:-0} + 0 ))
    # subtract placeholder line
    (( authorized_total > 0 )) && (( authorized_total-- )) || true
    log "INFO: vouchers=$VOUCHER_COUNT | authorized=$authorized_total | pending=$pending_total | new_pending=$PENDING_NEW | new_auth=$SESSIONS_AUTHORIZED | revoked=$REVOKED"
    log "INFO: ══════ run end ══════"
}

main
