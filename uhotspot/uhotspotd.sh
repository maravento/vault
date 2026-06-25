#!/bin/bash
# maravento.com
#
################################################################################
#
# uhotspotd — UniFi Hotspot Manager Daemon
#
# DESCRIPTION:
#   Persistent systemd service for UniFi hotspot ACL management.
#   Runs a full management cycle every POLL_INTERVAL seconds (configured in
#   uhotspot.conf, default 10) with a persistent UniFi API
#   session and CSRF token shared across all calls within a cycle.
#
#   Session tokens are persisted to TOKEN_STATE_FILE (/run/uhotspotd_session)
#   so that re-authentication inside $(...) subshells propagates correctly to
#   subsequent API calls in the same cycle.
#
#   MANAGED MACS (optional):
#   If /etc/acl/acl_mac/mac-*.txt files exist, MACs listed there are treated
#   as managed corporate devices. They are silently excluded from the guest
#   portal flow (steps 3, 7, 8) and are kept authorized in UniFi (step 11)
#   so they bypass the captive portal on HOTSPOT_ESSID without needing a
#   voucher. If no mac-*.txt files exist, steps 3 and 11 are no-ops.
#
# CYCLE (every POLL_INTERVAL seconds, default 10, set in uhotspot.conf):
#   1. VOUCHERS    — load voucher cache from UniFi (stat/voucher)
#   2. DEDUP       — cross-list consistency check, blockdhcp cleanup
#   3. CLEAN MACS  — remove mac-*.txt entries from guest-pending / mac-hotspot
#   4. SORT        — sort ACL files by IP
#   5. SNAPSHOT    — md5sum baseline of ACL files before processing
#   6. EXPIRED     — move expired mac-hotspot entries to guest-pending
#   7. PENDING     — detect new portal clients via stat/sta
#   8. SESSIONS    — promote voucher-authenticated clients to mac-hotspot
#   9. REVOKE      — move UniFi-unauthorized clients back to guest-pending
#  10. UNAUTHORIZE — send unauthorize-guest to pending MACs still authorized
#  11. AUTHORIZE   — re-authorize managed MACs (mac-*.txt) seen on HOTSPOT_ESSID
#                    that UniFi reports as unauthorized; checked every cycle so
#                    reconnecting devices are covered automatically
#  12. BACKUP      — update guest-wellknow.txt, clean blockdhcp conflicts
#  13. RELOAD      — invoke SERVER_RELOAD_SCRIPT if ACLs changed
#
# stat/sta is queried once per cycle and shared across steps 7, 9, 10, 11.
#
# CONFIG:  /etc/uhotspot/uhotspot.conf
# LOG:     /var/log/uhotspot.log
# SERVICE: systemctl status uhotspotd
#
# TESTED ON:
#   Ubuntu 24.04.x — UniFi OS Network 10.x
#
################################################################################

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: must be run as root" >&2
    exit 1
fi

SCRIPT_LOCK="/var/lock/uhotspotd.lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "uhotspotd is already running"
    exit 1
fi

TEMP_FILES_TO_CLEAN=()
cleanup_temp() {
    local f
    for f in "${TEMP_FILES_TO_CLEAN[@]+"${TEMP_FILES_TO_CLEAN[@]}"}"; do
        rm -f "$f" 2>/dev/null || true
    done
}
trap cleanup_temp EXIT

# ── Paths & constants ─────────────────────────────────────────────────────────
LOG_FILE="/var/log/uhotspot.log"
HOTSPOT_PATH="/etc/uhotspot"
CONFIG_FILE="$HOTSPOT_PATH/uhotspot.conf"
ACL_MAC_PATH="/etc/acl/acl_mac"
MAC_LIST="$HOTSPOT_PATH/mac-hotspot.txt"
PENDING_LIST="$HOTSPOT_PATH/guest-pending.txt"
BLOCK_DHCP="/etc/acl/acl_dhcp/blockdhcp.txt"
LEASE_REMOVE_QUEUE="$HOTSPOT_PATH/leases-remove-queue.txt"

TOKEN_STATE_FILE="/run/uhotspotd_session"

# Minutes UniFi keeps a managed MAC (mac-*.txt) authorized on the guest portal.
# Re-sent periodically by authorize_managed_macs (step 11) well before expiry.
MANAGED_AUTHORIZE_MINUTES=527040   # 366 days

