#!/bin/bash
# maravento.com
#
################################################################################
#
# uhotspotd — UniFi Hotspot Manager Daemon
#
# DESCRIPTION:
#   Persistent systemd service for UniFi hotspot ACL management.
#   Runs a full management cycle every POLL_INTERVAL seconds (set in
#   uhotspot.conf, default 20) with a persistent UniFi API session and CSRF
#   token shared across all calls within a cycle.
#
#   Session tokens are persisted to TOKEN_STATE_FILE (/run/uhotspotd_session)
#   so that re-authentication inside $(...) subshells propagates correctly to
#   subsequent API calls in the same cycle.
#
#   MANAGED MACS (optional):
#   If /etc/acl/acl_mac/mac-*.txt files exist, MACs listed there are treated
#   as managed corporate devices. They are silently excluded from the guest
#   portal flow (steps 5, 7, 8, 9) and are kept authorized in UniFi (step 10)
#   so they bypass the captive portal on HOTSPOT_ESSID without needing a
#   voucher. If no mac-*.txt files exist, steps 5 and 10 are no-ops.
#
# CYCLE (every POLL_INTERVAL seconds, default 20, set in uhotspot.conf):
#   1. VOUCHERS    — load voucher cache from UniFi (stat/voucher)
#   2. SNAPSHOT    — md5sum baseline of ACL files before processing (taken
#                    before DEDUP so its blockdhcp.txt changes are detected
#                    by RELOAD, step 12)
#   3. DEDUP       — cross-list consistency check, blockdhcp cleanup
#   4. SORT        — sort mac-hotspot.txt by IP
#   5. CLEAN MACS  — remove mac-*.txt entries from mac-hotspot
#   6. EXPIRED     — remove expired mac-hotspot entries (hotspot IPs freed)
#   7. NEW LEASES  — scan pydhcpd.leases; any MAC not yet in mac-hotspot/
#                    mac-*/blockdhcp/gracedhcp/guest-wellknow is written
#                    directly into gracedhcp.txt with a first-seen timestamp —
#                    the same role guest-pending.txt played in the
#                    pre-simplification design. Unlike guest-pending.txt, no
#                    fixed hotspot-range IP is assigned and no lease removal
#                    is queued: grace clients keep their existing pydhcpd
#                    pool lease. Writing gracedhcp.txt is enough to trigger
#                    RELOAD (step 12), which invokes uleases.sh to do the
#                    actual classification/expiry/blocking of grace entries.
#   8. SESSIONS    — promote voucher-authenticated clients to mac-hotspot
#   9. REVOKE      — remove UniFi-unauthorized clients from mac-hotspot
#  10. AUTHORIZE   — re-authorize managed MACs (mac-*.txt) seen on HOTSPOT_ESSID
#                    that UniFi reports as unauthorized; checked every cycle so
#                    reconnecting devices are covered automatically
#  11. BACKUP      — update guest-wellknow.txt, clean blockdhcp conflicts
#  12. RELOAD      — invoke SERVER_RELOAD_SCRIPT if ACLs changed
#
# stat/sta is queried once per cycle and shared across steps 9, 10.
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

# CYCLE_LOCK is separate from SCRIPT_LOCK (the singleton instance guard, held
# for the daemon's entire lifetime). CYCLE_LOCK is only held while run_cycle
# is actively mutating ACL files (~1-3s), released during the sleep between
# cycles. uleases.sh's cron-triggered guard checks THIS lock, not SCRIPT_LOCK,
# so the cron reload isn't blocked for the daemon's entire uptime — only
# during the narrow window where a real race on the ACL files could occur.
CYCLE_LOCK="/var/lock/uhotspotd-cycle.lock"
exec 201>"$CYCLE_LOCK"

