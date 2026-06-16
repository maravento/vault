#!/bin/bash
# maravento.com
#
################################################################################
#
# Script      : uaudit.sh
# Description : UniFi Network Hotspot - Full Client Audit & Management Tool
#
# REPORT SECTIONS
#   1. Authorized  - mac-hotspot.txt enriched with voucher code and status.
#                    Voucher code is extracted from the hostname field
#                    (format: guest{n}-{code}) and verified against stat/voucher.
#                    STATUS values: MULTI (USED_MULTIPLE), VALID (VALID_ONE),
#                    CONSUMED (quota exhausted, auto-purged by UniFi).
#                    ON column: YES if client is currently connected to the AP.
#   2. Pending     - guest-pending.txt enriched with live connection status
#                    and authorization flag (stat/sta)
#   3. Vouchers    - full voucher list from stat/voucher with usage stats
#
# INTERACTIVE ACTIONS (after report)
#   [1] Delete unused vouchers   - delete vouchers never activated (used=0)
#   [2] Forget clients no voucher - forget guests who connected to the portal
#                                   but never submitted a voucher code
#   [3] Delete expired vouchers  - delete vouchers past their end_time and
#                                   forget all associated client history
#   [4] Revoke by voucher code   - surgical invalidation of a single voucher:
#                                   delete from stat/voucher if still present,
#                                   unauthorize active sessions, forget all
#                                   associated MACs from stat/guest and stat/sta
#                                   Workaround for UniFi bug: stat/guest does not
#                                   distinguish manually deleted vouchers from
#                                   quota-exhausted ones (community.ui.com/31faff3e)
#   [5] Purge everything         - DELETE all vouchers and client history
#                                   (DESTRUCTIVE — requires typing YES)
#
# AUTH
#   Authenticates against UniFi OS (/api/auth/login). Requires HOTSPOT_ESSID,
#   UNIFI_CONTROLLER_URL, UNIFI_USERNAME, UNIFI_PASSWORD in uhotspot.conf
#
# DEPENDENCIES : curl, jq
# CONFIG       : /etc/uhotspot/uhotspot.conf
# LOG          : /var/log/uaudit.log
# TESTED ON    : Ubuntu 24.04 - UniFi OS Network 10.x
#
################################################################################

printf "\n"
echo "UniFi Clients Audit - starting, please wait..."

set -uo pipefail


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
LOG="/var/log/uaudit.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ── Authentication ────────────────────────────────────────────────────────────
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
        --connect-timeout 10 --max-time 40 \
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
        --connect-timeout 10 --max-time 30 \
        -H "X-CSRF-Token: $CSRF_TOKEN" \
        -H "Cookie: $SESSION_COOKIE" \
        "$BASE/$1"
}

