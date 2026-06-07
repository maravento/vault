#!/bin/bash
# maravento.com
#
################################################################################
#
# UniFi Network Hotspot - ACL Manager v4
#
# USAGE:
#   Manual : sudo /etc/uhotspot/uhotspot.sh
#   Cron   : registered by usetup.sh (every 30 seconds)
#            * * * * * /etc/uhotspot/uhotspot.sh; sleep 30 && /etc/uhotspot/uhotspot.sh
#
# DEPENDENCIES:
#   jq, curl, bash, UniFi Controller, pydhcpd
#
#   Indirect (used by uiptables.sh, not by this script):
#     iptables, ipset
#
# CHANGES:
#   - Configuration delegated to usetup.sh (installer). uhotspot.conf is
#     generated interactively during installation and sourced at runtime.
#     uhotspot.sh never prompts the user or writes uhotspot.conf.
#   - verify_installation() validates filesystem state (uhotspot.conf,
#     SERVER_RELOAD_SCRIPT) before the main loop. Exits with actionable
#     error messages if anything is missing or misconfigured.
#   - DHCP server pydhcpd is required. Script aborts if pydhcpd is not active.
#   - Crontab entry registered by usetup.sh (installer).
#   - LOG_FILE declared at bootstrap so all messages (including pre-main
#     validations) are captured in a single log.
#   - dedup_mac_lists: uses two internal scopes:
#       MANAGED_MACS (global) — only MACs from /etc/acl/acl_mac/mac-*.txt,
#         used to block portal entry for clients already managed by uleases.
#       all_macs (local) — all lists combined, used to clean blockdhcp.txt.
#   - Lease removal is queue-based: uhotspot.sh never modifies
#     pydhcpd.leases directly (pydhcpd may be writing to it). Instead,
#     queue_lease_removal() appends a MAC to leases-remove-queue.txt only on
#     a real state transition (new pending, eviction, or move to hotspot).
#     uleases.sh drains this queue during its safe stop→modify→start cycle.
#   - process_pending_guests and process_sessions: double verification against
#     MANAGED_MACS — a MAC present in /etc/acl/acl_mac/mac-*.txt is never
#     added to guest-pending.txt or mac-hotspot.txt, regardless of what the
#     UniFi API reports or whether the client forces a portal URL.
#   - Log format standardized with visual separators for readability:
#
#     ────────────────────────────────────────────────────────────────────────────────
#     2026-05-27 09:42:01 INFO: DHCP server detected — pydhcpd
#     2026-05-27 09:42:01 INFO: uhotspot Start. Wait...
#     2026-05-27 09:42:01 INFO: UniFi login OK
#     2026-05-27 09:42:02 INFO: ACLs unchanged — skipping reload
#     2026-05-27 09:42:02 INFO: vouchers=2 | authorized=14 | pending=2 | new_pending=0 | new_auth=0 | revoked=0
#     2026-05-27 09:42:02 INFO: Done
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
# MOBILE DEVICE LIMITATIONS (Android / iOS):
#   When UNIFI_HOTSPOT_ENABLED=true and DHCP option 252 (WPAD) is active,
#   Android and iOS clients on the guest SSID have the following constraints:
#
#   - WPAD (option 252): Neither Android nor iOS supports DHCP option 252.
#     Proxy must be configured manually on each device (host and port).
#
#   - Captive portal detection: Android sends probes to
#     connectivitycheck.gstatic.com; iOS sends probes to captive.apple.com.
#     If these probes are intercepted, blocked, or return an unexpected
#     response, the device reports "connected without internet" even when
#     actual connectivity works. To avoid this, add these domains to the
#     Squid whitelist without authentication requirements.
#
#   - App proxy bypass: On Android and iOS, most apps (YouTube, WhatsApp,
#     etc.) ignore the system proxy and open direct connections. Without
#     SSL bump or a VPN, direct HTTPS traffic cannot be intercepted.
#     Only browsers reliably honor the manually configured proxy.
#
#   - MAC randomization: Android 10+ and iOS 14+ randomize the MAC address
#     per network by default. A randomized MAC will never match an ACL entry,
#     so the device will be treated as an unauthorized client on every
#     connection. Users must disable MAC randomization for the guest SSID
#     before connecting, so the real hardware MAC is used and registered.
#
#   None of the above are defects in uhotspot.sh or dhcp.
#
# LOGIC:
#   The script runs every 30 seconds via cron and executes 9 steps:
#
#   1. DEDUP: verifies consistency across all ACL lists. MACs present in
#      guest-pending.txt, mac-hotspot.txt, or /etc/acl/acl_mac/mac-*.txt
#      are removed from blockdhcp.txt. A MAC cannot belong to more than one
#      list simultaneously. Entries in blockdhcp.txt with extra fields are
#      sanitized to the canonical 4-field format (a;MAC;IP;HOSTNAME;).
#
#   2. SNAPSHOT: records md5sum baselines of mac-hotspot.txt and
#      guest-pending.txt before any processing begins.
#
#   3. EXPIRED: iterates over mac-hotspot.txt looking for expired vouchers
#      (END_TIME < now). Moves them to guest-pending.txt preserving IP and
#      hostname, provided the client is still connected to the guest SSID.
#
#   4. PENDING: queries stat/sta on the UniFi API. Clients connected to the
#      guest SSID without authorization receive a sequential IP from the
#      user-defined range (e.g., 192.168.10.160 to 192.168.10.180) starting
#      from the lowest available IP. Their initial dynamic DHCP lease is
#      queued for removal. Hostname is constructed as guest{sequential_number}
#      and enriched with the voucher code in step 5. Example: guest5.
#      If the IP range is exhausted, the oldest entry in guest-pending.txt
#      is evicted (its lease queued for removal) to free one slot before
#      assigning. Clients already present in /etc/acl/acl_mac/mac-*.txt are
#      skipped — they have a fixed-address lease and must not enter the portal.
#
#   5. SESSIONS: queries stat/guest. UniFi records completed voucher sessions
#      here after the client authenticates. Clients are moved from
#      guest-pending.txt to mac-hotspot.txt with their end_time, and the
#      hostname is enriched with the voucher code (e.g. guest5-4652724159).
#      Clients already present in /etc/acl/acl_mac/mac-*.txt are skipped —
#      even if they force a portal URL and enter a voucher, they will never
#      be added to mac-hotspot.txt.
#
#   6. REVOKE: queries stat/sta. MACs present in mac-hotspot.txt that UniFi
#      reports as authorized=false are moved back to guest-pending.txt.
#
#   7. UNAUTHORIZE: sends an unauthorize-guest command to UniFi via
#      cmd/stamgr for any MAC in guest-pending.txt that still appears as
#      authorized=true in stat/sta.
#
#   8. BACKUP: merges all MAC addresses from mac-hotspot.txt into
#      guest-wellknow.txt using a cumulative sort -u (MACs are only added,
#      never removed). On first run the file is seeded from mac-hotspot.txt.
#      After each merge, any MAC present in guest-wellknow.txt that also
#      appears in blockdhcp.txt is removed from blockdhcp.txt, since a
#      known trusted client must not be permanently blocked.
#
#   9. RELOAD: compares the current state of mac-hotspot.txt and
#      guest-pending.txt against the baselines taken in step 2. If either
#      file changed, SERVER_RELOAD_SCRIPT is invoked exactly once to
#      restart DHCP, iptables, and related services.
#
# ACL FORMAT:
#   mac-hotspot.txt   → a;MAC;IP;HOSTNAME;END_TIME_EPOCH;
#   guest-pending.txt → a;MAC;IP;HOSTNAME;
#   guest-wellknow.txt → MAC
#
# HOSTNAME FORMAT:
#   guest{sequential_number} (assigned in PENDING step)
#   guest{sequential_number}-{voucher_code} (enriched in SESSIONS step)
#   Example: guest5-4652724159
#
# IP ASSIGNMENT:
#   Sequential within user-defined range, lowest available first
#
# UNIFI SITE:
#   UniFi always creates a site named "default" and this script uses it.
#   If the administrator renamed the site in the UniFi controller, edit
#   UNIFI_SITE in uhotspot.conf to match the exact name shown there.
#
# COOKIE NOTE:
#   UniFi OS uses a JWT cookie with the "partitioned" flag, which curl's
#   Netscape cookie jar discards. The TOKEN value is extracted from the
#   set-cookie header and injected manually in every request.
#
# DISCLAIMER:
#   Distributed without warranty. Use at your own risk.
#   Always test in a controlled environment before production.
#
################################################################################

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

