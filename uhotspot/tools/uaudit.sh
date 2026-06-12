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
    local payload
    payload=$(jq -n --arg u "$UNIFI_USERNAME" --arg p "$UNIFI_PASSWORD" \
        '{username:$u, password:$p}')
    LOGIN=$(curl -sk -i -X POST -H "Content-Type: application/json" \
        -d "$payload" \
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

            connected=$(echo "$sta_map" | awk -v mac="${mac}" 'tolower($1) == tolower(mac) {print "YES"}' FS='\t')
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

            sta_row=$(echo "$sta_map" | awk -v mac="${mac}" 'tolower($1) == tolower(mac)' FS='\t' | head -1)
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

# ── Interactive [1]: delete unused vouchers (used == 0) ──────────────────────
# Targets vouchers that were never activated (no client ever used them).
# Safe to delete: no sessions to unauthorize, no client history to remove.
interactive_delete_unused() {
    echo ""
    echo "======================================================================="
    echo " DELETE UNUSED VOUCHERS - vouchers that have never been activated"
    echo "======================================================================="

    mapfile -t UNUSED_IDS < <(echo "$VOUCHER" | jq -r '
        .data[] | select(.used == 0) | ._id
    ' 2>/dev/null)

    if [ ${#UNUSED_IDS[@]} -eq 0 ]; then
        echo "  No unused vouchers found."
        return
    fi

    echo "  Unused vouchers to delete:"
    echo ""
    for vid in "${UNUSED_IDS[@]}"; do
        local info
        info=$(echo "$VOUCHER" | jq -r --arg id "$vid" '
            .data[] | select(._id == $id)
            | [
                (.code // "N/A"),
                (((.duration // 0) / 60 | floor | tostring) + "h"),
                ("quota=" + ((.quota // 0) | tostring)),
                (if .create_time then (.create_time | strftime("%Y-%m-%d")) else "N/A" end)
              ]
            | join("  ")
        ' 2>/dev/null)
        echo "    code=$info"
    done

    echo ""
    read -rp "  Confirm deletion of ${#UNUSED_IDS[@]} unused voucher(s)? [y/N]: " CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo ""
    for vid in "${UNUSED_IDS[@]}"; do
        local code rc
        code=$(echo "$VOUCHER" | jq -r --arg id "$vid" \
            '.data[] | select(._id == $id) | .code' 2>/dev/null)
        rc=$(api_post "cmd/hotspot" "{\"cmd\":\"delete-voucher\",\"_id\":\"${vid}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$rc" = "ok" ] \
            && echo "  Deleted voucher: $code" \
            || echo "  Failed to delete voucher: $code"
    done

    echo ""
    echo "  Done."
}

# ── Interactive [2]: forget portal clients who never submitted a voucher ───────
# Targets clients in rest/user (is_guest=true) who have no record in stat/guest
# (never used a voucher) and are not currently connected to the hotspot ESSID
# in stat/sta. Action: forget-sta only (they were never authorized).
interactive_forget_no_voucher() {
    echo ""
    echo "======================================================================="
    echo " FORGET CLIENTS WITHOUT VOUCHER - connected to portal but never used one"
    echo "======================================================================="

    local ALLUSER
    ALLUSER=$(api_get "rest/user")
    local ALLUSER_RC
    ALLUSER_RC=$(echo "$ALLUSER" | jq -r '.meta.rc // "error"' 2>/dev/null)
    if [ "$ALLUSER_RC" != "ok" ]; then
        echo "  ERROR: Could not fetch rest/user (rc=$ALLUSER_RC)"
        return
    fi

    # MACs que sí usaron voucher (presentes en stat/guest)
    local guest_macs
    guest_macs=$(echo "$GUEST" | jq -r '
        .data[]
        | select(.voucher_code != null and .voucher_code != "")
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

    # MACs actualmente conectados al ESSID del hotspot (presentes en stat/sta)
    local sta_macs
    sta_macs=$(echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.essid == $essid)
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

    # Candidatos: is_guest=true, no en stat/guest, no en stat/sta activo
    mapfile -t NOVOUCHER_MACS < <(echo "$ALLUSER" | jq -r '
        .data[]
        | select(.is_guest == true)
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u | while IFS= read -r mac; do
        echo "$guest_macs" | grep -qx "$mac" && continue
        echo "$sta_macs"   | grep -qx "$mac" && continue
        echo "$mac"
    done)

    if [ ${#NOVOUCHER_MACS[@]} -eq 0 ]; then
        echo "  No clients found matching the criteria."
        return
    fi

    echo "  Clients to forget (${#NOVOUCHER_MACS[@]}):"
    echo ""
    for mac in "${NOVOUCHER_MACS[@]}"; do
        local hostname last_seen
        hostname=$(echo "$ALLUSER" | jq -r --arg m "$mac" '
            .data[] | select((.mac | ascii_downcase) == $m) | .hostname // "N/A"
        ' 2>/dev/null | head -1)
        last_seen=$(echo "$ALLUSER" | jq -r --arg m "$mac" '
            .data[] | select((.mac | ascii_downcase) == $m)
            | if .last_seen then (.last_seen | strftime("%Y-%m-%d %H:%M")) else "N/A" end
        ' 2>/dev/null | head -1)
        printf "    %-20s  %-25s  last_seen=%s\n" "$mac" "$hostname" "$last_seen"
    done

    echo ""
    read -rp "  Confirm forget of ${#NOVOUCHER_MACS[@]} client(s)? [y/N]: " CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo ""
    for mac in "${NOVOUCHER_MACS[@]}"; do
        local frc
        frc=$(api_post "cmd/stamgr" \
            "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$frc" = "ok" ] \
            && echo "  Forgotten: $mac" \
            || echo "  Failed to forget: $mac"
    done

    echo ""
    echo "  Done."
}

# ── Interactive [3]: delete expired vouchers + forget their clients ────────────
# A voucher is considered expired when its end_time has passed.
# For each expired voucher:
#   1. Delete the voucher from UniFi
#   2. Unauthorize any still-active sessions linked to it (via stat/sta)
#   3. Forget all client history linked to it (via stat/guest by voucher_code)
# This matches the lifecycle model: expired time = no reason to keep anything.
interactive_delete_expired() {
    local now
    now=$(date +%s)

    echo ""
    echo "======================================================================="
    echo " DELETE EXPIRED VOUCHERS + FORGET THEIR CLIENTS"
    echo "======================================================================="

    mapfile -t EXPIRED_IDS < <(echo "$VOUCHER" | jq -r \
        --argjson now "$now" '
        .data[]
        | select(.end_time != null and .end_time < $now)
        | ._id
    ' 2>/dev/null)

    if [ ${#EXPIRED_IDS[@]} -eq 0 ]; then
        echo "  No expired vouchers found."
        return
    fi

    echo "  Expired vouchers to delete:"
    echo ""
    for vid in "${EXPIRED_IDS[@]}"; do
        local info
        info=$(echo "$VOUCHER" | jq -r --arg id "$vid" '
            .data[] | select(._id == $id)
            | [
                (.code // "N/A"),
                (((.duration // 0) / 60 | floor | tostring) + "h"),
                ("used=" + ((.used // 0) | tostring)),
                (if .end_time then (.end_time | strftime("%Y-%m-%d %H:%M")) else "N/A" end)
              ]
            | join("  ")
        ' 2>/dev/null)
        echo "    code=$info"
    done

    echo ""
    read -rp "  Confirm deletion of ${#EXPIRED_IDS[@]} expired voucher(s)? [y/N]: " CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo ""

    for vid in "${EXPIRED_IDS[@]}"; do
        local code rc
        code=$(echo "$VOUCHER" | jq -r --arg id "$vid" \
            '.data[] | select(._id == $id) | .code' 2>/dev/null)

        # 1. Delete the voucher
        rc=$(api_post "cmd/hotspot" "{\"cmd\":\"delete-voucher\",\"_id\":\"${vid}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        if [ "$rc" = "ok" ]; then
            echo "  Deleted voucher: $code"
        else
            echo "  Failed to delete voucher: $code — skipping its clients"
            continue
        fi

        # 2. Unauthorize active sessions linked to this voucher (stat/sta)
        while IFS= read -r mac; do
            [ -z "$mac" ] && continue
            local unauth_rc
            unauth_rc=$(api_post "cmd/stamgr" \
                "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}" \
                | jq -r '.meta.rc // "error"' 2>/dev/null)
            [ "$unauth_rc" = "ok" ] \
                && echo "    Unauthorized: $mac" \
                || echo "    ~ No active session: $mac"
        done < <(echo "$STA" | jq -r --arg code "$code" '
            .data[]
            | select(.voucher_code == $code)
            | (.mac | ascii_downcase)
        ' 2>/dev/null | sort -u)

        # 3. Forget all client history linked to this voucher (stat/guest)
        while IFS= read -r mac; do
            [ -z "$mac" ] && continue
            local frc
            frc=$(api_post "cmd/stamgr" \
                "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}" \
                | jq -r '.meta.rc // "error"' 2>/dev/null)
            [ "$frc" = "ok" ] \
                && echo "    Forgotten: $mac" \
                || echo "    Failed to forget: $mac"
        done < <(echo "$GUEST" | jq -r --arg code "$code" '
            .data[]
            | select(.voucher_code == $code)
            | (.mac | ascii_downcase)
        ' 2>/dev/null | sort -u)
    done

    echo ""
    echo "  Done."
}

# ── Interactive [4]: purge all vouchers and client history ────────────────────
# Deletes ALL vouchers regardless of status or expiry, unauthorizes ALL active
# guest sessions, and erases ALL client history from UniFi.
# Requires typing YES to confirm. This action cannot be undone.
interactive_purge_all() {
    local voucher_total
    voucher_total=$(echo "$VOUCHER" | jq -r '.data | length' 2>/dev/null || echo "?")

    echo ""
    echo "======================================================================="
    echo " PURGE ALL — THIS WILL DESTROY ALL VOUCHERS AND CLIENT HISTORY"
    echo "======================================================================="
    echo ""
    echo "  This action will:"
    echo "    - Delete ALL vouchers ($voucher_total in stat/voucher)"
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

    # 2. Unauthorize all active sessions (stat/sta — currently connected)
    local mac unauth_rc
    while IFS= read -r mac; do
        [ -z "$mac" ] && continue
        unauth_rc=$(api_post "cmd/stamgr" \
            "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$unauth_rc" = "ok" ] \
            && echo "  Unauthorized: $mac" \
            || echo "  ~ No active session: $mac"
    done < <(echo "$STA" | jq -r '.data[] | (.mac | ascii_downcase)' 2>/dev/null | sort -u)

    # 3. Forget all client history (stat/guest — all past and present sessions)
    while IFS= read -r mac; do
        [ -z "$mac" ] && continue
        local frc
        frc=$(api_post "cmd/stamgr" \
            "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$frc" = "ok" ] \
            && echo "  Forgotten: $mac" \
            || echo "  Failed to forget: $mac"
    done < <(echo "$GUEST" | jq -r '.data[] | (.mac | ascii_downcase)' 2>/dev/null | sort -u)

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
# INTERACTIVE ACTIONS (after report)
#   [1] Delete unused vouchers  - delete vouchers never activated (used=0)
#   [2] Forget clients no voucher - forget guests who never submitted a voucher
#   [3] Delete expired vouchers - delete expired vouchers and forget their clients
#   [4] Purge everything        - DELETE all vouchers and client history (DESTRUCTIVE)
echo ""
echo "======================================================================="
echo " AVAILABLE ACTIONS"
echo "======================================================================="
echo "  [1] Delete unused vouchers   - remove vouchers never activated"
echo "  [2] Forget clients no voucher - connected to portal but never used one"
echo "  [3] Delete expired vouchers  - remove expired vouchers and forget their clients"
echo "  [4] Purge everything         - DELETE all vouchers and history (DESTRUCTIVE)"
echo "  [q] Quit"
echo ""
read -rp "  Your choice: " ACTION

case "$ACTION" in
    1) interactive_delete_unused ;;
    2) interactive_forget_no_voucher ;;
    3) interactive_delete_expired ;;
    4) interactive_purge_all ;;
    q|Q) echo "  Goodbye." ;;
    *) echo "  Invalid option. Exiting." ;;
esac

echo ""
