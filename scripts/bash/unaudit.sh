#!/bin/bash
# =============================================================================
# Script      : unaudit.sh
# Description : UniFi Network Hotspot - Full Client Audit & Management Tool
#
# REPORT SECTIONS
#   1. Connected clients  - live snapshot from stat/sta filtered by guest SSID
#   2. Guest sessions     - voucher sessions from stat/guest (active + expired)
#   3. Vouchers           - full voucher list from stat/voucher with usage stats
#   4. Cross-reference    - guest sessions enriched with stat/sta + voucher data
#   5. ACL vs API         - mac-hotspot.txt entries vs UniFi guest API
#
# INTERACTIVE ACTIONS (after report)
#   [1] Revoke used vouchers    - delete vouchers with used > 0, unauthorize
#                                 active sessions, optionally forget client history
#   [2] Delete unused vouchers  - delete vouchers with used = 0 (never activated)
#   [3] Forget inactive clients - remove expired guest session history via
#                                 forget-sta (cleans UniFi client list)
#   [4] All of the above
#
# AUTH
#   Authenticates against UniFi OS (/api/auth/login).
#   Extracts TOKEN from set-cookie header manually - curl's Netscape cookie jar
#   silently drops cookies with the "partitioned" flag used by UniFi OS >= 3.x.
#   CSRF token is extracted from x-csrf-token response header and sent on every
#   subsequent request to satisfy UniFi OS CSRF protection.
#
# DEPENDENCIES : curl, jq
# CONFIG       : /etc/unhotspot/config.conf
# LOG          : /etc/unhotspot/unaudit.log
# TESTED ON    : Ubuntu 24.04 - UniFi OS Network 10.x
# =============================================================================

printf "\n"
echo "UniFi Clients Audit - starting, please wait..."

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

for dep in curl jq; do
    if ! command -v "$dep" &>/dev/null; then
        echo "ERROR: Required dependency '$dep' is not installed."
        exit 1
    fi
done

CONFIG="/etc/unhotspot/config.conf"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

source "$CONFIG"

if [ -z "$UNIFI_CONTROLLER_URL" ] || [ -z "$UNIFI_USERNAME" ] || [ -z "$UNIFI_PASSWORD" ]; then
    echo "ERROR: Missing required variables (UNIFI_CONTROLLER_URL, UNIFI_USERNAME, UNIFI_PASSWORD) in $CONFIG"
    exit 1
fi

SITE="${UNIFI_SITE:-default}"
LOG="/etc/unhotspot/unaudit.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Authentication ────────────────────────────────────────────────────────────
# Logs into UniFi OS and extracts TOKEN + CSRF token from response headers.
# The TOKEN cookie is injected manually on every request because curl's
# Netscape cookie jar silently discards cookies with the "partitioned" attribute,
# which UniFi OS uses since version 3.x.
do_login() {
    LOGIN=$(curl -sk -i -X POST -H "Content-Type: application/json" \
        -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
        "$UNIFI_CONTROLLER_URL/api/auth/login")

    TOKEN=$(echo "$LOGIN" | grep -i "^x-csrf-token:" | cut -d" " -f2 | tr -d "\r")
    COOKIE=$(echo "$LOGIN" | grep -i "^set-cookie:" | grep -i "TOKEN=" | head -1 \
        | sed -E "s/.*TOKEN=([^;]+).*/TOKEN=\1/" | tr -d "\r")

    if [ -z "$TOKEN" ] || [ -z "$COOKIE" ]; then
        echo "ERROR: Authentication failed. Check credentials in $CONFIG"
        exit 1
    fi
}

do_login

# ── API helpers ───────────────────────────────────────────────────────────────
BASE="$UNIFI_CONTROLLER_URL/proxy/network/api/s/$SITE"

api_get() {
    curl -sk -X GET \
        -H "X-CSRF-Token: $TOKEN" \
        -H "Cookie: $COOKIE" \
        "$BASE/$1"
}

api_post() {
    curl -sk -X POST \
        -H "X-CSRF-Token: $TOKEN" \
        -H "Cookie: $COOKIE" \
        -H "Content-Type: application/json" \
        -d "$2" \
        "$BASE/$1"
}

