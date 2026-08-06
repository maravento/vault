#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata
# Captures dest_ip from Suricata alerts matching drop.conf signatures and
# feeds /etc/acl/acl_ipt/suridata.txt -- the same plain IP-list format
# blockports.txt already uses. Suricata itself never blocks anything (it
# runs passive/IDS, see steps.md in caso_suricata for why NFQUEUE/IPS mode
# was rejected): this script is what turns drop.conf into a real block,
# via the ipset+iptables rule already declared in iptables.sh (uiptables.sh
# equivalent), which rebuilds the ipset from suridata.txt on every reload.
#
# Between reloads, this script also patches the live ipset directly with
# any newly found IP, so a new block takes effect within one cron cycle
# instead of waiting for the next full firewall reload.
#
# SID SOURCE: drop.conf entries are matched against ET Open's ruleset by
# suricata-update (literal SIDs or "re:" message-regex patterns) and the
# result is compiled into suricata.rules with the final action already
# resolved -- this script reads THAT file (not drop.conf) so it never has
# to re-implement regex expansion itself, and stays in sync automatically
# whenever suricataupdate.sh runs.
#
# BACKFILL: suricataupdate.sh runs once a day, so a SID can generate alerts
# for hours before it's converted to drop. On the run right after a SID
# newly becomes drop (tracked via suridata.sids), this script does a one-time
# full eve.json scan for just that SID to catch anything already logged --
# the normal tail-from-offset logic below only sees NEW alerts.
#
# No expiry: once an IP is added, it stays -- same model as blockports.txt
# (manually curated, never auto-pruned). If a false positive slips in,
# remove it by hand from suridata.txt and re-run this script.
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/suricata/suricatacron.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

# DEPENDENCIES
for dep in jq ipset iptables coreutils grep; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: Required dependency '$dep' is not installed."
        exit 1
    fi
done

log "suridata start..."

# VARIABLES
RULES_FILE="/var/lib/suricata/rules/suricata.rules"
EVE_LOG="/var/log/suricata/eve.json"
OFFSET_FILE="/var/lib/suricata/suridata.offset"
SIDS_FILE="/var/lib/suricata/suridata.sids"
ACL_IPT_PATH="/etc/acl/acl_ipt"
OUT_FILE="$ACL_IPT_PATH/suridata.txt"

is_valid_ip() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

for f in "$RULES_FILE" "$EVE_LOG"; do
    if [ ! -f "$f" ]; then
        log "ERROR: required file not found: $f"
        exit 1
    fi
done
mkdir -p "$ACL_IPT_PATH" &>/dev/null
touch "$OUT_FILE"

# -- Step 1: SIDs currently resolved to "drop" by suricata-update ------------
mapfile -t DROP_SIDS < <(grep '^drop ' "$RULES_FILE" 2>/dev/null | grep -oP 'sid:\K\d+' | sort -un)
if [ "${#DROP_SIDS[@]}" -eq 0 ]; then
    log "WARNING: no drop-action SIDs found in $RULES_FILE -- nothing to match, skipping this run"
    exit 0
fi

# SID maps are passed to jq via --slurpfile (file), never --argjson (argv):
# drop.conf's broad re: categories (ET MALWARE, ET PHISHING, ...) resolve to
# tens of thousands of SIDs, and that JSON blob blows past the shell's
# argument-length limit -- jq fails with "argument list too long" and, since
# earlier versions of this script piped stderr to /dev/null, that failure
# was silent and every run just logged "No new IPs this run".
SID_MAP_FILE=$(mktemp)
NEW_SID_MAP_FILE=$(mktemp)
SID_GREP_FILE=$(mktemp)
trap 'rm -f "$SID_MAP_FILE" "$NEW_SID_MAP_FILE" "$SID_GREP_FILE"' EXIT
printf '%s\n' "${DROP_SIDS[@]}" | jq -R 'select(length>0)' | jq -s 'map({(.): true}) | add' > "$SID_MAP_FILE"