# Log file (declared early so all bootstrap messages are captured)
LOG_FILE="/var/log/uhotspot.log"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    local msg
    msg="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$msg"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Hotspot path
HOTSPOT_PATH="/etc/uhotspot"

# ─── Configuration ────────────────────────────────────────────────────────────
# SESSION_TOKEN: stores the raw JWT extracted from the set-cookie header.
# curl's Netscape cookie jar silently drops cookies with the "partitioned"
# flag (used by UniFi OS >= 3.x). The token is injected manually instead.
CONFIG_FILE="$HOTSPOT_PATH/uhotspot.conf"
SESSION_TOKEN=""
MAC_LIST="$HOTSPOT_PATH/mac-hotspot.txt"
PENDING_LIST="$HOTSPOT_PATH/guest-pending.txt"
PENDING_NEW=0
SESSIONS_AUTHORIZED=0
REVOKED=0

# ─── Permanent MAC block list ─────────────────────────────────────────────────
# ACL file for MAC addresses that must be permanently denied a DHCP lease.
# Format: a;MAC;IP;HOSTNAME;   (4 fields — no epoch; trailing semicolon required)
BLOCK_DHCP="/etc/acl/acl_dhcp/blockdhcp.txt"

# ─── Lease removal queue (consumed by uleases.sh) ───────────────────────────
# MACs written here are removed from pydhcpd.leases by uleases.sh during its
# safe stop→modify→start cycle. One MAC per line, lowercase.
LEASE_REMOVE_QUEUE="$HOTSPOT_PATH/leases-remove-queue.txt"