api_post() {
    curl -sk -X POST \
        --connect-timeout 10 --max-time 30 \
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
# VOUCHER RESOLUTION STRATEGY:
#   1. Extract voucher code from hostname field in mac-hotspot.txt
#      (format: guest{n}-{voucher_code}, e.g. guest3-7708162928)
#      This is always available even when the client is disconnected,
#      because uhotspot.sh writes it at authorization time.
#   2. Verify the code exists in stat/voucher (API) and enrich with status.
#      If found: show as CODE(STATUS)  e.g. 7708162928(USED_MULTIPLE)
#      If not found in stat/voucher: quota exhausted and auto-purged by UniFi, show as CODE(CONSUMED)
#   3. Fallback: if hostname has no voucher code, query stat/guest by MAC.
#      This covers clients still connected whose session is in stat/guest.
#   4. If neither source yields a code: show N/A.
print_authorized() {
    local ACL_HOTSPOT="/etc/uhotspot/mac-hotspot.txt"
    [ ! -f "$ACL_HOTSPOT" ] && return

    echo ""
    echo "============================================================================"
    echo " AUTHORIZED — mac-hotspot.txt"
    echo "============================================================================"

    local sta_map
    sta_map=$(echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.essid == $essid)
        | [(.mac | ascii_downcase), (if .authorized == true then "YES" else "NO" end)]
        | @tsv
    ' 2>/dev/null)

    {
        printf "MAC|IP|CODE|STATUS|EXPIRES|ON\n"
        while IFS=';' read -r status mac ip hostname end_time _; do
            [ "$status" != "a" ] && continue
            [ -z "$mac" ] && continue

            expires="N/A"
            [ -n "$end_time" ] && expires=$(date -d "@$end_time" '+%m-%d %H:%M' 2>/dev/null || echo "$end_time")

            # Step 1: extract code from hostname (guest{n}-{code})
            voucher=$(echo "$hostname" | sed -n 's/^guest[0-9]*-\([0-9]*\)$/\1/p')

            # Step 2: verify against stat/voucher API and get status
            vcode=""
            vstatus=""
            if [ -n "$voucher" ]; then
                vcode="$voucher"
                vstatus=$(echo "$VOUCHER" | jq -r --arg code "$voucher" '
                    .data[] | select(.code == $code) | .status // ""
                ' 2>/dev/null | head -1)
                [ -z "$vstatus" ] && vstatus="CONSUMED"
            else
                # Step 3: fallback to stat/guest by MAC
                vcode=$(echo "$GUEST" | jq -r --arg m "$mac" '
                    .data[]
                    | select((.mac | ascii_downcase) == $m)
                    | .voucher_code // ""
                ' 2>/dev/null | head -1)
                if [ -n "$vcode" ]; then
                    vstatus=$(echo "$VOUCHER" | jq -r --arg code "$vcode" '
                        .data[] | select(.code == $code) | .status // ""
                    ' 2>/dev/null | head -1)
                    [ -z "$vstatus" ] && vstatus="CONSUMED"
                fi
            fi

            # Step 4: nothing found
            [ -z "$vcode" ] && vcode="N/A"
            [ -z "$vstatus" ] && vstatus="N/A"
            vstatus=$(echo "$vstatus" | sed 's/USED_MULTIPLE/MULTI/;s/VALID_ONE/VALID/;s/VALID_MULTI/MULTI/')

            connected=$(echo "$sta_map" | awk -v mac="${mac}" 'tolower($1) == tolower(mac) {print "YES"}' FS='\t')
            [ -z "$connected" ] && connected="NO"

            echo "$mac|$ip|$vcode|$vstatus|$expires|$connected"
        done < "$ACL_HOTSPOT"
    } | column -t -s '|'
    echo ""
}

# ── Section 2: Pending clients (guest-pending.txt + stat/sta) ────────────────
print_pending() {
    local ACL_PENDING="/etc/uhotspot/guest-pending.txt"
    [ ! -f "$ACL_PENDING" ] && return

    echo ""
    echo "============================================================================"
    echo " PENDING — guest-pending.txt"
    echo "============================================================================"

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
    echo "============================================================================"
    echo " VOUCHERS — stat/voucher"
    echo "============================================================================"
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
interactive_delete_unused() {
    echo ""
    echo "============================================================================"
    echo " DELETE UNUSED VOUCHERS - vouchers that have never been activated"
    echo "============================================================================"

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
interactive_forget_no_voucher() {
    echo ""
    echo "============================================================================"
    echo " FORGET CLIENTS WITHOUT VOUCHER - connected to portal but never used one"
    echo "============================================================================"

    if [[ "$GUEST_RC" != "ok" ]]; then
        echo "  ERROR: stat/guest data unavailable (rc=$GUEST_RC) — aborting to prevent unintended mass-forget."
        return
    fi
    if [[ "$STA_RC" != "ok" ]]; then
        echo "  ERROR: stat/sta data unavailable (rc=$STA_RC) — aborting to prevent unintended mass-forget."
        return
    fi

    local ALLUSER
    ALLUSER=$(api_get "rest/user")
    local ALLUSER_RC
    ALLUSER_RC=$(echo "$ALLUSER" | jq -r '.meta.rc // "error"' 2>/dev/null)
    if [ "$ALLUSER_RC" != "ok" ]; then
        echo "  ERROR: Could not fetch rest/user (rc=$ALLUSER_RC)"
        return
    fi

    local guest_macs
    guest_macs=$(echo "$GUEST" | jq -r '
        .data[]
        | select(.voucher_code != null and .voucher_code != "")
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

    local sta_macs
    sta_macs=$(echo "$STA" | jq -r --arg essid "$HOTSPOT_ESSID" '
        .data[]
        | select(.essid == $essid)
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

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
interactive_delete_expired() {
    local now
    now=$(date +%s)

    echo ""
    echo "============================================================================"
    echo " DELETE EXPIRED VOUCHERS + FORGET THEIR CLIENTS"
    echo "============================================================================"

    if [[ "$VCH_RC" != "ok" ]]; then
        echo "  ERROR: stat/voucher data unavailable (rc=$VCH_RC) — aborting."
        return
    fi
    if [[ "$STA_RC" != "ok" ]]; then
        echo "  ERROR: stat/sta data unavailable (rc=$STA_RC) — aborting to prevent unintended client disconnect."
        return
    fi
    if [[ "$GUEST_RC" != "ok" ]]; then
        echo "  ERROR: stat/guest data unavailable (rc=$GUEST_RC) — aborting to prevent unintended client forget."
        return
    fi

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

        rc=$(api_post "cmd/hotspot" "{\"cmd\":\"delete-voucher\",\"_id\":\"${vid}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        if [ "$rc" = "ok" ]; then
            echo "  Deleted voucher: $code"
        else
            echo "  Failed to delete voucher: $code — skipping its clients"
            continue
        fi

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
interactive_purge_all() {
    if [[ "$VCH_RC" != "ok" ]]; then
        echo "  ERROR: stat/voucher data unavailable (rc=$VCH_RC) — aborting purge."
        return
    fi
    if [[ "$STA_RC" != "ok" ]]; then
        echo "  ERROR: stat/sta data unavailable (rc=$STA_RC) — aborting purge."
        return
    fi
    if [[ "$GUEST_RC" != "ok" ]]; then
        echo "  ERROR: stat/guest data unavailable (rc=$GUEST_RC) — aborting purge."
        return
    fi

    local voucher_total sta_total guest_total
    voucher_total=$(echo "$VOUCHER" | jq -r '.data | length' 2>/dev/null || echo "?")
    sta_total=$(echo "$STA"     | jq -r '.data | length' 2>/dev/null || echo "?")
    guest_total=$(echo "$GUEST" | jq -r '.data | length' 2>/dev/null || echo "?")

    echo ""
    echo "============================================================================"
    echo " PURGE ALL — THIS WILL DESTROY ALL VOUCHERS AND CLIENT HISTORY"
    echo "============================================================================"
    echo ""
    echo "  Impact summary:"
    echo "    - Vouchers to delete    : $voucher_total  (stat/voucher)"
    echo "    - Active sessions to cut: $sta_total  (stat/sta)"
    echo "    - Client records to erase: $guest_total  (stat/guest)"
    echo ""
    echo "  This action will:"
    echo "    - DELETE all vouchers — all codes become immediately invalid"
    echo "    - DISCONNECT all currently connected guests"
    echo "    - ERASE all guest history — clients will be unknown to UniFi"
    echo ""
    echo "============================================================================"
    echo "  !!            THIS ACTION CANNOT BE UNDONE                        !!"
    echo "============================================================================"
    echo ""
    read -rp "  Are you sure you want to proceed? [y/N]: " PRECONFIRM
    [[ ! "$PRECONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo ""
    echo "  Final confirmation required."
    echo "  Type the word YES (uppercase) to execute the purge:"
    echo ""
    read -rp "  > " CONFIRM
    [[ "$CONFIRM" != "YES" ]] && echo "  Cancelled." && return

    echo ""

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

# ── Interactive [5]: revoke voucher by code (workaround for UniFi bug) ────────
interactive_revoke_by_code() {
    echo ""
    echo "============================================================================"
    echo " REVOKE BY VOUCHER CODE — surgical invalidation (UniFi workaround)"
    echo "============================================================================"

    if [[ "$VCH_RC" != "ok" ]]; then
        echo "  ERROR: stat/voucher data unavailable (rc=$VCH_RC) — aborting."
        return
    fi
    if [[ "$GUEST_RC" != "ok" ]]; then
        echo "  ERROR: stat/guest data unavailable (rc=$GUEST_RC) — aborting to prevent unintended client forget."
        return
    fi
    if [[ "$STA_RC" != "ok" ]]; then
        echo "  ERROR: stat/sta data unavailable (rc=$STA_RC) — aborting to prevent unintended client disconnect."
        return
    fi

    mapfile -t ACTIVE_VOUCHERS < <(echo "$VOUCHER" | jq -r '
        .data[]
        | select(.used > 0)
        | [.code, (.note // "—"), (.used | tostring)]
        | @tsv
    ' 2>/dev/null | sort -t$'\t' -k2)

    if [ ${#ACTIVE_VOUCHERS[@]} -eq 0 ]; then
        echo ""
        echo "  No active vouchers found (used > 0)."
        return
    fi

    echo ""
    echo "  Active vouchers:"
    echo ""
    printf "  %-15s  %-20s  %s\n" "CODE" "NAME" "USED"
    printf "  %-15s  %-20s  %s\n" "---------------" "--------------------" "----"
    for row in "${ACTIVE_VOUCHERS[@]}"; do
        local code note used
        code=$(echo "$row" | awk -F'\t' '{print $1}')
        note=$(echo "$row" | awk -F'\t' '{print $2}')
        used=$(echo "$row" | awk -F'\t' '{print $3}')
        printf "  %-15s  %-20s  %s\n" "$code" "$note" "$used"
    done

    echo ""
    echo "  NOTE: This list shows vouchers currently reported by stat/voucher."
    echo "  Vouchers deleted manually from the UniFi UI will not appear here"
    echo "  but can still be revoked — enter their code directly if you know it."
    echo ""
    read -rp "  Enter voucher code to revoke: " TARGET_CODE
    TARGET_CODE=$(echo "$TARGET_CODE" | tr -d '[:space:]')

    if [ -z "$TARGET_CODE" ]; then
        echo "  No code entered. Cancelled."
        return
    fi

    local target_note
    target_note=$(printf '%s\n' "${ACTIVE_VOUCHERS[@]}" | awk -F'\t' -v code="$TARGET_CODE" '$1 == code {print $2}')
    [ -z "$target_note" ] && target_note="manually deleted — not in stat/voucher"

    echo ""
    echo "  Code : $TARGET_CODE"
    echo "  Name : $target_note"
    echo ""

    local voucher_id
    voucher_id=$(echo "$VOUCHER" | jq -r --arg code "$TARGET_CODE" '
        .data[] | select(.code == $code) | ._id
    ' 2>/dev/null | head -1)

    if [ -n "$voucher_id" ]; then
        local rc
        rc=$(api_post "cmd/hotspot" "{\"cmd\":\"delete-voucher\",\"_id\":\"${voucher_id}\"}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$rc" = "ok" ] \
            && echo "  Deleted voucher: $TARGET_CODE" \
            || echo "  WARNING: Failed to delete voucher from stat/voucher (rc=$rc)"
    else
        echo "  Voucher not in stat/voucher (manually deleted) — proceeding with cleanup..."
    fi

    mapfile -t GUEST_MACS < <(echo "$GUEST" | jq -r --arg code "$TARGET_CODE" '
        .data[]
        | select(.voucher_code == $code)
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

    mapfile -t STA_MACS < <(echo "$STA" | jq -r --arg code "$TARGET_CODE" '
        .data[]
        | select(.voucher_code == $code)
        | (.mac | ascii_downcase)
    ' 2>/dev/null | sort -u)

    mapfile -t ALL_MACS < <(printf '%s\n' "${GUEST_MACS[@]}" "${STA_MACS[@]}" | sort -u)

    if [ ${#ALL_MACS[@]} -eq 0 ]; then
        echo ""
        echo "  No client records found linked to code: $TARGET_CODE"
        echo "  Done."
        return
    fi

    echo ""
    echo "  Client records linked to this code (${#ALL_MACS[@]}):"
    echo ""
    for mac in "${ALL_MACS[@]}"; do
        local hostname
        hostname=$(echo "$GUEST" | jq -r --arg m "$mac" '
            .data[] | select((.mac | ascii_downcase) == $m) | .hostname // "N/A"
        ' 2>/dev/null | head -1)
        local active_flag=""
        echo "$STA" | jq -e --arg m "$mac" \
            '.data[] | select((.mac | ascii_downcase) == $m)' &>/dev/null \
            && active_flag=" [CONNECTED]"
        printf "    %-20s  %-25s%s\n" "$mac" "$hostname" "$active_flag"
    done

    echo ""
    read -rp "  Confirm revocation of ${#ALL_MACS[@]} client(s) for code $TARGET_CODE? [y/N]: " CONFIRM
    [[ ! "$CONFIRM" =~ ^[yY]$ ]] && echo "  Cancelled." && return

    echo ""

    for mac in "${ALL_MACS[@]}"; do
        local is_active
        is_active=$(echo "$STA" | jq -r --arg m "$mac" '
            .data[] | select((.mac | ascii_downcase) == $m) | .mac
        ' 2>/dev/null | head -1)

        if [ -n "$is_active" ]; then
            local unauth_rc
            unauth_rc=$(api_post "cmd/stamgr" \
                "{\"cmd\":\"unauthorize-guest\",\"mac\":\"${mac}\"}" \
                | jq -r '.meta.rc // "error"' 2>/dev/null)
            [ "$unauth_rc" = "ok" ] \
                && echo "  Unauthorized: $mac" \
                || echo "  WARNING: Failed to unauthorize: $mac (rc=$unauth_rc)"
        fi

        local frc
        frc=$(api_post "cmd/stamgr" \
            "{\"cmd\":\"forget-sta\",\"macs\":[\"${mac}\"]}" \
            | jq -r '.meta.rc // "error"' 2>/dev/null)
        [ "$frc" = "ok" ] \
            && echo "  Forgotten: $mac" \
            || echo "  WARNING: Failed to forget: $mac (rc=$frc)"
    done

    echo ""
    echo "  Revocation complete for code: $TARGET_CODE ($target_note)"
}

# ── Interactive action menu ───────────────────────────────────────────────────
echo ""
echo "============================================================================"
echo " AVAILABLE ACTIONS"
echo "============================================================================"
echo "  [1] Delete unused vouchers   - never activated"
echo "  [2] Forget clients no voucher - never used a voucher"
echo "  [3] Delete expired vouchers  - remove + forget their clients"
echo "  [4] Revoke by voucher code   - surgical invalidation by code"
echo "  [5] Purge everything         - DELETE all vouchers and history"
echo "  [q] Quit"
echo ""
read -rp "  Your choice: " ACTION

case "$ACTION" in
    1) interactive_delete_unused ;;
    2) interactive_forget_no_voucher ;;
    3) interactive_delete_expired ;;
    4) interactive_revoke_by_code ;;
    5) interactive_purge_all ;;
    q|Q) echo "  Goodbye." ;;
    *) echo "  Invalid option. Exiting." ;;
esac

echo ""