# -- Step 1b: SIDs newly resolved to drop since the last run -----------------
# suricataupdate.sh runs once a day; any alert for a SID that already
# happened before its conversion to drop would otherwise be lost forever,
# since Step 2 below only tails NEW eve.json content. Backfill by doing a
# one-time full scan restricted to just the newly-dropped SIDs.
touch "$SIDS_FILE"
mapfile -t NEW_SIDS < <(comm -23 <(printf '%s\n' "${DROP_SIDS[@]}") <(sort -un "$SIDS_FILE"))
printf '%s\n' "${DROP_SIDS[@]}" > "$SIDS_FILE"

backfill_ips=""
if [ "${#NEW_SIDS[@]}" -gt 0 ]; then
    log "INFO: ${#NEW_SIDS[@]} SID(s) newly resolved to drop -- rescanning full eve.json for them"
    printf '%s\n' "${NEW_SIDS[@]}" | jq -R 'select(length>0)' | jq -s 'map({(.): true}) | add' > "$NEW_SID_MAP_FILE"
    # Cheap text pre-filter before the expensive JSON parse: grep -F over
    # the whole file is far faster than jq parsing every line, and it's
    # safe to over-match (e.g. SID 201787 also matches inside 2017871) --
    # jq's exact-key lookup below still discards anything that isn't a
    # real match, this step only cuts down how much jq has to parse.
    printf '"signature_id":%s\n' "${NEW_SIDS[@]}" > "$SID_GREP_FILE"
    backfill_ips=$(grep -aF -f "$SID_GREP_FILE" "$EVE_LOG" | jq -r --slurpfile sids "$NEW_SID_MAP_FILE" '
        select(.event_type=="alert")
        | select(.alert.signature_id != null)
        | select($sids[0][(.alert.signature_id|tostring)] == true)
        | .dest_ip
    ' 2>>"$log_file")
    backfill_ips=$(printf '%s' "$backfill_ips" | sort -u)
fi

# -- Step 2: read only what's new in eve.json since the last run -------------
current_size=$(stat -c%s "$EVE_LOG" 2>/dev/null || echo 0)
last_offset=0
if [ -f "$OFFSET_FILE" ]; then
    last_offset=$(cat "$OFFSET_FILE" 2>/dev/null)
    [[ "$last_offset" =~ ^[0-9]+$ ]] || last_offset=0
fi
if (( last_offset > current_size )); then
    log "INFO: eve.json truncated -- offset reset to 0"
    last_offset=0
fi

new_ips=""
if (( current_size > last_offset )); then
    new_ips=$(tail -c "+$((last_offset + 1))" "$EVE_LOG" 2>/dev/null | jq -r --slurpfile sids "$SID_MAP_FILE" '
        select(.event_type=="alert")
        | select(.alert.signature_id != null)
        | select($sids[0][(.alert.signature_id|tostring)] == true)
        | .dest_ip
    ' 2>>"$log_file" | sort -u)
fi
echo "$current_size" > "$OFFSET_FILE"

new_ips=$(printf '%s\n%s\n' "$new_ips" "$backfill_ips" | sed '/^$/d' | sort -u)

# -- Step 3: append new, valid, not-yet-listed IPs ----------------------------
added=0
if [ -n "$new_ips" ]; then
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        is_valid_ip "$ip" || continue
        grep -qxF "$ip" "$OUT_FILE" 2>/dev/null && continue
        echo "$ip" >> "$OUT_FILE"
        log "INFO: $ip added to suridata.txt"
        (( added++ )) || true
    done <<< "$new_ips"
fi

if (( added == 0 )); then
    log "No new IPs this run"
else
    log "$added new IP(s) added"
    sort -t . -k1,1n -k2,2n -k3,3n -k4,4n -o "$OUT_FILE" "$OUT_FILE"
fi

# -- Step 4: patch the live ipset so the block applies before the next -------
# firewall reload -- iptables.sh remains the source of truth for the rule
# itself (ipset creation + FORWARD drop), this only keeps membership current
# between reloads.
if ipset list suridata &>/dev/null; then
    while IFS= read -r ip; do
        [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
        is_valid_ip "$ip" && ipset add suridata "$ip" -exist
    done < "$OUT_FILE"
else
    log "INFO: ipset 'suridata' does not exist yet -- run iptables.sh once to create it"
fi

log "suridata done at: $(date)"