# ─── Shared ACL MAC path (also used by uleases) ─────────────────────────────
# MACs in any mac-*.txt here must not appear in mac-hotspot.txt or guest-pending.txt.
ACL_MAC_PATH="/etc/acl/acl_mac"

# ─── DHCP backend requirement check ──────────────────────────────────────────
echo "────────────────────────────────────────────────────────────────────────────────" >> "$LOG_FILE" 2>/dev/null || true
if ! systemctl is-active --quiet pydhcpd 2>/dev/null; then
    log "WARNING: pydhcpd is not active — install and start pydhcpd"
    exit 1
fi
log "INFO: DHCP server detected — pydhcpd"

CSRF_TOKEN=""
VOUCHER_CACHE=""
VOUCHER_COUNT=0
MANAGED_MACS=""

# ─── Load config ──────────────────────────────────────────────────────────────
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: $CONFIG_FILE not found. Run usetup.sh first." >&2
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

    if (( ${#missing[@]} > 0 )); then
        log "ERROR: Missing required variables in $CONFIG_FILE: ${missing[*]}"
        log "ERROR: Edit $CONFIG_FILE and set the missing values, then re-run the script"
        exit 1
    fi

}

# ─── Verify installation integrity ───────────────────────────────────────────
# Defense-in-depth validation after config is loaded. Catches filesystem and
# configuration problems with actionable error messages before the main loop.
verify_installation() {
    local missing=0

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: $CONFIG_FILE not found. Run 'sudo usetup.sh' first." >&2
        missing=1
    fi

    if [[ ! -f "${SERVER_RELOAD_SCRIPT:-}" ]]; then
        echo "ERROR: Reload script not found: ${SERVER_RELOAD_SCRIPT:-unset}" >&2
        echo "       Run 'sudo usetup.sh' to fix." >&2
        missing=1
    elif [[ ! -x "$SERVER_RELOAD_SCRIPT" ]]; then
        echo "ERROR: Reload script not executable: $SERVER_RELOAD_SCRIPT" >&2
        echo "       Run: chmod +x $SERVER_RELOAD_SCRIPT" >&2
        missing=1
    fi

    if [[ -z "${HOTSPOT_ESSID:-}" ]]; then
        echo "ERROR: HOTSPOT_ESSID not set in $CONFIG_FILE" >&2
        missing=1
    fi

    if [[ -z "${UNIFI_CONTROLLER_URL:-}" ]]; then
        echo "ERROR: UNIFI_CONTROLLER_URL not set in $CONFIG_FILE" >&2
        missing=1
    fi

    if (( missing )); then
        exit 1
    fi

    log "INFO: Installation verified — config and scripts found"
}

# ─── ACL file init ────────────────────────────────────────────────────────────
init_acl_files() {
    mkdir -p "$(dirname "$MAC_LIST")" "$(dirname "$LOG_FILE")" "$(dirname "$BLOCK_DHCP")"
    touch "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"
    chmod 600 "$MAC_LIST" "$PENDING_LIST" "$BLOCK_DHCP"
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
    local login_url header_file http_code raw_cookie payload

    if [[ "$UNIFI_TYPE" == "unifi-os" ]]; then
        login_url="${UNIFI_CONTROLLER_URL}/api/auth/login"
    else
        login_url="${UNIFI_CONTROLLER_URL}/api/login"
    fi

    header_file=$(mktemp)
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
        log "ERROR: UniFi login failed (HTTP $http_code) at $login_url"
        rm -f "$header_file"
        return 1
    fi

    CSRF_TOKEN=$(grep -i 'x-updated-csrf-token\|x-csrf-token' "$header_file" \
        | tail -1 | awk '{print $2}' | tr -d '\r\n' || true)

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

    if [[ "$code" == "401" ]]; then
        log "INFO: Session expired on POST, re-authenticating..."
        if ! unifi_login; then
            log "ERROR: Re-authentication failed on POST"
            echo "$code"
            return 1
        fi
        args=(-sk -w "\n__CODE__:%{http_code}"
            -X POST
            -H "Content-Type: application/json"
            -H "Cookie: TOKEN=${SESSION_TOKEN}")
        [[ -n "$CSRF_TOKEN" ]] && args+=(-H "x-csrf-token: $CSRF_TOKEN")
        raw=$(curl --max-time 30 "${args[@]}" -d "$payload" "$url" 2>/dev/null || true)
        code=$(echo "$raw" | grep '__CODE__:' | cut -d: -f2 | tr -d '\r\n')
    fi

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

# ─── IP / hostname assignment ─────────────────────────────────────────────────
get_next_guest_number() {
    local used n=1
    used=$(grep -oh 'guest[0-9]*' "$MAC_LIST" "$PENDING_LIST" 2>/dev/null \
        | sed 's/guest//' | sort -n | uniq || true)
    while echo "$used" | grep -q "^${n}$"; do (( n++ )); done
    echo "$n"
}

# IMPORTANT: this function is called inside $() subshells.
# Never add log(), echo(), or side effects here — output goes to the caller.
# Results must be returned ONLY as: "IP;hostname" via the final echo.
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

# Returns the voucher code matching a given end_time, or empty if not found.
# Used to enrich the guest hostname with the voucher code (e.g. guest1-0316670958).
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

# ─── Lease removal queue ─────────────────────────────────────────────────────
# Queues a MAC for removal from pydhcpd.leases. The actual removal is performed
# by uleases.sh during its safe stop→modify→start cycle, avoiding writes to the
# leases file while pydhcpd is running.
queue_lease_removal() {
    local mac="$1"
    local lc_mac
    lc_mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    if ! grep -qxF "$lc_mac" "$LEASE_REMOVE_QUEUE" 2>/dev/null; then
        echo "$lc_mac" >> "$LEASE_REMOVE_QUEUE"
        log "INFO: Queued lease removal for $lc_mac"
    fi
}

# ─── MAC list deduplication ───────────────────────────────────────────────────
# blockdhcp.txt must use format a;MAC;IP;HOSTNAME; (4 fields, no epoch).
# Entries with extra fields are sanitized on each run.
dedup_mac_lists() {
    local acl_dir
    acl_dir="$(dirname "$MAC_LIST")"

    # MANAGED_MACS: only MACs from /etc/acl/acl_mac/mac-*.txt.
    # Used to block portal entry for clients already managed by another ACL list.
    MANAGED_MACS=$(
        {
            for f in "$ACL_MAC_PATH"/mac-*.txt; do
                [[ -f "$f" ]] && grep -ih '^a;' "$f" 2>/dev/null || true
            done
        } | awk -F';' '{print tolower($2)}' \
          | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' \
          | sort -u
    )

    # all_macs: all managed MACs across all lists.
    # Used internally to clean blockdhcp.txt.
    local all_macs
    all_macs=$(
        {
            awk -F';' '/^a;/{print tolower($2)}' "$PENDING_LIST" 2>/dev/null || true
            awk -F';' '/^a;/{print tolower($2)}' "$MAC_LIST"     2>/dev/null || true
            echo "$MANAGED_MACS"
        } | grep -E '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' \
          | sort -u
    )

    local removed_block=0 sanitized_block=0

    # Sanitize and clean blockdhcp.txt
    if [[ -f "$BLOCK_DHCP" ]]; then
        local tmp_block
        tmp_block=$(mktemp)
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            local bmac bip bhostname field_count
            IFS=';' read -r _ bmac bip bhostname _ <<< "$line"
            bmac=$(echo "$bmac" | tr '[:upper:]' '[:lower:]')

            # Skip if this MAC is already managed
            if echo "$all_macs" | grep -q "^${bmac}$"; then
                log "INFO: dedup → removed $bmac from blockdhcp.txt"
                (( removed_block++ )) || true
                continue
            fi

            # Normalize to 4-field format a;MAC;IP;HOSTNAME;
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

    if (( sanitized_block > 0 )); then
        log "INFO: dedup → sanitized $sanitized_block blockdhcp entries (extra fields removed)"
    fi
}

# ─── ACL helpers ──────────────────────────────────────────────────────────────
# ─── Backup authorized MACs to guest-wellknow.txt ────────────────────────────
# Behavior:
#   - First run (file empty or missing): seeds the file with all MACs from mac-hotspot.txt
#   - Subsequent runs: only ADDS new MACs (sort -u merge). Never removes existing ones.
#   - Always: if a MAC in guest-wellknow.txt appears in blockdhcp.txt, removes
#             it from blockdhcp.txt (a known trusted client must not be blocked)
mac_hotspot_backup() {
    local wellknow_file current_macs new_macs merged_macs

    wellknow_file="$(dirname "$MAC_LIST")/guest-wellknow.txt"

    # Extract current MACs from mac-hotspot.txt (field 2 of lines starting with 'a;')
    new_macs=$(awk -F';' '/^a;/{print $2}' "$MAC_LIST" | sort -u)

    if [[ ! -s "$wellknow_file" ]]; then
        # ── First run: seed with everything in mac-hotspot.txt ──────────────
        merged_macs="$new_macs"
        log "INFO: mac_hotspot_backup: guest-wellknow.txt is new/empty — seeding with $(echo "$merged_macs" | grep -c .) MACs"
    else
        # ── Subsequent runs: merge (add only, never remove) ──────────────────
        current_macs=$(sort -u "$wellknow_file")
        merged_macs=$(printf '%s\n%s\n' "$current_macs" "$new_macs" | sort -u)
    fi

    # ── Atomic write ─────────────────────────────────────────────────────────
    echo "$merged_macs" | grep -v '^$' > "${wellknow_file}.tmp" \
        && mv "${wellknow_file}.tmp" "$wellknow_file" \
        && chmod 600 "$wellknow_file"

    # ── Always: remove from blockdhcp.txt any MAC present in guest-wellknow.txt
    if [[ -s "$BLOCK_DHCP" && -s "$wellknow_file" ]]; then
        local removed
        removed=$(grep -cFf "$wellknow_file" "$BLOCK_DHCP" || true)
        if [[ $removed -gt 0 ]]; then
            grep -vFf "$wellknow_file" "$BLOCK_DHCP" > "${BLOCK_DHCP}.tmp" \
                && mv "${BLOCK_DHCP}.tmp" "$BLOCK_DHCP"
            log "WARNING: mac_hotspot_backup: removed $removed entry/entries from blockdhcp.txt — MAC(s) found in guest-wellknow.txt"
        fi
    fi
}

# ─── Sort ACL files by IP ─────────────────────────────────────────────────────
sort_acl_files() {
    local tmp

    if [[ -s "$MAC_LIST" ]]; then
        tmp=$(mktemp)
        sort -t';' -k3,3V "$MAC_LIST" | uniq > "$tmp"
        mv "$tmp" "$MAC_LIST" && chmod 600 "$MAC_LIST"
    fi

    if [[ -s "$PENDING_LIST" ]]; then
        tmp=$(mktemp)
        sort -t';' -k3,3V "$PENDING_LIST" | uniq > "$tmp"
        mv "$tmp" "$PENDING_LIST" && chmod 600 "$PENDING_LIST"
    fi
}

add_mac_to_acl() {
    local mac="$1" ip="$2" hostname="$3" end_time="$4"
    local new_line="a;${mac};${ip};${hostname};${end_time};"

    if grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null; then
        sed -i "/^a;${mac};/Id" "$PENDING_LIST"
    fi

    queue_lease_removal "$mac"

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

# ─── Step 3: remove expired MACs from mac-hotspot.txt ────────────────────────
clean_expired_macs() {
    local now tmp
    now=$(date +%s)
    tmp=$(mktemp)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
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

    if [[ -z "$active_macs" ]]; then
        log "INFO: clean_disconnected_pending: no active MACs from stat/sta — skipping to avoid false removals"
        return
    fi

    local tmp removed=0
    tmp=$(mktemp)
    while IFS=';' read -r status mac ip hostname _; do
        [[ "$status" != "a" ]] && continue
        [[ -z "$mac" ]] && continue
        if echo "$active_macs" | grep -qi "^${mac}$"; then
            echo "${status};${mac};${ip};${hostname};" >> "$tmp"
        else
            log "INFO: Removed disconnected pending $mac — not seen on $HOTSPOT_ESSID"
            (( removed++ )) || true
        fi
    done < "$PENDING_LIST"
    mv "$tmp" "$PENDING_LIST" && chmod 600 "$PENDING_LIST"
}

# ─── Step 4: detect new portal clients (stat/sta) ────────────────────────────
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

    # ── Evict oldest pending if range is exhausted ────────────────────────────
    local available_count=0 i
    for (( i=HOTSPOT_RANGE_START; i<=HOTSPOT_RANGE_END; i++ )); do
        local candidate="${HOTSPOT_IP_RANGE}.${i}"
        grep -q ";${candidate};" "$MAC_LIST"     2>/dev/null && continue
        grep -q ";${candidate};" "$PENDING_LIST" 2>/dev/null && continue
        (( available_count++ )) || true
    done

    if [[ $available_count -eq 0 ]]; then
        local oldest_line oldest_mac oldest_ip
        oldest_line=$(grep '^a;' "$PENDING_LIST" 2>/dev/null | head -1 || true)
        oldest_mac=$(echo "$oldest_line" | awk -F';' '{print $2}')
        oldest_ip=$(echo "$oldest_line"  | awk -F';' '{print $3}')
        if [[ -n "$oldest_mac" && -n "$oldest_ip" ]]; then
            log "INFO: Range exhausted — evicting oldest pending $oldest_mac (ip=$oldest_ip)"
            sed -i "/^a;${oldest_mac};/Id" "$PENDING_LIST"
            queue_lease_removal "$oldest_mac"
        else
            log "WARNING: Range exhausted and no pending guest to evict — skipping pending"
            return
        fi
    fi

    clean_disconnected_pending "$guests_data"

    local count=0
    while IFS=$'\t' read -r mac ip; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue

        # Skip if already managed by hotspot lists
        grep -qi "^a;${mac};" "$MAC_LIST"     2>/dev/null && continue
        grep -qi "^a;${mac};" "$PENDING_LIST" 2>/dev/null && continue

        # Skip if already managed by another ACL list (mac-proxy, mac-transparent, etc.)
        if echo "$MANAGED_MACS" | grep -qi "^${mac}$"; then
            log "INFO: Skipping $mac — already managed in ACL lists (mac-*)"
            continue
        fi

        # Assign IP and hostname from the hotspot range
        local iph assigned_ip assigned_hostname
        iph=$(assign_ip_and_hostname) || continue
        assigned_ip=$(echo "$iph" | cut -d';' -f1)
        assigned_hostname=$(echo "$iph" | cut -d';' -f2)

        echo "a;${mac};${assigned_ip};${assigned_hostname};" >> "$PENDING_LIST"
        log "INFO: Pending guest $mac → ip=$assigned_ip hostname=$assigned_hostname (ssid=$HOTSPOT_ESSID)"

        queue_lease_removal "$mac"
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

# ─── Step 5: detect voucher-authenticated clients (stat/guest) ────────────────
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

    while IFS=$'\t' read -r mac end_time api_voucher_code; do
        [[ -z "$mac" || "$mac" == "null" ]] && continue
        [[ -z "$end_time" || "$end_time" == "null" ]] && continue

        # Skip sessions that are already expired
        if (( end_time <= now )); then
            continue
        fi

        # Skip if already managed by another ACL list (mac-proxy, mac-transparent, etc.)
        if echo "$MANAGED_MACS" | grep -qi "^${mac}$"; then
            log "INFO: Skipping $mac — already managed in ACL lists (mac-*)"
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

        # Enrich hostname with voucher code if available (e.g. guest1-0316670958)
        # Use voucher_code directly from stat/guest (reliable even after voucher is purged
        # from stat/voucher). Fall back to cache lookup only if field is absent.
        local voucher_code
        if [[ -n "$api_voucher_code" && "$api_voucher_code" != "null" ]]; then
            voucher_code="$api_voucher_code"
        else
            voucher_code=$(get_voucher_code_by_end_time "$end_time")
        fi
        [[ -n "$voucher_code" ]] && assigned_hostname="${assigned_hostname%-*}-${voucher_code}"

        add_mac_to_acl "$mac" "$assigned_ip" "$assigned_hostname" "$end_time"
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

# ─── Revoke MACs that UniFi reports as unauthorized ──────────────────────────
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
# the current state of MAC_LIST, PENDING_LIST and the lease removal queue
# against the baseline and invokes SERVER_RELOAD_SCRIPT exactly once if any
# of them changed.
_ACL_SNAPSHOT_HOTSPOT=""
_ACL_SNAPSHOT_PENDING=""
_ACL_SNAPSHOT_QUEUE=""

snapshot_acls() {
    _ACL_SNAPSHOT_HOTSPOT=$(md5sum "$MAC_LIST"     2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_PENDING=$(md5sum "$PENDING_LIST" 2>/dev/null | awk '{print $1}' || echo "absent")
    _ACL_SNAPSHOT_QUEUE=$(md5sum "$LEASE_REMOVE_QUEUE" 2>/dev/null | awk '{print $1}' || echo "absent")
}

check_and_reload_if_changed() {
    local cur_hotspot cur_pending cur_queue
    cur_hotspot=$(md5sum "$MAC_LIST"     2>/dev/null | awk '{print $1}' || echo "absent")
    cur_pending=$(md5sum "$PENDING_LIST" 2>/dev/null | awk '{print $1}' || echo "absent")
    cur_queue=$(md5sum "$LEASE_REMOVE_QUEUE" 2>/dev/null | awk '{print $1}' || echo "absent")

    if [[ "$cur_hotspot" == "$_ACL_SNAPSHOT_HOTSPOT" && \
          "$cur_pending" == "$_ACL_SNAPSHOT_PENDING" && \
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
        timeout 60 bash "$SERVER_RELOAD_SCRIPT" >> "$LOG_FILE" 2>&1 \
            || { rc=$?; [[ $rc -eq 124 ]] \
                && log "WARNING: $SERVER_RELOAD_SCRIPT timed out after 60s" \
                || log "WARNING: $SERVER_RELOAD_SCRIPT exited with error (code $rc)"; }
        unset UHOTSPOT_RELOAD_ACTIVE
    else
        log "WARNING: ACLs changed but SERVER_RELOAD_SCRIPT is not set or not executable"
    fi
}


set -euo pipefail

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    load_config
    verify_installation
    log "INFO: uhotspot Start. Wait..."
    init_acl_files
    if ! unifi_login; then
        log "ERROR: Cannot authenticate to UniFi controller — aborting"
        exit 1
    fi
    load_all_vouchers
    dedup_mac_lists
    sort_acl_files
    snapshot_acls
    clean_expired_macs
    process_pending_guests
    process_sessions
    revoke_unauthorized
    unauthorize_pending
    mac_hotspot_backup
    check_and_reload_if_changed

    # ── Run summary ──────────────────────────────────────────────────────────
    local pending_total authorized_total
    pending_total=$(grep -c "^a;" "$PENDING_LIST" 2>/dev/null || true)
    pending_total=$(( ${pending_total:-0} + 0 ))
    authorized_total=$(grep -c "^a;" "$MAC_LIST" 2>/dev/null || true)
    authorized_total=$(( ${authorized_total:-0} + 0 ))
    log "INFO: vouchers=$VOUCHER_COUNT | authorized=$authorized_total | pending=$pending_total | new_pending=$PENDING_NEW | new_auth=$SESSIONS_AUTHORIZED | revoked=$REVOKED"
    log "INFO: Done"
}

main "$@"
