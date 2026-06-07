#!/bin/bash
# maravento.com
#
################################################################################
#
# Script      : uaudit.sh
# Description : UniFi Network Hotspot - Full Client Audit & Management Tool
#
# REPORT SECTIONS
#   1. Authorized  - mac-hotspot.txt enriched with voucher (stat/guest) and
#                    live connection status (stat/sta)
#   2. Pending     - guest-pending.txt enriched with live connection status
#                    and authorization flag (stat/sta)
#   3. Vouchers    - full voucher list from stat/voucher with usage stats
#
# INTERACTIVE ACTIONS (after report)
#   [1] Revoke used vouchers    - delete (used>0), unauthorize sessions,
#                                 optionally forget client history
#   [2] Delete unused vouchers  - delete vouchers never used (used=0)
#   [3] Forget inactive clients - remove expired guest session history
#   [4] All of the above
#
# AUTH
#   Authenticates against UniFi OS (/api/auth/login). Requires HOTSPOT_ESSID,
#   UNIFI_CONTROLLER_URL, UNIFI_USERNAME, UNIFI_PASSWORD in uhotspot.conf
#
# DEPENDENCIES : curl, jq
# CONFIG       : /etc/uhotspot/uhotspot.conf
# LOG          : /etc/uhotspot/uaudit.log
# TESTED ON    : Ubuntu 24.04 - UniFi OS Network 10.x
#
################################################################################

printf "\n"
echo "UniFi Clients Audit - starting, please wait..."

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

CONFIG="/etc/uhotspot/uhotspot.conf"
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config file not found: $CONFIG"
    exit 1
fi

source "$CONFIG"

if [ -z "$UNIFI_CONTROLLER_URL" ] || [ -z "$UNIFI_USERNAME" ] || [ -z "$UNIFI_PASSWORD" ] || [ -z "$HOTSPOT_ESSID" ]; then
    echo "ERROR: Missing required variables (UNIFI_CONTROLLER_URL, UNIFI_USERNAME, UNIFI_PASSWORD, HOTSPOT_ESSID) in $CONFIG"
    exit 1
fi

SITE="${UNIFI_SITE:-default}"
TYPE="${UNIFI_TYPE:-unifi-os}"
LOG="/etc/uhotspot/uaudit.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Authentication ────────────────────────────────────────────────────────────
# Logs into UniFi OS and extracts TOKEN + CSRF token from response headers.
# The TOKEN cookie is injected manually on every request because curl's
# Netscape cookie jar silently discards cookies with the "partitioned" attribute,
# which UniFi OS uses since version 3.x.
do_login() {
    local login_path
    if [[ "$TYPE" == "classic" ]]; then
        login_path="/api/login"
    else
        login_path="/api/auth/login"
    fi
    LOGIN=$(curl -sk -i -X POST -H "Content-Type: application/json" \
        -d "{\"username\":\"$UNIFI_USERNAME\",\"password\":\"$UNIFI_PASSWORD\"}" \
        "$UNIFI_CONTROLLER_URL$login_path")

    CSRF_TOKEN=$(echo "$LOGIN" | grep -iE "^x-(updated-)?csrf-token:" | tail -1 | awk '{print $2}' | tr -d "\r")
    SESSION_COOKIE=$(echo "$LOGIN" | grep -i "^set-cookie:" | grep -i "TOKEN=" | head -1 \
        | sed -E "s/.*TOKEN=([^;]+).*/TOKEN=\1/" | tr -d "\r")

    if [ -z "$CSRF_TOKEN" ] || [ -z "$SESSION_COOKIE" ]; then
        echo "ERROR: Authentication failed. Check credentials in $CONFIG"
        exit 1
    fi
}

do_login

# ── API helpers ───────────────────────────────────────────────────────────────
if [[ "$TYPE" == "classic" ]]; then
    BASE="$UNIFI_CONTROLLER_URL/api/s/$SITE"
else
    BASE="$UNIFI_CONTROLLER_URL/proxy/network/api/s/$SITE"
fi