# ── Runtime state ─────────────────────────────────────────────────────────────
SESSION_TOKEN=""
CSRF_TOKEN=""
MANAGED_MACS=""
VOUCHER_CACHE=""
VOUCHER_COUNT=0
PENDING_NEW=0
SESSIONS_AUTHORIZED=0
REVOKED=0
MANAGED_AUTHORIZED=0
_ACL_SNAPSHOT_HOTSPOT=""
_ACL_SNAPSHOT_PENDING=""
_ACL_SNAPSHOT_QUEUE=""

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# ── Config ────────────────────────────────────────────────────────────────────
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: $CONFIG_FILE not found" >&2
        exit 1
    fi
    local _owner _perms _gdigit _odigit
    _owner=$(stat -c '%U' "$CONFIG_FILE" 2>/dev/null)
    _perms=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null)
    _gdigit="${_perms: -2:1}"
    _odigit="${_perms: -1}"
    if [[ "$_owner" != "root" ]] || [[ "$_gdigit" =~ [2367] ]] || [[ "$_odigit" =~ [2367] ]]; then
        echo "ERROR: $CONFIG_FILE has unsafe owner/permissions (owner=$_owner perms=$_perms)" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    local missing=()
    [[ -z "${UNIFI_CONTROLLER_URL:-}" ]] && missing+=("UNIFI_CONTROLLER_URL")
    [[ -z "${UNIFI_USERNAME:-}"       ]] && missing+=("UNIFI_USERNAME")
    [[ -z "${UNIFI_PASSWORD:-}"       ]] && missing+=("UNIFI_PASSWORD")
    [[ -z "${HOTSPOT_ESSID:-}"        ]] && missing+=("HOTSPOT_ESSID")
    [[ -z "${HOTSPOT_IP_RANGE:-}"     ]] && missing+=("HOTSPOT_IP_RANGE")
    [[ -z "${HOTSPOT_RANGE_START:-}"  ]] && missing+=("HOTSPOT_RANGE_START")
    [[ -z "${HOTSPOT_RANGE_END:-}"    ]] && missing+=("HOTSPOT_RANGE_END")
    [[ -z "${SERVER_RELOAD_SCRIPT:-}" ]] && missing+=("SERVER_RELOAD_SCRIPT")
    [[ -z "${UNIFI_TYPE:-}"           ]] && missing+=("UNIFI_TYPE")
    [[ -z "${UNIFI_SITE:-}"           ]] && missing+=("UNIFI_SITE")

    if (( ${#missing[@]} > 0 )); then
        log "ERROR: Missing variables in $CONFIG_FILE: ${missing[*]}"
        exit 1
    fi
}

# ── Installation check ────────────────────────────────────────────────────────
verify_installation() {
    if [[ ! -f "${SERVER_RELOAD_SCRIPT:-}" ]]; then
        log "ERROR: SERVER_RELOAD_SCRIPT not found: ${SERVER_RELOAD_SCRIPT:-unset}"
        exit 1
    elif [[ ! -x "$SERVER_RELOAD_SCRIPT" ]]; then
        log "ERROR: SERVER_RELOAD_SCRIPT not executable: $SERVER_RELOAD_SCRIPT"
        exit 1
    fi
    if ! systemctl is-active --quiet pydhcpd 2>/dev/null; then
        log "ERROR: pydhcpd is not active"
        exit 1
    fi
    log "INFO: Installation verified"
}

# ── ACL file init ─────────────────────────────────────────────────────────────
init_acl_files() {
    mkdir -p "$(dirname "$MAC_LIST")" "$(dirname "$LOG_FILE")" "$(dirname "$BLOCK_DHCP")"
    touch "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"
    chmod 600 "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"
}

# ── UniFi API ─────────────────────────────────────────────────────────────────
# SESSION_TOKEN and CSRF_TOKEN are written to TOKEN_STATE_FILE after every
# login and after every API response that rotates them. Because api_get and
# api_post run inside $(...) subshells, variable updates inside those subshells
# are lost when the subshell exits. Writing to a file sidesteps that: the next
# subshell reads the file at entry and picks up the latest token, so a single
# reauth propagates correctly across all subsequent calls in the same cycle.

api_path() {
    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        echo "${UNIFI_CONTROLLER_URL}/proxy/network/api/s/${UNIFI_SITE}/${1}"
    else
        echo "${UNIFI_CONTROLLER_URL}/api/s/${UNIFI_SITE}/${1}"
    fi
}

_save_session() {
    printf '%s\n%s\n' "$SESSION_TOKEN" "$CSRF_TOKEN" > "$TOKEN_STATE_FILE" 2>/dev/null || true
}

_load_session() {
    [[ ! -f "$TOKEN_STATE_FILE" ]] && return
    local tok csrf
    { IFS= read -r tok; IFS= read -r csrf; } < "$TOKEN_STATE_FILE" 2>/dev/null || return
    [[ -n "$tok"  ]] && SESSION_TOKEN="$tok"
    [[ -n "$csrf" ]] && CSRF_TOKEN="$csrf"
}

_update_session_from_headers() {
    local hfile="$1"
    [[ ! -f "$hfile" ]] && return
    local new_tok new_csrf changed=0
    new_tok=$(grep -i '^set-cookie:' "$hfile" | grep -i 'TOKEN=' | head -1 \
        | sed -E 's/.*TOKEN=([^;]+).*/\1/' | tr -d '\r\n' || true)
    new_csrf=$(grep -iE '^(x-updated-csrf-token|x-csrf-token):' "$hfile" | tail -1 \
        | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '\r\n' || true)
    if [[ -n "$new_tok"  && "$new_tok"  != "$SESSION_TOKEN" ]]; then SESSION_TOKEN="$new_tok";  changed=1; fi
    if [[ -n "$new_csrf" && "$new_csrf" != "$CSRF_TOKEN"    ]]; then CSRF_TOKEN="$new_csrf";    changed=1; fi
    (( changed )) && _save_session
}

unifi_login() {
    local login_url header_file http_code raw_cookie payload

    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        login_url="${UNIFI_CONTROLLER_URL}/api/auth/login"
    else
        login_url="${UNIFI_CONTROLLER_URL}/api/login"
    fi

    header_file=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${header_file}")
    payload=$(jq -n --arg u "$UNIFI_USERNAME" --arg p "$UNIFI_PASSWORD" \
        '{username: $u, password: $p}')

    http_code=$(curl -sk \
        -D "$header_file" \
        -o /dev/null \
        -w "%{http_code}" \
        -X POST "$login_url" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --connect-timeout 10 --max-time 40 || echo "000")

    if [[ "$http_code" != "200" ]]; then
        log "ERROR: UniFi login failed (HTTP $http_code)"
        rm -f "$header_file"
        return 1
    fi

    local new_csrf new_tok
    new_tok=$(grep -i '^set-cookie:' "$header_file" \
        | grep -i 'TOKEN=' \
        | head -1 \
        | sed -E 's/.*TOKEN=([^;]+).*/\1/' \
        | tr -d '\r\n' || true)

    if [[ -z "$new_tok" ]]; then
        log "ERROR: Login OK but TOKEN cookie not found"
        rm -f "$header_file"
        return 1
    fi

    SESSION_TOKEN="$new_tok"

    # UniFi OS embeds the CSRF token inside the JWT payload (csrfToken field).
    # Extract it from the second segment of the JWT (base64-encoded JSON).
    local jwt_payload padded
    jwt_payload=$(echo "$new_tok" | cut -d'.' -f2)
    padded="${jwt_payload}$(printf '%0.s=' $(seq 1 $(( (4 - ${#jwt_payload} % 4) % 4 ))))"
    new_csrf=$(echo "$padded" | base64 -d 2>/dev/null \
        | jq -r '.csrfToken // empty' 2>/dev/null || true)

    # Fallback: check response headers (classic UniFi controller).
    # Header file must still exist at this point — do not delete it before here.
    if [[ -z "$new_csrf" ]]; then
        new_csrf=$(grep -iE '^(x-updated-csrf-token|x-csrf-token):' "$header_file" \
            | tail -1 | sed -E 's/^[^:]+:[[:space:]]*//' | tr -d '\r\n' || true)
    fi

    rm -f "$header_file"

    CSRF_TOKEN="$new_csrf"
    _save_session
    log "INFO: UniFi login OK (csrf=${CSRF_TOKEN:0:8}...)"
}

api_get() {
    local url="$1"
    _load_session

    local hdr
    hdr=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("$hdr")

    local args=(-sk -w "\n__CODE__:%{http_code}" -D "$hdr"
        -H "Cookie: TOKEN=${SESSION_TOKEN}")
    [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")

    local raw code body
    raw=$(curl --max-time 30 "${args[@]}" "$url" 2>/dev/null || true)
    code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
    body=$(echo "$raw" | grep -v '__CODE__:')
    _update_session_from_headers "$hdr"

    if [[ "$code" == "401" ]]; then
        log "INFO: Session expired — re-authenticating"
        if ! unifi_login; then
            log "ERROR: Re-authentication failed"
            rm -f "$hdr"
            echo "{}"
            return 1
        fi
        _load_session
        args=(-sk -w "\n__CODE__:%{http_code}" -D "$hdr"
            -H "Cookie: TOKEN=${SESSION_TOKEN}")
        [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
        raw=$(curl --max-time 30 "${args[@]}" "$url" 2>/dev/null || true)
        code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
        body=$(echo "$raw" | grep -v '__CODE__:')
        _update_session_from_headers "$hdr"
    fi

    rm -f "$hdr"

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

api_post() {
    local url="$1" payload="$2"
    _load_session

    local hdr
    hdr=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("$hdr")

    local args=(-sk -w "\n__CODE__:%{http_code}" -D "$hdr"
        -X POST
        -H "Content-Type: application/json"
        -H "Cookie: TOKEN=${SESSION_TOKEN}")
    [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")

    local raw code
    raw=$(curl --max-time 30 "${args[@]}" -d "$payload" "$url" 2>/dev/null || true)
    code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
    _update_session_from_headers "$hdr"

    if [[ "$code" == "401" ]]; then
        log "INFO: Session expired on POST — re-authenticating"
        if ! unifi_login; then
            log "ERROR: Re-authentication failed on POST"
            rm -f "$hdr"
            echo "$code"
            return 1
        fi
        _load_session
        args=(-sk -w "\n__CODE__:%{http_code}" -D "$hdr"
            -X POST
            -H "Content-Type: application/json"
            -H "Cookie: TOKEN=${SESSION_TOKEN}")
        [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
        raw=$(curl --max-time 30 "${args[@]}" -d "$payload" "$url" 2>/dev/null || true)
        code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
        _update_session_from_headers "$hdr"
    fi

    rm -f "$hdr"
    echo "$code"
}

# ── Step 1: voucher cache ─────────────────────────────────────────────────────
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

# ── IP/hostname assignment ────────────────────────────────────────────────────
get_next_guest_number() {
    local used n=1 max_n
    max_n=$(( HOTSPOT_RANGE_END - HOTSPOT_RANGE_START + 2 ))
    used=$(grep -oh 'guest[0-9]*' "$MAC_LIST" "$PENDING_LIST" 2>/dev/null \
        | sed 's/guest//' | sort -n | uniq || true)
    while echo "$used" | grep -q "^${n}$" && (( n <= max_n )); do
        (( n++ ))
    done
    echo "$n"
}

# NOTE: called inside $() subshells — no log(), no side effects.
# Returns "IP;hostname" via stdout only.
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
        return 1
    fi
    local guest_num
    guest_num=$(get_next_guest_number)
    echo "${available[0]};guest${guest_num}"
}

get_voucher_code_by_end_time() {
    local end_time="$1"
    [[ -z "$VOUCHER_CACHE" || -z "$end_time" ]] && return 0
    echo "$VOUCHER_CACHE" | jq -r \
        --argjson et "$end_time" '
        .data[]
        | select(.end_time == $et)
        | .code // empty
    ' 2>/dev/null | head -1 || true
}

# ── Lease removal queue ───────────────────────────────────────────────────────
queue_lease_removal() {
    local mac="$1"
    local lc_mac
    lc_mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    if ! grep -qxF "$lc_mac" "$LEASE_REMOVE_QUEUE" 2>/dev/null; then
        echo "$lc_mac" >> "$LEASE_REMOVE_QUEUE"
        log "INFO: Queued lease removal for $lc_mac"
    fi
}

# ── Step 2: MAC list deduplication ───────────────────────────────────────────
dedup_mac_lists() {
    # MANAGED_MACS is only populated when MANAGED_MACS_ENABLED=true in uhotspot.conf.
    # When disabled, clean_managed_macs and authorize_managed_macs become no-ops
    # because both check [[ -z "$MANAGED_MACS" ]] && return at their entry point.
    if [[ "${MANAGED_MACS_ENABLED:-false}" != "true" ]]; then
        MANAGED_MACS=""
    else
        MANAGED_MACS=$(
            {
                for f in "$ACL_MAC_PATH"/mac-*.txt; do
                    [[ -f "$f" ]] && grep -ih '^a;' "$f" 2>/dev/null || true
                done
            } | awk -F';' '{print tolower($2)}' \
              | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' \
              | sort -u || true
        )
    fi

    local all_macs
    all_macs=$(
        {
            awk -F';' '/^a;/{print tolower($2)}' "$PENDING_LIST" 2>/dev/null || true
            awk -F';' '/^a;/{print tolower($2)}' "$MAC_LIST"     2>/dev/null || true
            echo "$MANAGED_MACS"
        } | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' \
          | sort -u || true
    )

    local removed_block=0 sanitized_block=0

    if [[ -f "$BLOCK_DHCP" ]]; then
        local tmp_block
        tmp_block=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${tmp_block}")
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local bmac bip bhostname field_count
            IFS=';' read -r _ bmac bip bhostname _ <<< "$line"
            bmac=$(echo "$bmac" | tr '[:upper:]' '[:lower:]')
            if echo "$all_macs" | grep -q "^${bmac}$"; then
                log "INFO: dedup → removed $bmac from blockdhcp.txt"
                (( removed_block++ )) || true
                continue
            fi
            field_count=$(echo "$line" | tr -cd ';' | wc -c)
            if (( field_count != 4 )); then
                echo "a;${bmac};${bip};${bhostname};" >> "$tmp_block"
                (( sanitized_block++ )) || true
            else
                echo "$line" >> "$tmp_block"
            fi
        done < "$BLOCK_DHCP"
        mv "$tmp_block" "$BLOCK_DHCP" && chmod 600 "$BLOCK_DHCP"
    fi

    if (( sanitized_block > 0 )); then
        log "INFO: dedup → sanitized $sanitized_block blockdhcp entries"
    fi
}

# ── Step 3: clean managed MACs from hotspot lists ─────────────────────────────
# Removes any MAC present in mac-*.txt from guest-pending and mac-hotspot.
# Handles the race where a client was added to a hotspot list before its MAC
# was moved to a managed ACL file, or entered the portal from a corporate device.
clean_managed_macs() {
    [[ -z "$MANAGED_MACS" ]] && return
    local removed=0 tmp

    for list in "$PENDING_LIST" "$MAC_LIST"; do
        [[ ! -f "$list" ]] && continue
        tmp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${tmp}")
        while IFS=';' read -r status mac rest; do
            [[ "$status" != "a" || -z "$mac" ]] && continue
            local lc_mac
            lc_mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
            if echo "$MANAGED_MACS" | grep -q "^${lc_mac}$"; then
                log "INFO: clean_managed_macs → removed $mac from $(basename "$list")"
                queue_lease_removal "$mac"
                (( removed++ )) || true
            else
                echo "${status};${mac};${rest}" >> "$tmp"
            fi
        done < "$list"
        mv "$tmp" "$list" && chmod 600 "$list"
    done

    if (( removed > 0 )); then
        log "INFO: clean_managed_macs → done (removed $removed entries)"
    fi
}

# ── Step 4: sort ACL files by IP ─────────────────────────────────────────────
sort_acl_files() {
    local tmp

    if [[ -s "$MAC_LIST" ]]; then
        tmp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${tmp}")
        sort -t';' -k3,3V "$MAC_LIST" | uniq > "$tmp"
        mv "$tmp" "$MAC_LIST" && chmod 600 "$MAC_LIST"
    fi

    if [[ -s "$PENDING_LIST" ]]; then
        tmp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${tmp}")
        sort -t';' -k3,3V "$PENDING_LIST" | uniq > "$tmp"
        mv "$tmp" "$PENDING_LIST" && chmod 600 "$PENDING_LIST"
    fi
}

add_mac_to_acl() {
    local mac="$1" ip="$2" hostname="$3" end_time="$4"

    if [[ "$mac" == *';'* || "$ip" == *';'* || "$hostname" == *';'* || "$end_time" == *';'* ]]; then
        log "ERROR: Refusing ACL entry — field contains ';' (mac=$mac)"
        return 1
    fi

    local new_line="a;${mac};${ip};${hostname};${end_time};"

    if grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null; then
        sed -i "/^a;${mac};/Id" "$PENDING_LIST"
    fi

    if grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
        local existing_end
        existing_end=$(grep -i "^a;${mac};" "$MAC_LIST" | head -1 | awk -F';' '{print $5}')
        if [[ "$end_time" != "$existing_end" ]]; then
            local escaped_line
            escaped_line=$(printf '%s' "$new_line" | sed -e 's/[\&|/]/\\&/g')
            sed -i "s|^a;${mac};.*|${escaped_line}|I" "$MAC_LIST"
            log "INFO: Updated end_time for $mac ($existing_end → $end_time)"
        fi
    else
        queue_lease_removal "$mac"
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
        if ! iph=$(assign_ip_and_hostname); then
            log "WARNING: expire_to_pending: pool exhausted for $mac"
            return 1
        fi
        ip=$(echo "$iph"       | cut -d';' -f1)
        hostname=$(echo "$iph" | cut -d';' -f2)
    fi

    echo "a;${mac};${ip};${hostname};" >> "$PENDING_LIST"
    log "INFO: Expired $mac → guest-pending.txt ip=$ip hostname=$hostname"
}

# ── Step 6: clean expired MACs ────────────────────────────────────────────────
clean_expired_macs() {
    local now tmp
    now=$(date +%s)
    tmp=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${tmp}")

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local end_time mac
        end_time=$(echo "$line" | awk -F';' '{print $5}')
        mac=$(echo "$line"      | awk -F';' '{print $2}')
        if [[ -z "$end_time" ]] || (( now <= end_time )); then
            echo "$line" >> "$tmp"
        else
            log "INFO: Expired $mac at $(date -d "@$end_time" 2>/dev/null || echo "$end_time")"
            if ! expire_to_pending "$mac"; then
                log "WARNING: clean_expired_macs: keeping $mac (pool unavailable — will retry)"
                echo "$line" >> "$tmp"
            fi
        fi
    done < "$MAC_LIST"

    mv "$tmp" "$MAC_LIST" && chmod 600 "$MAC_LIST"
}

# ── Clean disconnected pending ────────────────────────────────────────────────
clean_disconnected_pending() {
    local sta_data="$1"
    [[ ! -s "$PENDING_LIST" ]] && return

    local active_macs
    active_macs=$(echo "$sta_data" | jq -r \
        --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.mac != null and .mac != "")
        | select(.essid == $essid)
        | (.mac | ascii_downcase)
    ' 2>/dev/null || true)

    if [[ -z "$active_macs" ]]; then
        log "INFO: clean_disconnected_pending: no active MACs — skipping"
        return
    fi

    local tmp removed=0
    tmp=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${tmp}")
    while IFS=';' read -r status mac ip hostname _; do
        [[ "$status" != "a" ]] && continue
        [[ -z "$mac" ]] && continue
        if echo "$active_macs" | grep -qi "^${mac}$"; then
            echo "${status};${mac};${ip};${hostname};" >> "$tmp"
        else
            log "INFO: Removed disconnected pending $mac"
            (( removed++ )) || true
        fi
    done < "$PENDING_LIST"
    mv "$tmp" "$PENDING_LIST" && chmod 600 "$PENDING_LIST"
}

# ── Step 7: process pending guests ───────────────────────────────────────────
# Detects clients connected to HOTSPOT_ESSID that are not yet in any ACL list
# and adds them to guest-pending.txt with a fixed IP from the hotspot range.
# MACs present in mac-*.txt (MANAGED_MACS) are silently skipped.
process_pending_guests() {
    local sta_data="$1"
    local rc
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    [[ "$rc" != "ok" ]] && { log "INFO: stat/sta unavailable — skipping pending"; return; }

    clean_disconnected_pending "$sta_data"

    local available_count=0 i
    for (( i=HOTSPOT_RANGE_START; i<=HOTSPOT_RANGE_END; i++ )); do
        local candidate="${HOTSPOT_IP_RANGE}.${i}"
        grep -q ";${candidate};" "$MAC_LIST"     2>/dev/null && continue
        grep -q ";${candidate};" "$PENDING_LIST" 2>/dev/null && continue
        (( available_count++ )) || true
    done

    if [[ $available_count -eq 0 ]]; then
        local oldest_line oldest_mac oldest_ip
        oldest_line=$(grep '^a;' "$PENDING_LIST" 2>/dev/null | sort -t';' -k3,3V | head -1 || true)
        oldest_mac=$(echo "$oldest_line" | awk -F';' '{print $2}')
        oldest_ip=$(echo "$oldest_line"  | awk -F';' '{print $3}')
        if [[ -n "$oldest_mac" && -n "$oldest_ip" ]]; then
            log "INFO: Range exhausted — evicting oldest pending $oldest_mac (ip=$oldest_ip)"
            sed -i "/^a;${oldest_mac};/Id" "$PENDING_LIST"
            queue_lease_removal "$oldest_mac"
        else
            log "WARNING: Range exhausted and no pending guest to evict — skipping"
            return
        fi
    fi

    local count=0
    while IFS=$'\t' read -r mac ip; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        grep -qi "^a;${mac};" "$MAC_LIST"     2>/dev/null && continue
        grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null && continue
        if echo "$MANAGED_MACS" | grep -qi "^${mac}$"; then
            continue
        fi
        local iph assigned_ip assigned_hostname
        iph=$(assign_ip_and_hostname) || continue
        assigned_ip=$(echo "$iph" | cut -d';' -f1)
        assigned_hostname=$(echo "$iph" | cut -d';' -f2)
        echo "a;${mac};${assigned_ip};${assigned_hostname};" >> "$PENDING_LIST"
        log "INFO: Pending guest $mac → ip=$assigned_ip hostname=$assigned_hostname (ssid=$HOTSPOT_ESSID)"
        queue_lease_removal "$mac"
        (( count++ )) || true
    done < <(echo "$sta_data" | jq -r \
        --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.mac != null and .mac != "")
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (.ip // "")]
        | join("\t")
    ' 2>/dev/null || true)

    PENDING_NEW=$count
}

# ── Step 8: process sessions ──────────────────────────────────────────────────
# Queries stat/guest. Promotes voucher-authenticated clients from guest-pending
# to mac-hotspot.txt. MACs in mac-*.txt are skipped even if they entered a voucher.
process_sessions() {
    local endpoint sessions_data rc added=0
    local now
    now=$(date +%s)

    endpoint=$(api_path "stat/guest")
    sessions_data=$(api_get "$endpoint")
    rc=$(echo "$sessions_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    [[ "$rc" != "ok" ]] && { log "INFO: stat/guest unavailable — skipping sessions"; return; }

    while IFS=$'\t' read -r mac end_time api_voucher_code; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        [[ -z "$end_time" || "$end_time" == "null" ]] && continue
        (( end_time <= now )) && continue

        if echo "$MANAGED_MACS" | grep -qi "^${mac}$"; then
            continue
        fi

        if grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
            local existing_end
            existing_end=$(grep -i "^a;${mac};" "$MAC_LIST" | head -1 | awk -F';' '{print $5}')
            [[ "$end_time" == "$existing_end" ]] && continue
        fi

        local assigned_ip="" assigned_hostname="" entry=""
        entry=$(grep -i "^a;${mac};" "$PENDING_LIST" 2>/dev/null | head -1 || true)
        assigned_hostname=$(echo "$entry" | awk -F';' '{print $4}')
        assigned_ip=$(echo "$entry"       | awk -F';' '{print $3}')

        if [[ -z "$assigned_ip" ]]; then
            local iph
            if ! iph=$(assign_ip_and_hostname); then
                log "WARNING: Range exhausted for $mac — will retry next cycle"
                continue
            fi
            assigned_ip=$(echo "$iph" | cut -d';' -f1)
            [[ -z "$assigned_hostname" ]] && assigned_hostname=$(echo "$iph" | cut -d';' -f2)
        fi
        [[ -z "$assigned_hostname" ]] && assigned_hostname="guest$(get_next_guest_number)"

        local voucher_code
        if [[ -n "$api_voucher_code" && "$api_voucher_code" != "null" ]]; then
            voucher_code="$api_voucher_code"
        else
            voucher_code=$(get_voucher_code_by_end_time "$end_time")
        fi
        if [[ -n "$voucher_code" ]]; then
            if [[ "$assigned_hostname" == *-* ]]; then
                assigned_hostname="${assigned_hostname%-*}-${voucher_code}"
            else
                assigned_hostname="${assigned_hostname}-${voucher_code}"
            fi
        fi

        if ! add_mac_to_acl "$mac" "$assigned_ip" "$assigned_hostname" "$end_time"; then
            continue
        fi
        (( added++ )) || true

    done < <(echo "$sessions_data" | jq -r '
        .data[]
        | select(.mac != null and .mac != "")
        | select(.end != null)
        | [(.mac | ascii_downcase), (.end | tostring), (.voucher_code // "")]
        | join("\t")
    ' 2>/dev/null || true)

    SESSIONS_AUTHORIZED=$added
}

# ── Step 9: revoke unauthorized ───────────────────────────────────────────────
revoke_unauthorized() {
    local sta_data="$1"
    local rc
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    [[ "$rc" != "ok" ]] && { log "INFO: stat/sta unavailable — skipping revoke"; return; }

    local revoked=0
    local macs_to_revoke=()

    while IFS=';' read -r status mac ip hostname end_time _; do
        [[ "$status" != "a" ]] && continue
        [[ -z "$mac" ]] && continue
        local authorized
        authorized=$(echo "$sta_data" | jq -r \
            --arg mac "$mac" '
            .data[]
            | select((.mac | ascii_downcase) == $mac)
            | .authorized
        ' 2>/dev/null | tail -1 || true)
        if [[ "$authorized" == "false" ]]; then
            macs_to_revoke+=("$mac")
        fi
    done < "$MAC_LIST"

    local mac
    for mac in "${macs_to_revoke[@]+"${macs_to_revoke[@]}"}"; do
        [[ -z "$mac" ]] && continue
        log "INFO: Revoking $mac — authorized=false in UniFi"
        if expire_to_pending "$mac"; then
            sed -i "/^a;${mac};/Id" "$MAC_LIST" 2>/dev/null || true
            (( revoked++ )) || true
        else
            log "WARNING: revoke_unauthorized: keeping $mac in mac-hotspot.txt (pending slot unavailable — will retry)"
        fi
    done

    REVOKED=$revoked
}

# ── Step 10: unauthorize pending ──────────────────────────────────────────────
unauthorize_pending() {
    local sta_data="$1"
    [[ ! -s "$PENDING_LIST" ]] && return
    local rc
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    [[ "$rc" != "ok" ]] && { log "WARNING: unauthorize_pending: stat/sta unavailable"; return; }

    while IFS=';' read -r status mac ip hostname _; do
        [[ "$status" != "a" ]] && continue
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
            log "INFO: Unauthorized $mac"
        else
            log "WARNING: Failed to unauthorize $mac (HTTP $http_code)"
        fi
    done < "$PENDING_LIST"
}

# ── Step 11: authorize managed MACs ──────────────────────────────────────────
# mac-*.txt (mac-unlimited, mac-proxy, etc.) clients now share HOTSPOT_ESSID
# with portal guests. UniFi's guest portal requires authorize-guest for ANY
# client on that SSID, regardless of iptables/ACL bypass rules — those only
# control routing/NAT, not whether UniFi shows the captive portal.
#
# This step scans stat/sta for managed MACs (mac-*.txt) that UniFi currently
# shows as unauthorized/absent on HOTSPOT_ESSID, and sends authorize-guest
# with a long duration so they stop seeing the portal. Re-checked every cycle
# so a MAC that reconnects (and UniFi forgets) gets re-authorized automatically.
authorize_managed_macs() {
    local sta_data="$1"
    [[ -z "$MANAGED_MACS" ]] && return
    local rc
    rc=$(echo "$sta_data" | jq -r '.meta.rc // empty' 2>/dev/null || true)
    [[ "$rc" != "ok" ]] && { log "INFO: stat/sta unavailable — skipping authorize_managed_macs"; return; }

    local authorized_count=0
    local mac

    while IFS= read -r mac; do
        [[ -z "$mac" ]] && continue

        local on_essid authorized
        on_essid=$(echo "$sta_data" | jq -r \
            --arg mac "$mac" --arg essid "$HOTSPOT_ESSID" '
            .data[]
            | select((.mac | ascii_downcase) == $mac)
            | select(.essid == $essid)
            | "yes"
        ' 2>/dev/null | head -1 || true)
        [[ "$on_essid" != "yes" ]] && continue

        authorized=$(echo "$sta_data" | jq -r \
            --arg mac "$mac" '
            .data[]
            | select((.mac | ascii_downcase) == $mac)
            | .authorized // false
        ' 2>/dev/null | head -1 || true)
        [[ "$authorized" == "true" ]] && continue

        local auth_url http_code
        auth_url=$(api_path "cmd/stamgr")
        http_code=$(api_post "$auth_url" \
            "{\"cmd\":\"authorize-guest\",\"mac\":\"${mac}\",\"minutes\":${MANAGED_AUTHORIZE_MINUTES}}")
        if [[ "$http_code" == "200" ]]; then
            log "INFO: authorize_managed_macs: authorized $mac (managed, minutes=${MANAGED_AUTHORIZE_MINUTES})"
            (( authorized_count++ )) || true
        else
            log "WARNING: authorize_managed_macs: failed to authorize $mac (HTTP $http_code)"
        fi
    done <<< "$MANAGED_MACS"

    MANAGED_AUTHORIZED=$authorized_count
}

# ── Step 12: backup ───────────────────────────────────────────────────────────
mac_hotspot_backup() {
    local wellknow_file current_macs new_macs merged_macs
    wellknow_file="$(dirname "$MAC_LIST")/guest-wellknow.txt"
    new_macs=$(awk -F';' '/^a;/{print $2}' "$MAC_LIST" | sort -u)

    if [[ ! -s "$wellknow_file" ]]; then
        merged_macs="$new_macs"
        log "INFO: mac_hotspot_backup: seeding guest-wellknow.txt"
    else
        current_macs=$(sort -u "$wellknow_file")
        merged_macs=$(printf '%s\n%s\n' "$current_macs" "$new_macs" | sort -u)
    fi

    echo "$merged_macs" | grep -v '^$' > "${wellknow_file}.tmp" \
        && mv "${wellknow_file}.tmp" "$wellknow_file" \
        && chmod 600 "$wellknow_file"

    if [[ -s "$BLOCK_DHCP" && -s "$wellknow_file" ]]; then
        local removed pattern_file
        pattern_file=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${pattern_file}")
        sed 's/.*/;\0;/' "$wellknow_file" > "$pattern_file"
        removed=$(grep -cFf "$pattern_file" "$BLOCK_DHCP" || true)
        if [[ $removed -gt 0 ]]; then
            grep -vFf "$pattern_file" "$BLOCK_DHCP" > "${BLOCK_DHCP}.tmp" \
                && mv "${BLOCK_DHCP}.tmp" "$BLOCK_DHCP"
            log "WARNING: mac_hotspot_backup: removed $removed entry/entries from blockdhcp.txt"
        fi
        rm -f "$pattern_file"
    fi
}

# ── ACL snapshot & reload ─────────────────────────────────────────────────────
snapshot_acls() {
    _ACL_SNAPSHOT_HOTSPOT=$(md5sum "$MAC_LIST"         2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_PENDING=$(md5sum "$PENDING_LIST"     2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_QUEUE=$(md5sum "$LEASE_REMOVE_QUEUE" 2>/dev/null | awk '{print $1}' || echo "absent")
}

# ── Step 13: reload if ACLs changed ──────────────────────────────────────────
check_and_reload_if_changed() {
    local cur_hotspot cur_pending cur_queue rc
    cur_hotspot=$(md5sum "$MAC_LIST"         2>/dev/null | awk '{print $1}' || echo "absent")
    cur_pending=$(md5sum "$PENDING_LIST"     2>/dev/null | awk '{print $1}' || echo "absent")
    cur_queue=$(md5sum "$LEASE_REMOVE_QUEUE" 2>/dev/null | awk '{print $1}' || echo "absent")

    if [[ "$cur_hotspot" == "$_ACL_SNAPSHOT_HOTSPOT" && \
          "$cur_pending" == "$_ACL_SNAPSHOT_PENDING"  && \
          "$cur_queue"   == "$_ACL_SNAPSHOT_QUEUE" ]]; then
        log "INFO: ACLs unchanged — skipping reload"
        return
    fi

    [[ "$cur_hotspot" != "$_ACL_SNAPSHOT_HOTSPOT" ]] && log "INFO: mac-hotspot.txt changed"
    [[ "$cur_pending"  != "$_ACL_SNAPSHOT_PENDING"  ]] && log "INFO: guest-pending.txt changed"
    [[ "$cur_queue"    != "$_ACL_SNAPSHOT_QUEUE"    ]] && log "INFO: lease removal queue changed"

    if [[ -n "${SERVER_RELOAD_SCRIPT:-}" && -x "$SERVER_RELOAD_SCRIPT" ]]; then
        log "INFO: ACL changed — invoking $SERVER_RELOAD_SCRIPT"
        export UHOTSPOT_RELOAD_ACTIVE=1
        timeout 60 "$SERVER_RELOAD_SCRIPT" >> "$LOG_FILE" 2>&1 \
            || { rc=$?; [[ $rc -eq 124 ]] \
                && log "WARNING: $SERVER_RELOAD_SCRIPT timed out after 60s" \
                || log "WARNING: $SERVER_RELOAD_SCRIPT exited with error (code $rc)"; }
        unset UHOTSPOT_RELOAD_ACTIVE
    else
        log "WARNING: ACLs changed but SERVER_RELOAD_SCRIPT is not set or not executable"
    fi
}



# ── Full hotspot cycle ────────────────────────────────────────────────────────
run_cycle() {
    PENDING_NEW=0
    SESSIONS_AUTHORIZED=0
    REVOKED=0
    MANAGED_AUTHORIZED=0

    load_all_vouchers
    dedup_mac_lists
    sort_acl_files
    snapshot_acls
    clean_managed_macs
    clean_expired_macs

    local sta_endpoint sta_data
    sta_endpoint=$(api_path "stat/sta")
    sta_data=$(api_get "$sta_endpoint")

    process_pending_guests "$sta_data"
    process_sessions
    revoke_unauthorized      "$sta_data"
    unauthorize_pending      "$sta_data"
    authorize_managed_macs   "$sta_data"
    mac_hotspot_backup
    check_and_reload_if_changed

    local pending_total authorized_total
    pending_total=$(grep -c "^a;" "$PENDING_LIST" 2>/dev/null || true)
    pending_total=$(( ${pending_total:-0} + 0 ))
    authorized_total=$(grep -c "^a;" "$MAC_LIST" 2>/dev/null || true)
    authorized_total=$(( ${authorized_total:-0} + 0 ))
    log "INFO: vouchers=$VOUCHER_COUNT | authorized=$authorized_total | pending=$pending_total | new_pending=$PENDING_NEW | new_auth=$SESSIONS_AUTHORIZED | revoked=$REVOKED | managed_authorized=$MANAGED_AUTHORIZED"
}

# ── Main daemon loop ──────────────────────────────────────────────────────────
main() {
    load_config
    POLL_INTERVAL="${POLL_INTERVAL:-10}"
    verify_installation
    init_acl_files

    echo "────────────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE" 2>/dev/null || true
    log "INFO: uhotspotd start"

    if ! unifi_login; then
        log "ERROR: Initial login failed — retrying in 30s"
        sleep 30
        unifi_login || { log "ERROR: Login retry failed — exiting"; exit 1; }
    fi

    while true; do
        run_cycle || log "WARNING: cycle ended with error — continuing"
        sleep "$POLL_INTERVAL"
    done
}

main "$@"