TEMP_FILES_TO_CLEAN=()
cleanup_temp() {
    local rc=$?
    local f
    for f in "${TEMP_FILES_TO_CLEAN[@]+"${TEMP_FILES_TO_CLEAN[@]}"}"; do
        rm -f "$f" 2>/dev/null || true
    done
    # Only skip the "done" announcement on an explicit error exit (exit 1) —
    # the ERROR line already logged is the signal that something happened.
    # A normal stop (systemctl stop sends SIGTERM, rc=143) is not that case
    # and must still log done. Uses log_raw, not log, so this line closes out
    # whatever was last logged instead of opening a delimiter block of its
    # own — a raya must mark the start of a cycle/session, never a shutdown.
    if (( rc != 1 )) && declare -F log_raw &>/dev/null; then
        log_raw "INFO: uhotspotd done"
    fi
}
trap cleanup_temp EXIT

# ── Paths & constants ─────────────────────────────────────────────────────────
LOG_FILE="/var/log/uhotspot.log"
HOTSPOT_PATH="/etc/uhotspot"
CONFIG_FILE="$HOTSPOT_PATH/uhotspot.conf"
ACL_MAC_PATH="/etc/acl/acl_mac"
MAC_LIST="$HOTSPOT_PATH/mac-hotspot.txt"
BLOCK_DHCP="/etc/acl/acl_dhcp/blockdhcp.txt"
LEASE_REMOVE_QUEUE="$HOTSPOT_PATH/leases-remove-queue.txt"
PYDHCPD_LEASES="/etc/pydhcp/pydhcpd.leases"

TOKEN_STATE_FILE="/run/uhotspotd_session"

# Minutes UniFi keeps a managed MAC (mac-*.txt) authorized on the guest portal.
# Re-sent periodically by authorize_managed_macs (step 10) well before expiry.
MANAGED_AUTHORIZE_MINUTES=527040   # 366 days

# ── Runtime state ─────────────────────────────────────────────────────────────
SESSION_TOKEN=""
CSRF_TOKEN=""
MANAGED_MACS=""
VOUCHER_CACHE=""
VOUCHER_COUNT=0
SESSIONS_AUTHORIZED=0
REVOKED=0
MANAGED_AUTHORIZED=0
_ACL_SNAPSHOT_HOTSPOT=""
_ACL_SNAPSHOT_BLOCK=""
_ACL_SNAPSHOT_QUEUE=""
_ACL_SNAPSHOT_GRACE=""