api_get() {
    curl -sk -X GET \
        -H "X-CSRF-Token: $CSRF_TOKEN" \
        -H "Cookie: $SESSION_COOKIE" \
        "$BASE/$1"
}

api_post() {
    curl -sk -X POST \
        -H "X-CSRF-Token: $CSRF_TOKEN" \
        -H "Cookie: $SESSION_COOKIE" \
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

# ── Section 1: Authorized clients (mac-hotspot.txt + stat/guest + stat/sta) ───
print_authorized() {
    local ACL_HOTSPOT="/etc/uhotspot/mac-hotspot.txt"
    [ ! -f "$ACL_HOTSPOT" ] && return

    echo ""
    echo "======================================================================="
    echo " AUTHORIZED — mac-hotspot.txt"
    echo "======================================================================="

    local sta_map
    sta_map=$(echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (if .authorized == true then "YES" else "NO" end)]
        | @tsv
    ' 2>/dev/null)

    {
        printf "MAC|IP|VOUCHER|EXPIRES|CONNECTED\n"
        while IFS=';' read -r status mac ip hostname end_time _; do
            [ "$status" != "a" ] && continue
            [ -z "$mac" ] && continue

            expires="N/A"
            [ -n "$end_time" ] && expires=$(date -d "@$end_time" '+%m-%d %H:%M' 2>/dev/null || echo "$end_time")

            voucher=$(echo "$GUEST" | jq -r --arg m "$mac" '
                .data[]
                | select((.mac | ascii_downcase) == $m)
                | .voucher_code // "N/A"
            ' 2>/dev/null | head -1)
            [ -z "$voucher" ] && voucher="N/A"

            connected=$(echo "$sta_map" | grep -i "^${mac}" | awk -F'\t' '{print "YES"}')
            [ -z "$connected" ] && connected="NO"

            echo "$mac|$ip|$voucher|$expires|$connected"
        done < "$ACL_HOTSPOT"
    } | column -t -s '|'
    echo ""
}

# ── Section 2: Pending clients (guest-pending.txt + stat/sta) ────────────────
print_pending() {
    local ACL_PENDING="/etc/uhotspot/guest-pending.txt"
    [ ! -f "$ACL_PENDING" ] && return

    echo ""
    echo "======================================================================="
    echo " PENDING — guest-pending.txt"
    echo "======================================================================="

    local sta_map
    sta_map=$(echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (if .authorized == true then "YES" else "NO" end)]
        | @tsv
    ' 2>/dev/null)

    {
        printf "MAC|IP|HOSTNAME|CONNECTED|AUTH\n"
        while IFS=';' read -r status mac ip hostname _; do
            [ "$status" != "a" ] && continue
            [ -z "$mac" ] && continue

            sta_row=$(echo "$sta_map" | grep -i "^${mac}" | head -1)
            if [ -n "$sta_row" ]; then
                connected="YES"
                auth=$(echo "$sta_row" | awk -F'\t' '{print $2}')
            else
                connected="NO"
                auth="NO"
            fi

            echo "$mac|$ip|$hostname|$connected|$auth"
        done < "$ACL_PENDING"
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
            | [.code//"N/A", (.status//"N/A"), (((.duration//0)/60|floor|tostring) + "h"), (.quota//0|tostring), (.used//0|tostring), (if .end_time then (.end_time|strftime("%m-%d %H:%M")) else "N/A" end)]
            | join("|")
        ' 2>/dev/null
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
    ' 2>/dev/null | grep -v '^$' | sort -u)

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
    [[ ! "$CONFIRM" =~ ^[yY](es)?$ ]] && echo "  Cancelled." && return

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
    [[ ! "$CONFIRM" =~ ^[yY](es)?$ ]] && echo "  Cancelled." && return

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

# ── Interactive: revoke fully consumed vouchers ──────────────────────────────
# Targets vouchers where all available slots have been used (used >= quota).
# Deletes the voucher, unauthorizes active sessions, and optionally removes
# client history.
interactive_revoke_used() {
    _voucher_selector \
        "REVOKE USED VOUCHERS - activated vouchers with active or past sessions" \
        '.data[] | select(.quota > 0 and .used >= .quota) | ._id' \
        "Revoke"
}

# ── Interactive: delete unused vouchers (used == 0) ───────────────────────────
# Targets vouchers that were never activated. Safe to delete with no session
# or client side effects.
interactive_delete_unused() {
    _voucher_selector \
        "DELETE UNUSED VOUCHERS - vouchers that have never been activated" \
        '.data[] | select(.used == 0) | ._id' \
        "Delete"
}

# ── Interactive: purge all vouchers and client history ────────────────────────
# Deletes ALL vouchers regardless of status or usage, unauthorizes ALL active
# guest sessions, and erases ALL client history from UniFi. Requires typing
# YES to confirm. This action cannot be undone.
interactive_purge_all() {
    echo ""
    echo "======================================================================="
    echo " PURGE ALL — THIS WILL DESTROY ALL VOUCHERS AND CLIENT HISTORY"
    echo "======================================================================="
    echo ""
    echo "  This action will:"
    echo "    - Delete ALL vouchers (${#VOUCHER_IDS_ALL[@]:-all} in stat/voucher)"
    echo "    - Unauthorize ALL active guest sessions"
    echo "    - Erase ALL client history from UniFi"
    echo ""
    echo "  This cannot be undone."
    echo ""
    read -rp "  Type YES to confirm: " CONFIRM
    [[ "$CONFIRM" != "YES" ]] && echo "  Cancelled." && return

    echo ""

    # 1. Delete all vouchers
    local vid code rc
    while IFS= read -r vid; do
        [ -z "$vid" ] && continue
        code=$(echo "$VOUCHER" | jq -r --arg id "$vid" \
            '.data[] | select(._id == $id) | .code' 2>/dev/null)
        rc=$(api_post "cmd/hotspot" "{\"cmd\":\"delete-voucher\",\"_id\":\"${vid}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$rc" = "ok" ] \
            && echo "  Deleted voucher: $code" \
            || echo "  Failed to delete voucher: $code"
    done < <(echo "$VOUCHER" | jq -r '.data[] | ._id' 2>/dev/null)

    # 2. Unauthorize all active sessions
    local mac unauth_rc
    while IFS= read -r mac; do
        [ -z "$mac" ] && continue
        unauth_rc=$(api_post "cmd/stamgr" \
            "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$unauth_rc" = "ok" ] \
            && echo "  Unauthorized: $mac" \
            || echo "  ~ No active session: $mac"
    done < <(echo "$GUEST" | jq -r '.data[] | (.mac | ascii_downcase)' 2>/dev/null | sort -u)

    # 3. Forget all client history
    while IFS= read -r mac; do
        [ -z "$mac" ] && continue
        local frc
        frc=$(api_post "cmd/stamgr" \
            "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$frc" = "ok" ] \
            && echo "  Forgotten: $mac" \
            || echo "  Failed to forget: $mac"
    done < <(echo "$STA" | jq -r '.data[] | (.mac | ascii_downcase)' 2>/dev/null | sort -u)

    echo ""
    echo "  Purge complete."
}

# ── Run report ────────────────────────────────────────────────────────────────
OUTPUT=""
OUTPUT+=$(print_authorized)
OUTPUT+=$(print_pending)
OUTPUT+=$(print_voucher)

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
echo "  [1] Revoke used vouchers    - delete fully consumed vouchers"
echo "  [2] Delete unused vouchers  - remove vouchers never activated"
echo "  [3] Forget inactive clients - erase expired session history in UniFi"
echo "  [4] All of the above"
echo "  [5] Purge everything        - DELETE all vouchers and history (DESTRUCTIVE)"
echo "  [q] Quit"
echo ""
read -rp "  Your choice: " ACTION

case "$ACTION" in
    1) interactive_revoke_used ;;
    2) interactive_delete_unused ;;
    3) interactive_forget ;;
    4) interactive_revoke_used; interactive_delete_unused; interactive_forget ;;
    5) interactive_purge_all ;;
    q|Q) echo "  Goodbye." ;;
    *) echo "  Invalid option. Exiting." ;;
esac

echo ""
