#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata
# Captures dest_ip from Suricata alerts matching drop.conf signatures and
# feeds /etc/suricata/suridata.txt -- the same plain IP-list format
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
# NO EXPIRY: once an IP is added, it stays -- same model as blockports.txt
# (manually curated, never auto-pruned). If a false positive slips in,
# remove it by hand from suridata.txt and re-run this script.
#
# LOCAL EXCLUSION: dest_ip values inside the server's own LAN (SERV_SUBNET,
# assumed /24) or inside the WAN interface's own /24 are never written to
# suridata.txt -- a false/positive alert against your own network must not
# result in the firewall blocking your own gateway, WAN uplink, or LAN
# hosts. On every run, any LAN/WAN IP already present from before this
# exclusion existed is also purged from suridata.txt and from the live
# ipset. SERV_SUBNET follows the same "${VAR:-default}" fallback pattern
# already used by iptables.sh, so this script can run standalone even if
# nothing exports it. The WAN side has no such fixed value (DHCP/ISP-
# assigned, can change), so its /24 is resolved at runtime from wan_iface
# via `ip addr show` instead of a fallback constant.
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

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep in jq ipset iptables coreutils grep; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -- abort"
        exit 1
    fi
done

# validation -- one variable per thing validated; use directly with =~
UH_OCT='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'
UH_NETMASK='^(0\.0\.0\.0|128\.0\.0\.0|192\.0\.0\.0|224\.0\.0\.0|240\.0\.0\.0|248\.0\.0\.0|252\.0\.0\.0|254\.0\.0\.0|255\.0\.0\.0|255\.128\.0\.0|255\.192\.0\.0|255\.224\.0\.0|255\.240\.0\.0|255\.248\.0\.0|255\.252\.0\.0|255\.254\.0\.0|255\.255\.0\.0|255\.255\.128\.0|255\.255\.192\.0|255\.255\.224\.0|255\.255\.240\.0|255\.255\.248\.0|255\.255\.252\.0|255\.255\.254\.0|255\.255\.255\.0|255\.255\.255\.128|255\.255\.255\.192|255\.255\.255\.224|255\.255\.255\.240|255\.255\.255\.248|255\.255\.255\.252|255\.255\.255\.254|255\.255\.255\.255)$'
UH_DNS='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])(,(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9]))*$'
UH_UINT='^(0|[1-9][0-9]*)$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
UH_MAC_RE='([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}'
UH_MAC="^${UH_MAC_RE}$"
UH_PREFIX='0.0.0.0:0 128.0.0.0:1 192.0.0.0:2 224.0.0.0:3 240.0.0.0:4 248.0.0.0:5 252.0.0.0:6 254.0.0.0:7 255.0.0.0:8 255.128.0.0:9 255.192.0.0:10 255.224.0.0:11 255.240.0.0:12 255.248.0.0:13 255.252.0.0:14 255.254.0.0:15 255.255.0.0:16 255.255.128.0:17 255.255.192.0:18 255.255.224.0:19 255.255.240.0:20 255.255.248.0:21 255.255.252.0:22 255.255.254.0:23 255.255.255.0:24 255.255.255.128:25 255.255.255.192:26 255.255.255.224:27 255.255.255.240:28 255.255.255.248:29 255.255.255.252:30 255.255.255.254:31 255.255.255.255:32'

log "suridata start..."

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

rules_file="/var/lib/suricata/rules/suricata.rules"
eve_log="/var/log/suricata/eve.json"
offset_file="/var/lib/suricata/suridata.offset"
sids_file="/var/lib/suricata/suridata.sids"
out_file="/etc/suricata/suridata.txt"

# network identity -- same "${VAR:-default}" fallback style as iptables.sh,
# so this script still runs standalone if nothing exports these first.
wan_iface="eth0"
SERV_SUBNET="${SERV_SUBNET:-192.168.0.0}"

for f in "$rules_file" "$eve_log"; do
    if [ ! -f "$f" ]; then
        log "ERROR: required file not found: $f -- abort"
        exit 1
    fi
done
touch "$out_file"