# ── Logging ───────────────────────────────────────────────────────────────────
# _CYCLE_MARKED tracks whether the delimiter line has already been printed
# for the current cycle. It starts at 0 (unset), so the very first log() call
# of the whole process (verify_installation's "Installation verified") prints
# it too — covering daemon startup with the same mechanism, no special case
# needed. run_cycle() resets it to 0 at the start of every loop iteration, so
# a cycle with no activity produces no delimiter and no lines at all; a cycle
# with any activity gets exactly one delimiter, right before its first line.
_CYCLE_MARKED=0
log() {
    if [[ "$_CYCLE_MARKED" != "1" ]]; then
        echo "────────────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE" 2>/dev/null || true
        _CYCLE_MARKED=1
    fi
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Same output format as log(), but never opens a delimiter block of its own.
# Used only for the shutdown notice (see cleanup_temp): that line closes out
# whatever was last logged in this process rather than starting a new one.
# The next process (a fresh uhotspotd start) still gets its own delimiter as
# usual, since _CYCLE_MARKED is a fresh variable in that new process.
log_raw() {
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
    if [[ "$_owner" != "root" ]] || [[ "$_gdigit" != "0" ]] || [[ "$_odigit" != "0" ]]; then
        echo "ERROR: $CONFIG_FILE has unsafe owner/permissions (owner=$_owner perms=$_perms) — must be owned by root with no group/other access (600)" >&2
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

    if [[ "${UNIFI_TYPE:-}" == "classic" ]]; then
        log "ERROR: UNIFI_TYPE=classic is not supported by this daemon (login uses TOKEN cookie, classic controllers use unifises). Set UNIFI_TYPE=unifi-os or use uaudit.sh for classic controllers."
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
    touch "$MAC_LIST" "$BLOCK_DHCP"
    chmod 600 "$MAC_LIST" "$BLOCK_DHCP"

    local grace_file="${ACL_GRACE_FILE:-/etc/acl/acl_dhcp/gracedhcp.txt}"
    mkdir -p "$(dirname "$grace_file")"
    touch "$grace_file"
    chmod 600 "$grace_file"
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
    ( umask 077; printf '%s\n%s\n' "$SESSION_TOKEN" "$CSRF_TOKEN" > "$TOKEN_STATE_FILE" ) 2>/dev/null || true
    chmod 600 "$TOKEN_STATE_FILE" 2>/dev/null || true
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
    new_tok=$(grep -iE '^set-cookie:[[:space:]]*TOKEN=' "$hfile" \
        | head -1 \
        | sed -E 's/^[^:]+:[[:space:]]*TOKEN=([^;]+).*/\1/' \
        | tr -d '\r\n' || true)
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
    # Pass username/password to jq via environment, not --arg, so the
    # plaintext password never appears in jq's own argv (readable by any
    # local user via /proc/<pid>/cmdline). Environment is only readable by
    # the same user or root (/proc/<pid>/environ).
    payload=$(UH_JQ_USER="$UNIFI_USERNAME" UH_JQ_PASS="$UNIFI_PASSWORD" jq -n \
        '{username: env.UH_JQ_USER, password: env.UH_JQ_PASS}')

    # Body goes to curl via stdin (--data-binary @-), not -d, for the same
    # reason: -d "$payload" would put the password in curl's argv too.
    http_code=$(curl -sk \
        -D "$header_file" \
        -o /dev/null \
        -w "%{http_code}" \
        -X POST "$login_url" \
        -H "Content-Type: application/json" \
        --data-binary @- \
        --connect-timeout 10 --max-time 40 <<< "$payload" || echo "000")

    if [[ "$http_code" != "200" ]]; then
        log "ERROR: UniFi login failed (HTTP $http_code)"
        rm -f "$header_file"
        return 1
    fi

    local new_csrf new_tok
    new_tok=$(grep -iE '^set-cookie:[[:space:]]*TOKEN=' "$header_file" \
        | head -1 \
        | sed -E 's/^[^:]+:[[:space:]]*TOKEN=([^;]+).*/\1/' \
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
        VOUCHER_COUNT=0
        return
    fi
    count=$(echo "$VOUCHER_CACHE" | jq '.data | length' 2>/dev/null || echo 0)
    VOUCHER_COUNT="$count"
}

# ── IP/hostname assignment ────────────────────────────────────────────────────
get_next_guest_number() {
    local used n=1 max_n
    max_n=$(( HOTSPOT_RANGE_END - HOTSPOT_RANGE_START + 2 ))
    used=$(grep -oh 'guest[0-9]*' "$MAC_LIST" 2>/dev/null \
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
        grep -q ";${candidate};" "$MAC_LIST" 2>/dev/null && continue
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
    if grep -qxF "$lc_mac" "$LEASE_REMOVE_QUEUE" 2>/dev/null; then
        return 0
    fi
    if echo "$lc_mac" >> "$LEASE_REMOVE_QUEUE" 2>/dev/null; then
        log "INFO: Queued lease removal for $lc_mac"
        return 0
    fi
    log "WARNING: queue_lease_removal: failed to write $lc_mac to $LEASE_REMOVE_QUEUE"
    return 1
}

# ── Step 3: MAC list deduplication ───────────────────────────────────────────
dedup_mac_lists() {
    # Populated from whatever mac-*.txt files exist in ACL_MAC_PATH. Stays
    # empty if none are present, in which case clean_managed_macs and
    # authorize_managed_macs are no-ops (both check
    # [[ -z "$MANAGED_MACS" ]] && return at their entry point).
    MANAGED_MACS=$(
        {
            for f in "$ACL_MAC_PATH"/mac-*.txt; do
                [[ -f "$f" ]] && grep -ih '^a;' "$f" 2>/dev/null || true
            done
        } | awk -F';' '{print tolower($2)}' \
          | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' \
          | sort -u || true
    )

    local all_macs
    all_macs=$(
        {
            awk -F';' '/^a;/{print tolower($2)}' "$MAC_LIST" 2>/dev/null || true
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
        local after_lines
        after_lines=$(wc -l < "$tmp_block" 2>/dev/null || echo -1)
        if (( after_lines < 0 )); then
            log "ERROR: dedup_mac_lists: failed to validate temp file — skipping blockdhcp update"
            rm -f "$tmp_block"
        else
            mv "$tmp_block" "$BLOCK_DHCP" && chmod 600 "$BLOCK_DHCP"
        fi
    fi

    if (( sanitized_block > 0 )); then
        log "INFO: dedup → sanitized $sanitized_block blockdhcp entries"
    fi
}

# ── Step 5: clean managed MACs from hotspot lists ─────────────────────────────
# Removes any MAC present in mac-*.txt from mac-hotspot.
clean_managed_macs() {
    [[ -z "$MANAGED_MACS" ]] && return
    local removed=0 tmp

    for list in "$MAC_LIST"; do
        [[ ! -f "$list" ]] && continue
        local before_count=0
        before_count=$(grep -c '^a;' "$list" 2>/dev/null); before_count=$(( ${before_count:-0} + 0 ))
        local iter_removed=0
        tmp=$(mktemp)
        TEMP_FILES_TO_CLEAN+=("${tmp}")
        while IFS= read -r _line; do
            IFS=';' read -r status mac rest <<< "$_line"
            if [[ "$status" != "a" || -z "$mac" ]]; then
                echo "$_line" >> "$tmp"
                continue
            fi
            local lc_mac
            lc_mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
            if echo "$MANAGED_MACS" | grep -q "^${lc_mac}$"; then
                log "INFO: clean_managed_macs → removed $mac from $(basename "$list")"
                queue_lease_removal "$mac"
                (( iter_removed++ )) || true
                (( removed++ )) || true
            else
                echo "${status};${mac};${rest}" >> "$tmp"
            fi
        done < "$list"
        local after_count
        after_count=$(grep -c '^a;' "$tmp" 2>/dev/null); after_count=$(( ${after_count:-0} + 0 ))
        if (( before_count - after_count != iter_removed )); then
            log "ERROR: clean_managed_macs: count mismatch on $(basename "$list") (before=$before_count after=$after_count removed=$iter_removed) — skipping"
            rm -f "$tmp"
            continue
        fi
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
}

add_mac_to_acl() {
    local mac="$1" ip="$2" hostname="$3" end_time="$4"

    if [[ ! "$mac" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$ ]]; then
        log "ERROR: add_mac_to_acl: refusing malformed MAC '$mac' — not added"
        return 1
    fi

    if [[ "$ip" == *';'* || "$hostname" == *';'* || "$end_time" == *';'* ]]; then
        log "ERROR: Refusing ACL entry — field contains ';' (mac=$mac)"
        return 1
    fi

    local new_line="a;${mac};${ip};${hostname};${end_time};"

    if grep -qi "^a;${mac};" "$MAC_LIST" 2>/dev/null; then
        local existing_end
        existing_end=$(grep -i "^a;${mac};" "$MAC_LIST" | head -1 | awk -F';' '{print $5}')
        if [[ "$end_time" != "$existing_end" ]]; then
            local escaped_line
            escaped_line=$(printf '%s' "$new_line" | sed -e 's/[\&|/]/\\&/g')
            if ! sed -i "s|^a;${mac};.*|${escaped_line}|I" "$MAC_LIST"; then
                log "ERROR: Failed to update end_time for $mac in $MAC_LIST (sed -i failed)"
                return 1
            fi
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

expire_from_hotspot() {
    local mac="$1"
    # Release the hotspot-range IP. On reconnect, uleases.sh detects the client
    # via pydhcpd.leases; if the MAC is in guest-wellknow.txt the lease is kept
    # without a new grace timer, otherwise the client enters gracedhcp.txt.
    if ! queue_lease_removal "$mac"; then
        log "WARNING: Expire $mac — failed to queue lease removal, will retry"
        return 1
    fi
    log "INFO: Expired $mac — released from mac-hotspot.txt"
    return 0
}

# ── Step 6: clean expired MACs ────────────────────────────────────────────────
clean_expired_macs() {
    local now tmp
    now=$(date +%s)
    tmp=$(mktemp)
    TEMP_FILES_TO_CLEAN+=("${tmp}")

    local before_count=0
    before_count=$(grep -c '^a;' "$MAC_LIST" 2>/dev/null); before_count=$(( ${before_count:-0} + 0 ))
    local moved=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local end_time mac
        end_time=$(echo "$line" | awk -F';' '{print $5}')
        mac=$(echo "$line"      | awk -F';' '{print $2}')
        if [[ -z "$end_time" ]] || (( now <= end_time )); then
            echo "$line" >> "$tmp"
        else
            log "INFO: Expired $mac at $(date -d "@$end_time" 2>/dev/null || echo "$end_time")"
            if ! expire_from_hotspot "$mac"; then
                log "WARNING: clean_expired_macs: keeping $mac — will retry"
                echo "$line" >> "$tmp"
            else
                (( moved++ )) || true
            fi
        fi
    done < "$MAC_LIST"

    local after_count
    after_count=$(grep -c '^a;' "$tmp" 2>/dev/null); after_count=$(( ${after_count:-0} + 0 ))
    if (( before_count - after_count != moved )); then
        log "ERROR: clean_expired_macs: count mismatch (before=$before_count after=$after_count moved=$moved) — skipping"
        rm -f "$tmp"
        return
    fi
    mv "$tmp" "$MAC_LIST" && chmod 600 "$MAC_LIST"
}

# ── Step 7: detect new clients in pydhcpd.leases ──────────────────────────────
# Plays the role guest-pending.txt used to play in the pre-simplification
# design: scans pydhcpd.leases for MACs that aren't yet known to any ACL
# source (mac-hotspot, mac-*, blockdhcp, gracedhcp, guest-wellknow) and writes
# them straight into gracedhcp.txt with a first-seen timestamp.
#
# Unlike the old guest-pending.txt flow, no fixed hotspot-range IP is assigned
# here and no lease removal is queued — gracedhcp clients keep their existing
# pydhcpd pool lease until they enter a voucher or their grace timer expires
# (handled by uleases.sh). Writing gracedhcp.txt is enough to be picked up by
# the snapshot taken in step 2, so check_and_reload_if_changed (step 12)
# detects the change and triggers SERVER_RELOAD_SCRIPT, which runs uleases.sh
# to do the actual classification/expiry/blocking of grace entries.
process_new_leases() {
    [[ ! -f "$PYDHCPD_LEASES" ]] && return

    local grace_file wellknow_file
    grace_file="${ACL_GRACE_FILE:-/etc/acl/acl_dhcp/gracedhcp.txt}"
    wellknow_file="$(dirname "$MAC_LIST")/guest-wellknow.txt"

    local added=0
    local current_lease="" lease_content=""

    while IFS= read -r line; do
        if echo "$line" | grep -qE '^lease ((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?) \{$'; then
            current_lease="$line"
            lease_content="$line"$'\n'
            continue
        fi
        [[ -n "$current_lease" ]] && lease_content+="$line"$'\n'

        if [[ "$line" == "}" && -n "$current_lease" ]]; then
            local mac ip host
            mac=$(echo "$lease_content" | grep -oiE '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -1 | tr '[:upper:]' '[:lower:]')
            ip=$(echo "$lease_content" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
            host=$(echo "$lease_content" | grep -oE 'client-hostname "[^"]+"' | cut -d'"' -f2 | tr ' ' '_')
            host=$(echo "$host" | tr -cd 'A-Za-z0-9._-' | cut -c1-63)
            [[ -z "$host" ]] && host="no_name_$(head -c100 /dev/urandom | sha1sum | head -c10)"

            if [[ -n "$mac" && -n "$ip" ]] \
               && ! grep -qi "^a;${mac};" "$MAC_LIST"   2>/dev/null \
               && ! grep -qi "^a;${mac};" "$BLOCK_DHCP" 2>/dev/null \
               && ! grep -qi "^a;${mac};" "$grace_file" 2>/dev/null \
               && ! grep -qxiF "$mac" "$wellknow_file"  2>/dev/null \
               && ! echo "$MANAGED_MACS" | grep -qi "^${mac}$"; then
                echo "a;${mac};${ip};${host};$(date +%s);" >> "$grace_file"
                log "INFO: New client $mac ip=$ip hostname=$host → gracedhcp.txt"
                (( added++ )) || true
            fi
            current_lease=""
            lease_content=""
        fi
    done < "$PYDHCPD_LEASES"

    if (( added > 0 )); then
        chmod 600 "$grace_file" 2>/dev/null || true
        log "INFO: process_new_leases → added $added new client(s) to gracedhcp.txt"
    fi
}

# ── Step 8: process sessions ──────────────────────────────────────────────────
# Queries stat/guest. Promotes voucher-authenticated clients to mac-hotspot.txt.
# MACs in mac-*.txt are skipped even if they entered a voucher.
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
            local existing_line existing_ip existing_hostname existing_end
            existing_line=$(grep -i "^a;${mac};" "$MAC_LIST" | head -1)
            existing_ip=$(echo "$existing_line" | awk -F';' '{print $3}')
            existing_hostname=$(echo "$existing_line" | awk -F';' '{print $4}')
            existing_end=$(echo "$existing_line" | awk -F';' '{print $5}')
            [[ "$end_time" == "$existing_end" ]] && continue

            # Renewal of an already-authorized MAC (e.g. an admin manually
            # extended the voucher's end time from the UniFi UI, or any
            # other integration that updates an existing guest session).
            # The IP and hostname it was assigned when the voucher was
            # first redeemed must not change for as long as it stays
            # authorized — only the expiration time is updated.
            # assign_ip_and_hostname() is never called here since no new
            # IP is needed.
            log "INFO: process_sessions: renewal detected for $mac (end_time $existing_end -> $end_time) — keeping ip=$existing_ip hostname=$existing_hostname"
            if add_mac_to_acl "$mac" "$existing_ip" "$existing_hostname" "$end_time"; then
                (( added++ )) || true
            fi
            continue
        fi

        local assigned_ip="" assigned_hostname=""
        local iph
        if ! iph=$(assign_ip_and_hostname); then
            log "WARNING: Range exhausted for $mac — will retry next cycle"
            continue
        fi
        assigned_ip=$(echo "$iph" | cut -d';' -f1)
        assigned_hostname=$(echo "$iph" | cut -d';' -f2)

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
        ' 2>/dev/null | head -1 || true)
        if [[ "$authorized" == "false" ]]; then
            macs_to_revoke+=("$mac")
        fi
    done < "$MAC_LIST"

    local mac
    for mac in "${macs_to_revoke[@]+"${macs_to_revoke[@]}"}"; do
        [[ -z "$mac" ]] && continue
        if [[ ! "$mac" =~ ^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$ ]]; then
            log "ERROR: revoke_unauthorized: refusing malformed MAC '$mac' — skipping"
            continue
        fi
        log "INFO: Revoking $mac — authorized=false in UniFi; releasing from mac-hotspot"
        queue_lease_removal "$mac"
        if sed -i "/^a;${mac};/Id" "$MAC_LIST" 2>/dev/null; then
            (( revoked++ )) || true
        else
            log "WARNING: revoke_unauthorized: sed failed to remove $mac from $MAC_LIST — will retry next cycle"
        fi
    done

    REVOKED=$revoked
}

# ── Step 10: authorize managed MACs ──────────────────────────────────────────
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

# ── Step 11: backup ───────────────────────────────────────────────────────────
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

# ── Step 2: ACL snapshot (baseline for reload detection) ─────────────────────
snapshot_acls() {
    local grace_file="${ACL_GRACE_FILE:-/etc/acl/acl_dhcp/gracedhcp.txt}"
    _ACL_SNAPSHOT_HOTSPOT=$(md5sum "$MAC_LIST"          2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_BLOCK=$(md5sum   "$BLOCK_DHCP"        2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_QUEUE=$(md5sum   "$LEASE_REMOVE_QUEUE" 2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_GRACE=$(md5sum   "$grace_file"         2>/dev/null | awk '{print $1}' || echo "absent")
}

# ── Step 12: reload if ACLs changed ──────────────────────────────────────────
# Returns 0 if ACLs changed (reload attempted), 1 if unchanged (silent — no
# log noise on the common no-change path). Callers use the return code to
# decide whether the per-cycle summary line is worth logging.
check_and_reload_if_changed() {
    local grace_file="${ACL_GRACE_FILE:-/etc/acl/acl_dhcp/gracedhcp.txt}"
    local cur_hotspot cur_block cur_queue cur_grace rc
    cur_hotspot=$(md5sum "$MAC_LIST"          2>/dev/null | awk '{print $1}' || echo "absent")
    cur_block=$(md5sum   "$BLOCK_DHCP"        2>/dev/null | awk '{print $1}' || echo "absent")
    cur_queue=$(md5sum   "$LEASE_REMOVE_QUEUE" 2>/dev/null | awk '{print $1}' || echo "absent")
    cur_grace=$(md5sum   "$grace_file"         2>/dev/null | awk '{print $1}' || echo "absent")

    if [[ "$cur_hotspot" == "$_ACL_SNAPSHOT_HOTSPOT" && \
          "$cur_block"   == "$_ACL_SNAPSHOT_BLOCK"   && \
          "$cur_queue"   == "$_ACL_SNAPSHOT_QUEUE"   && \
          "$cur_grace"   == "$_ACL_SNAPSHOT_GRACE" ]]; then
        return 1
    fi

    [[ "$cur_hotspot" != "$_ACL_SNAPSHOT_HOTSPOT" ]] && log "INFO: mac-hotspot.txt changed"
    [[ "$cur_block"   != "$_ACL_SNAPSHOT_BLOCK"   ]] && log "INFO: blockdhcp.txt changed"
    [[ "$cur_queue"   != "$_ACL_SNAPSHOT_QUEUE"   ]] && log "INFO: lease removal queue changed"
    [[ "$cur_grace"   != "$_ACL_SNAPSHOT_GRACE"   ]] && log "INFO: gracedhcp.txt changed"

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
    return 0
}



# ── Full hotspot cycle ────────────────────────────────────────────────────────
run_cycle() {
    _CYCLE_MARKED=0

    if ! flock -n 201; then
        log "WARNING: cycle lock held unexpectedly — skipping this cycle"
        return
    fi

    SESSIONS_AUTHORIZED=0
    REVOKED=0
    MANAGED_AUTHORIZED=0

    load_all_vouchers
    snapshot_acls
    dedup_mac_lists
    sort_acl_files
    clean_managed_macs
    clean_expired_macs
    process_new_leases

    local sta_endpoint sta_data
    sta_endpoint=$(api_path "stat/sta")
    sta_data=$(api_get "$sta_endpoint")

    process_sessions
    revoke_unauthorized    "$sta_data"
    authorize_managed_macs "$sta_data"
    mac_hotspot_backup

    # Summary line is only useful when something actually changed this cycle —
    # logging it unconditionally at POLL_INTERVAL cadence (default 20s) drowns
    # the log in identical lines during idle periods.
    if check_and_reload_if_changed; then
        local authorized_total grace_total
        authorized_total=$(grep -c "^a;" "$MAC_LIST" 2>/dev/null || true)
        authorized_total=$(( ${authorized_total:-0} + 0 ))
        grace_total=$(grep -c "^a;" "${ACL_GRACE_FILE:-/etc/acl/acl_dhcp/gracedhcp.txt}" 2>/dev/null || true)
        grace_total=$(( ${grace_total:-0} + 0 ))
        log "INFO: vouchers=$VOUCHER_COUNT | authorized=$authorized_total | grace=$grace_total | new_auth=$SESSIONS_AUTHORIZED | revoked=$REVOKED | managed_authorized=$MANAGED_AUTHORIZED"
    fi

    flock -u 201
}

# ── Main daemon loop ──────────────────────────────────────────────────────────
main() {
    load_config
    POLL_INTERVAL="${POLL_INTERVAL:-20}"
    verify_installation
    init_acl_files

    log "INFO: uhotspotd start..."

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