# ── Fetch data from UniFi API ─────────────────────────────────────────────────
STA=$(api_get "stat/sta")
GUEST=$(api_get "stat/guest")
VOUCHER=$(api_get "stat/voucher")

STA_RC=$(echo "$STA"     | jq -r '.meta.rc // "error"' 2>/dev/null)
GUEST_RC=$(echo "$GUEST" | jq -r '.meta.rc // "error"' 2>/dev/null)
VCH_RC=$(echo "$VOUCHER" | jq -r '.meta.rc // "error"' 2>/dev/null)

echo "  stat/sta     -> $STA_RC    ($(echo "$STA"     | jq '.data|length' 2>/dev/null) entries)"
echo "  stat/guest   -> $GUEST_RC  ($(echo "$GUEST"   | jq '.data|length' 2>/dev/null) entries)"
echo "  stat/voucher -> $VCH_RC    ($(echo "$VOUCHER" | jq '.data|length' 2>/dev/null) entries)"

# ── Section 1: Connected clients (stat/sta) ───────────────────────────────────
print_sta() {
    echo ""
    echo "======================================================================="
    echo " CONNECTED CLIENTS — stat/sta"
    echo "======================================================================="
    {
        printf "MAC|IP|HOSTNAME|ESSID|AUTHORIZED\n"
        echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
            .data[]
            | select(.essid == $essid)
            | [.mac//"N/A", .ip//"N/A", (.hostname//.name//"N/A"), .essid//"N/A", (if .authorized then "YES" else "NO" end), (.rssi//0|tostring)]
            | join("|")
        ' 2>/dev/null
    } | column -t -s '|'
    echo ""
}

# ── Section 2: Guest sessions (stat/guest) ────────────────────────────────────
print_guest() {
    echo ""
    echo "======================================================================="
    echo " GUEST SESSIONS — stat/guest"
    echo "======================================================================="
    {
        printf "MAC|IP|VOUCHER|EXPIRED|END\n"
        echo "$GUEST" | jq -r '
            .data[]
            | [.mac//"N/A", .ip//"N/A", .voucher_code//"N/A", (if .expired then "YES" else "NO" end), (if .end then (.end|strftime("%m-%d %H:%M")) else "N/A" end)]
            | join("|")
        ' 2>/dev/null
    } | column -t -s '|'
    echo ""
}

# ── Section 3: Vouchers (stat/voucher) ───────────────────────────────────────
print_voucher() {
    echo ""
    echo "======================================================================="
    echo " VOUCHERS — stat/voucher"
    echo "======================================================================="
    {
        printf "CODE|STATUS|DURATION|QUOTA|USED|EXPIRES\n"
        echo "$VOUCHER" | jq -r '
            .data[]
            | [.code//"N/A", ((.status//"N/A")[0:12]), (((.duration//0)/60|floor|tostring) + "h"), (.quota//0|tostring), (.used//0|tostring), (if .create_time and .duration then ((.create_time + ((.duration//0)*60))|strftime("%m-%d %H:%M")) else "N/A" end)]
            | join("|")
        ' 2>/dev/null
    } | column -t -s '|'
    echo ""
}

# ── Section 4: Cross-reference (guest + sta + voucher) ───────────────────────
print_crossref() {
    echo ""
    echo "======================================================================="
    echo " CROSS-REFERENCE — guest + sta + voucher"
    echo "======================================================================="
    
    STA_AUTH=$(echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (if .authorized == true then "YES" elif .authorized == false then "NO" else "N/A" end)]
        | @tsv
    ' 2>/dev/null)
    
    {
        printf "MAC|IP|VOUCHER|CONN|AUTH|END(guest)\n"
        echo "$GUEST" | jq -r '
            .data[]
            | [(.mac//"N/A"|ascii_downcase), .ip//"N/A", .voucher_code//"N/A", (if .end then (.end|strftime("%m-%d %H:%M")) else "N/A" end)]
            | join("|")
        ' 2>/dev/null | while IFS='|' read -r mac ip voucher end_date; do
            connected=$(echo "$STA_AUTH" | grep -i "^${mac}" | awk '{print "YES"}' || echo "NO")
            [ -z "$connected" ] && connected="NO"
            auth=$(echo "$STA_AUTH" | grep -i "^${mac}" | cut -f2)
            [ -z "$auth" ] && auth="N/A"
            echo "$mac|$ip|$voucher|$connected|$auth|$end_date"
        done
    } | column -t -s '|'
    echo ""
}

# ── Section 5: ACL vs API (mac-hotspot.txt vs stat/guest) ────────────────────
print_acl_vs_api() {
    local MAC_LIST="/etc/unhotspot/mac-hotspot.txt"
    [ ! -f "$MAC_LIST" ] && return

    echo ""
    echo "======================================================================="
    echo " ACL vs API — mac-hotspot.txt cross-check"
    echo "======================================================================="
    
    {
        printf "MAC|IP(ACL)|HOSTNAME(ACL)|END(ACL)|API\n"
        while IFS=';' read -r status mac ip hostname end_time _; do
            [ "$status" != "a" ] && continue
            [ "$mac" = "02:00:00:00:00:00" ] && continue
            [ -z "$mac" ] && continue

            end_human="N/A"
            [ -n "$end_time" ] && end_human=$(date -d "@$end_time" '+%m-%d %H:%M' 2>/dev/null || echo "$end_time")

            in_guest=$(echo "$GUEST" | jq -r --arg m "$mac" '.data[] | select((.mac | ascii_downcase) == $m) | .mac' 2>/dev/null | head -1)
            [ -n "$in_guest" ] && in_api="YES" || in_api="NO"

            hostname_short="${hostname:0:30}"
            echo "$mac|$ip|$hostname_short|$end_human|$in_api"
        done < "$MAC_LIST"
    } | column -t -s '|'
    echo ""
}

# ── Interactive: forget expired/inactive clients ──────────────────────────────
# Lists all clients with expired guest sessions and lets the user choose which
# ones to remove from UniFi's client history via forget-sta.
interactive_forget() {
    echo ""
    echo "======================================================================="
    echo " FORGET INACTIVE CLIENTS - expired sessions from stat/guest"
    echo "======================================================================="

    # Collect MACs with expired sessions
    mapfile -t EXPIRED_MACS < <(echo "$GUEST" | jq -r '
        .data[]
        | select(.expired == true or .end == null or .end < now)
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

    if [ ${#EXPIRED_MACS[@]} -eq 0 ]; then
        echo "  No expired or inactive clients found."
        return
    fi

    echo "  Expired clients in history:"
    echo ""
    declare -A MAC_INFO
    local idx=1
    for mac in "${EXPIRED_MACS[@]}"; do
        local info
        info=$(echo "$GUEST" | jq -r --arg m "$mac" '
            .data[]
            | select((.mac | ascii_downcase) == $m)
            | [(.voucher_code // "N/A"), (if .end then (.end | todate) else "N/A" end), (.ip // "N/A")]
            | join(" | ")
        ' 2>/dev/null | head -1)
        printf "  [%2d] %-19s  voucher=%-14s  end=%s  ip=%s\n" \
            "$idx" "$mac" \
            "$(echo "$info" | cut -d'|' -f1 | xargs)" \
            "$(echo "$info" | cut -d'|' -f2 | xargs)" \
            "$(echo "$info" | cut -d'|' -f3 | xargs)"
        MAC_INFO[$idx]="$mac"
        (( idx++ ))
    done

    echo ""
    echo "  Options:"
    echo "    all   --> forget all listed clients"
    echo "    1 3 5 --> forget by number (space-separated)"
    echo "    q     --> cancel"
    echo ""
    read -rp "  Your choice: " CHOICE

    [ "$CHOICE" = "q" ] && echo "  Cancelled." && return

    local selected=()
    if [ "$CHOICE" = "all" ]; then
        selected=("${EXPIRED_MACS[@]}")
    else
        read -ra CHOICES <<< "$CHOICE"
        for n in "${CHOICES[@]}"; do
            if [[ "$n" =~ ^[0-9]+$ ]] && [ -n "${MAC_INFO[$n]+_}" ]; then
                selected+=("${MAC_INFO[$n]}")
            else
                echo "  WARN: '$n' is not valid, skipped."
            fi
        done
    fi

    if [ ${#selected[@]} -eq 0 ]; then
        echo "  Nothing selected."
        return
    fi

    echo ""
    echo "  About to forget ${#selected[@]} client(s):"
    for mac in "${selected[@]}"; do echo "    - $mac"; done
    echo ""
    read -rp "  Are you sure? [y/N]: " CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo "  Forgetting ${#selected[@]} client(s)..."
    for mac in "${selected[@]}"; do
        local result rc
        result=$(api_post "cmd/stamgr" "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}")
        rc=$(echo "$result" | jq -r '.meta.rc // "error"' 2>/dev/null)
        if [ "$rc" = "ok" ]; then
            echo "  Forgotten: $mac"
        else
            echo "  Failed to forget $mac: $result"
        fi
    done
}

# ── Helper: interactive voucher selector ─────────────────────────────────────
# Shared logic for voucher revocation and deletion.
# Args:
#   $1  title        - section header shown to the user
#   $2  filter       - jq filter expression to select vouchers from $VOUCHER
#   $3  label_action - action verb shown in prompts ("Revoke" or "Delete")
_voucher_selector() {
    local title="$1" filter="$2" label_action="$3"

    echo ""
    echo "======================================================================="
    echo " ${title}"
    echo "======================================================================="

    mapfile -t VOUCHER_IDS < <(echo "$VOUCHER" | jq -r "${filter}" 2>/dev/null)

    if [ ${#VOUCHER_IDS[@]} -eq 0 ]; then
        echo "  No vouchers found in this category."
        return
    fi

    declare -A VCH_ID_MAP
    local idx=1
    for vid in "${VOUCHER_IDS[@]}"; do
        local info
        info=$(echo "$VOUCHER" | jq -r --arg id "$vid" '
            .data[]
            | select(._id == $id)
            | [
                (.code // "N/A"),
                (.status // "N/A"),
                (((.duration // 0) / 60 | floor | tostring) + "h"),
                ("quota=" + ((.quota // 0) | tostring) + " used=" + ((.used // 0) | tostring)),
                (if .create_time then (.create_time | todate) else "N/A" end)
              ]
            | join(" | ")
        ' 2>/dev/null)
        printf "  [%2d] code=%-14s  %s\n" \
            "$idx" \
            "$(echo "$info" | cut -d'|' -f1 | xargs)" \
            "$(echo "$info" | cut -d'|' -f2- | xargs)"
        VCH_ID_MAP[$idx]="$vid"
        (( idx++ ))
    done

    echo ""
    echo "  Options:"
    echo "    all   -> ${label_action} all"
    echo "    1 3 5 -> ${label_action} by number (space-separated)"
    echo "    q     -> cancel"
    echo ""
    read -rp "  Your choice: " CHOICE

    [ "$CHOICE" = "q" ] && echo "  Cancelled." && return

    local selected_ids=()
    if [ "$CHOICE" = "all" ]; then
        selected_ids=("${VOUCHER_IDS[@]}")
    else
        read -ra CHOICES <<< "$CHOICE"
        for n in "${CHOICES[@]}"; do
            if [[ "$n" =~ ^[0-9]+$ ]] && [ -n "${VCH_ID_MAP[$n]+_}" ]; then
                selected_ids+=("${VCH_ID_MAP[$n]}")
            else
                echo "  WARN: '$n' is not valid, skipped."
            fi
        done
    fi

    [ ${#selected_ids[@]} -eq 0 ] && echo "  Nothing selected." && return

    echo ""
    echo "  About to process ${#selected_ids[@]} voucher(s):"
    for vid in "${selected_ids[@]}"; do
        local c
        c=$(echo "$VOUCHER" | jq -r --arg id "$vid" '.data[] | select(._id == $id) | .code' 2>/dev/null)
        echo "    - $c"
    done
    echo ""
    read -rp "  Are you sure? [y/N]: " CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo ""
    echo "  Processing ${#selected_ids[@]} voucher(s)..."
    local affected_macs=()

    for vid in "${selected_ids[@]}"; do
        local code result rc
        code=$(echo "$VOUCHER" | jq -r --arg id "$vid" \
            '.data[] | select(._id == $id) | .code' 2>/dev/null)

        result=$(api_post "cmd/hotspot" "{\"cmd\":\"delete-voucher\",\"_id\":\"${vid}\"}")
        rc=$(echo "$result" | jq -r '.meta.rc // "error"' 2>/dev/null)

        if [ "$rc" = "ok" ]; then
            echo "  Deleted voucher: $code"

            # Collect MACs associated with this voucher (only used vouchers have sessions)
            while IFS= read -r mac; do
                [ -n "$mac" ] && affected_macs+=("$mac")
            done < <(echo "$GUEST" | jq -r --arg code "$code" '
                .data[]
                | select(.voucher_code == $code)
                | (.mac | ascii_downcase)
            ' 2>/dev/null)

            # Unauthorize any active sessions tied to this voucher
            while IFS= read -r mac; do
                [ -z "$mac" ] && continue
                local unauth_rc
                unauth_rc=$(api_post "cmd/stamgr" \
                    "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}" \
                    | jq -r '.meta.rc // "error"' 2>/dev/null)
                if [ "$unauth_rc" = "ok" ]; then
                    echo "  Session revoked: $mac"
                else
                    echo "  ~ No active session found for: $mac"
                fi
            done < <(echo "$GUEST" | jq -r --arg code "$code" '
                .data[]
                | select(.voucher_code == $code)
                | (.mac | ascii_downcase)
            ' 2>/dev/null)
        else
            echo "  Failed to delete voucher $code: $result"
        fi
    done

    # Offer to forget client history for all affected MACs
    if [ ${#affected_macs[@]} -gt 0 ]; then
        echo ""
        echo "  The following clients have sessions linked to the deleted vouchers:"
        for mac in "${affected_macs[@]}"; do
            echo "    - $mac"
        done
        echo ""
        read -rp "  Remove their history from UniFi as well? [y/N]: " FORGET_CHOICE
        if [[ "$FORGET_CHOICE" =~ ^[yY]$ ]]; then
            for mac in "${affected_macs[@]}"; do
                local frc
                frc=$(api_post "cmd/stamgr" \
                    "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}" \
                    | jq -r '.meta.rc // "error"' 2>/dev/null)
                [ "$frc" = "ok" ] \
                    && echo "  History removed: $mac" \
                    || echo "  Failed to forget: $mac"
            done
        fi
    fi
}

# ── Interactive: revoke used vouchers (used > 0) ──────────────────────────────
# Targets vouchers that have been activated at least once. Deletes the voucher,
# unauthorizes active sessions, and optionally removes client history.
interactive_revoke_used() {
    _voucher_selector \
        "REVOKE USED VOUCHERS - activated vouchers with active or past sessions" \
        '.data[] | select((.status == "VALID_ONE" or .status == "VALID_MULTI") and .used > 0) | ._id' \
        "Revoke"
}

# ── Interactive: delete unused vouchers (used == 0) ───────────────────────────
# Targets vouchers that were never activated. Safe to delete with no session
# or client side effects.
interactive_delete_unused() {
    _voucher_selector \
        "DELETE UNUSED VOUCHERS - vouchers that have never been activated" \
        '.data[] | select((.status == "VALID_ONE" or .status == "VALID_MULTI") and .used == 0) | ._id' \
        "Delete"
}

# ── Run report ────────────────────────────────────────────────────────────────
OUTPUT=""
OUTPUT+=$(print_sta)
OUTPUT+=$(print_guest)
OUTPUT+=$(print_voucher)
OUTPUT+=$(print_crossref)
OUTPUT+=$(print_acl_vs_api)

echo "$OUTPUT"

{
    echo ""
    echo "=== Report generated on $TIMESTAMP ==="
    echo "$OUTPUT"
} >> "$LOG"

printf "\nAudit complete. Log saved to: %s\n" "$LOG"

# ── Interactive action menu ───────────────────────────────────────────────────
echo ""
echo "======================================================================="
echo " AVAILABLE ACTIONS"
echo "======================================================================="
echo "  [1] Revoke used vouchers    - delete + unauthorize active sessions"
echo "  [2] Delete unused vouchers  - remove vouchers never activated"
echo "  [3] Forget inactive clients - erase expired session history in UniFi"
echo "  [4] All of the above"
echo "  [q] Quit"
echo ""
read -rp "  Your choice: " ACTION

case "$ACTION" in
    1) interactive_revoke_used ;;
    2) interactive_delete_unused ;;
    3) interactive_forget ;;
    4) interactive_revoke_used; interactive_delete_unused; interactive_forget ;;
    q|Q) echo "  Goodbye." ;;
    *) echo "  Invalid option. Exiting." ;;
esac

echo ""