# -- LAN/WAN exclusion prefixes -----------------------------------------------
# Assumes /24, same convention as the rest of this project (blockports.txt
# etc.). lan_prefix comes straight from SERV_SUBNET (fixed, known value).
# wan_prefix has no fixed value to fall back on -- the WAN IP is
# ISP/DHCP-assigned and can change, so it's resolved at runtime from
# wan_iface. If it can't be resolved (interface down, not yet up), WAN
# exclusion is simply skipped for this run and logged, without aborting.
if [[ "$SERV_SUBNET" =~ $UH_IPV4 ]]; then
    lan_prefix="${SERV_SUBNET%.*}."
else
    log "WARNING: SERV_SUBNET '$SERV_SUBNET' is not a valid IPv4 -- LAN exclusion disabled this run"
    lan_prefix=""
fi

wan_ip=$(ip -4 -o addr show "$wan_iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
if [[ "$wan_ip" =~ $UH_IPV4 ]]; then
    wan_prefix="${wan_ip%.*}."
else
    log "WARNING: could not resolve IP for wan_iface=$wan_iface -- WAN exclusion disabled this run"
    wan_prefix=""
fi

# -- Step 0: retroactively purge already-listed LAN/WAN IPs ------------------
# The filter in Step 3 only stops NEW IPs from being added -- it does
# nothing for IPs that were written to out_file (or the live ipset) before
# this exclusion existed, or from a run where lan_prefix/wan_prefix
# resolution failed. This pass removes them retroactively on every run.
if [ -n "$lan_prefix" ] || [ -n "$wan_prefix" ]; then
    purged=0
    clean_file=$(mktemp)
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        if { [ -n "$lan_prefix" ] && [[ "$ip" == "$lan_prefix"* ]]; } || \
           { [ -n "$wan_prefix" ] && [[ "$ip" == "$wan_prefix"* ]]; }; then
            log "INFO: $ip removed (LAN/WAN range)"
            ipset del suridata "$ip" 2>/dev/null || true
            (( purged++ )) || true
            continue
        fi
        echo "$ip" >> "$clean_file"
    done < "$out_file"
    if (( purged > 0 )); then
        mv "$clean_file" "$out_file"
        log "$purged local IP(s) purged"
    else
        rm -f "$clean_file"
    fi
fi

# -- Step 1: SIDs currently resolved to "drop" by suricata-update ------------
mapfile -t drop_sids < <(grep '^drop ' "$rules_file" 2>/dev/null | grep -oP 'sid:\K\d+' | sort -u)
if [ "${#drop_sids[@]}" -eq 0 ]; then
    log "WARNING: no drop-action SIDs found in $rules_file"
    log "WARNING: nothing to match this run -- skip"
    exit 0
fi

# SID maps are passed to jq via --slurpfile (file), never --argjson (argv):
# drop.conf's broad re: categories (ET MALWARE, ET PHISHING, ...) resolve to
# tens of thousands of SIDs, and that JSON blob blows past the shell's
# argument-length limit -- jq fails with "argument list too long" and, since
# earlier versions of this script piped stderr to /dev/null, that failure
# was silent and every run just logged "No new IPs this run".
sid_map_file=$(mktemp)
new_sid_map_file=$(mktemp)
sid_grep_file=$(mktemp)
trap 'rm -f "$sid_map_file" "$new_sid_map_file" "$sid_grep_file"' EXIT
printf '%s\n' "${drop_sids[@]}" | jq -R 'select(length>0)' | jq -s 'map({(.): true}) | add' > "$sid_map_file"

# -- Step 1b: SIDs newly resolved to drop since the last run -----------------
# suricataupdate.sh runs once a day; any alert for a SID that already
# happened before its conversion to drop would otherwise be lost forever,
# since Step 2 below only tails NEW eve.json content. Backfill by doing a
# one-time full scan restricted to just the newly-dropped SIDs.
touch "$sids_file"
mapfile -t new_sids < <(comm -23 <(printf '%s\n' "${drop_sids[@]}") <(sort -u "$sids_file"))
printf '%s\n' "${drop_sids[@]}" > "$sids_file"

backfill_ips=""
if [ "${#new_sids[@]}" -gt 0 ]; then
    log "INFO: ${#new_sids[@]} SID(s) newly resolved to drop"
    log "INFO: rescanning full eve.json for them"
    printf '%s\n' "${new_sids[@]}" | jq -R 'select(length>0)' | jq -s 'map({(.): true}) | add' > "$new_sid_map_file"
    # Cheap text pre-filter before the expensive JSON parse: grep -F over
    # the whole file is far faster than jq parsing every line, and it's
    # safe to over-match (e.g. SID 201787 also matches inside 2017871) --
    # jq's exact-key lookup below still discards anything that isn't a
    # real match, this step only cuts down how much jq has to parse.
    printf '"signature_id":%s\n' "${new_sids[@]}" > "$sid_grep_file"
    backfill_ips=$(grep -aF -f "$sid_grep_file" "$eve_log" | jq -r --slurpfile sids "$new_sid_map_file" '
        select(.event_type=="alert")
        | select(.alert.signature_id != null)
        | select($sids[0][(.alert.signature_id|tostring)] == true)
        | .dest_ip
    ' 2>>"$log_file")
    backfill_ips=$(printf '%s' "$backfill_ips" | sort -u)
fi

# -- Step 2: read only what's new in eve.json since the last run -------------
current_size=$(stat -c%s "$eve_log" 2>/dev/null || echo 0)
last_offset=0
if [ -f "$offset_file" ]; then
    last_offset=$(cat "$offset_file" 2>/dev/null)
    [[ "$last_offset" =~ $UH_UINT ]] || last_offset=0
fi
if (( last_offset > current_size )); then
    log "INFO: eve.json truncated -- offset reset to 0"
    last_offset=0
fi

new_ips=""
jq_failed=0
if (( current_size > last_offset )); then
    new_ips=$(tail -c "+$((last_offset + 1))" "$eve_log" 2>/dev/null | jq -r --slurpfile sids "$sid_map_file" '
        select(.event_type=="alert")
        | select(.alert.signature_id != null)
        | select($sids[0][(.alert.signature_id|tostring)] == true)
        | .dest_ip
    ' 2>>"$log_file" | sort -u) || jq_failed=1
fi
if (( jq_failed )); then
    log "WARNING: jq failed parsing new eve.json content -- offset NOT advanced, will retry this segment next run"
else
    echo "$current_size" > "$offset_file"
fi

new_ips=$(printf '%s\n%s\n' "$new_ips" "$backfill_ips" | sed '/^$/d' | sort -u)

# -- Step 3: append new, valid, not-yet-listed, non-local IPs ----------------
added=0
if [ -n "$new_ips" ]; then
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        [[ "$ip" =~ $UH_IPV4 ]] || continue
        # exclude LAN subnet and WAN interface's own /24
        [ -n "$lan_prefix" ] && [[ "$ip" == "$lan_prefix"* ]] && continue
        [ -n "$wan_prefix" ] && [[ "$ip" == "$wan_prefix"* ]] && continue
        grep -qxF "$ip" "$out_file" 2>/dev/null && continue
        echo "$ip" >> "$out_file"
        log "INFO: $ip added to suridata.txt"
        (( added++ )) || true
    done <<< "$new_ips"
fi

if (( added == 0 )); then
    log "INFO: no new IPs this run"
else
    log "INFO: $added new IP(s) added"
    sort -t . -k1,1n -k2,2n -k3,3n -k4,4n -o "$out_file" "$out_file"
fi

# -- Step 4: patch the live ipset so the block applies before the next -------
# firewall reload -- iptables.sh remains the source of truth for the rule
# itself (ipset creation + FORWARD drop), this only keeps membership current
# between reloads.
if ipset list suridata &>/dev/null; then
    while IFS= read -r ip; do
        [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
        [[ "$ip" =~ $UH_IPV4 ]] && ipset add suridata "$ip" -exist
    done < "$out_file"
else
    log "INFO: ipset 'suridata' does not exist yet -- run iptables.sh once to create it"
fi

log "suridata done at: $(date '+%Y-%m-%d %H:%M:%S')"
