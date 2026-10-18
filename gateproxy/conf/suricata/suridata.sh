#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata
#
# USAGE:
# sudo ./suridata.sh
#
# LOG: /var/log/suricata/suricatacron.log
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/suricata/suricatacron.log"
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies
for dep in jq ipset iptables coreutils grep; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_UINT='^(0|[1-9][0-9]*)$'

rules_file="/var/lib/suricata/rules/suricata.rules"
eve_log="/var/log/suricata/eve.json"
offset_file="/var/lib/suricata/suridata.offset"
sids_file="/var/lib/suricata/suridata.sids"
out_file="/etc/suricata/suridata.txt"

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
pydhcp_env="/etc/pydhcp/pydhcp.env"
env_specs=("$pydhcp_env root:pydhcpd 640")
for env_spec in "${env_specs[@]}"; do
    read -r env_path env_owner_want env_perms_want <<< "$env_spec"
    if [ ! -f "$env_path" ]; then
        log "ERROR: $(basename "$env_path") not found -abort"
        exit 1
    fi
    env_owner=$(stat -c '%U:%G' "$env_path" 2>/dev/null)
    env_perms=$(stat -c '%a' "$env_path" 2>/dev/null)
    if [[ "$env_owner" != "$env_owner_want" ]] \
       || [[ "$env_perms" != "$env_perms_want" ]]; then
        if chown "$env_owner_want" "$env_path" 2>/dev/null \
           && chmod "$env_perms_want" "$env_path" 2>/dev/null; then
            log "INFO: $(basename "$env_path") perms fixed -fixed"
        else
            log "ERROR: cannot fix $(basename "$env_path") perms -abort"
            exit 1
        fi
    fi
done
unset env_specs env_spec env_path env_owner_want env_perms_want
unset env_owner env_perms

# LOAD_CONF
# Read known key=value pairs from a config file, without sourcing it
load_conf() {
    local conf_file="$1" env_key env_value env_line
    [[ ! -f "$conf_file" ]] && { log "WARNING: $conf_file not found -fallback"; return 1; }
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            log "ERROR: malformed line in $(basename "$conf_file"): '$env_line' -abort"
            exit 1
        fi
        case "$env_key" in
            WAN_IFACE|SERV_SUBNET)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}

# LOAD
# Reads pydhcp.env; a missing file is handled by the check below
load_conf "$pydhcp_env" || true

# KEY CHECK
# Collect every failure first, then decide -- a single abort reports them all
key_errors=()
if ! grep -q "^WAN_IFACE=" "$pydhcp_env"; then
    key_errors+=("WAN_IFACE missing line")
elif [[ -z "${WAN_IFACE:-}" ]]; then
    key_errors+=("WAN_IFACE not set")
fi
if ! grep -q "^SERV_SUBNET=" "$pydhcp_env"; then
    key_errors+=("SERV_SUBNET missing line")
elif [[ -z "${SERV_SUBNET:-}" ]]; then
    key_errors+=("SERV_SUBNET not set")
elif ! [[ "$SERV_SUBNET" =~ $UH_IPV4 ]]; then
    key_errors+=("SERV_SUBNET invalid IPv4")
fi
if (( ${#key_errors[@]} > 0 )); then
    for key_error in "${key_errors[@]}"; do
        log "ERROR: $key_error -abort"
    done
    log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$pydhcp_env") -abort"
    exit 1
fi
unset key_errors key_error

# FALLBACK
# Default values used when a key is absent, each one logged
if [ -z "${WAN_IFACE:-}" ]; then
    log "WARNING: no WAN_IFACE in pydhcp.env -fallback"
fi
wan_iface="${WAN_IFACE:-eth0}"
if [ -z "${SERV_SUBNET:-}" ]; then
    log "WARNING: no SERV_SUBNET in pydhcp.env -fallback"
fi
SERV_SUBNET="${SERV_SUBNET:-192.168.0.0}"

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "suridata start..."

for f in "$rules_file" "$eve_log"; do
    if [ ! -f "$f" ]; then
        log "ERROR: required file not found: $f -abort"
        exit 1
    fi
done
touch "$out_file"

# EXCLUSION PREFIXES
# The LAN and WAN /24 prefixes that must never be blocked.
# Assumes /24, same convention as the rest of this project (blockports.txt
# etc.). lan_prefix comes straight from SERV_SUBNET (fixed, known value).
# wan_prefix has no fixed value to fall back on -- the WAN IP is
# ISP/DHCP-assigned and can change, so it's resolved at runtime from
# wan_iface. If it can't be resolved (interface down, not yet up), WAN
# exclusion is simply skipped for this run and logged, without aborting.
lan_prefix="${SERV_SUBNET%.*}."

wan_ip=$(ip -4 -o addr show "$wan_iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
if [[ "$wan_ip" =~ $UH_IPV4 ]]; then
    wan_prefix="${wan_ip%.*}."
else
    log "WARNING: WAN IP unresolved; exclusion skipped -fallback"
    wan_prefix=""
fi

# LOCAL IP PURGE
# Removes LAN/WAN IPs that were already listed by an earlier run.
# The append filter below only stops NEW IPs from being added -- it does
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

# DROP SIDS
# The SIDs that suricata-update currently resolves to the drop action
mapfile -t drop_sids < <(grep '^drop ' "$rules_file" 2>/dev/null | grep -oP 'sid:\K\d+' | sort -u)
if [ "${#drop_sids[@]}" -eq 0 ]; then
    log "INFO: no drop-action SIDs found in $rules_file"
    log "INFO: nothing to match this run -skip"
    log "suridata done at: $(date '+%Y-%m-%d %H:%M:%S')"
    exit 0
fi

# SID maps are passed to jq via --slurpfile (file), never --argjson (argv):
# drop.conf's broad re: categories (ET MALWARE, ET PHISHING, ...) resolve to
# tens of thousands of SIDs, and that JSON blob blows past the shell's
# argument-length limit -- jq fails with "argument list too long".
sid_map_file=$(mktemp)
new_sid_map_file=$(mktemp)
sid_grep_file=$(mktemp)
backfill_raw_file=$(mktemp)
trap 'rm -f "$sid_map_file" "$new_sid_map_file" "$sid_grep_file" "$backfill_raw_file"' EXIT
if ! printf '%s\n' "${drop_sids[@]}" | jq -R 'select(length>0)' | jq -s 'map({(.): true}) | add' > "$sid_map_file"; then
    log "ERROR: failed to build drop SID map -abort"
    exit 1
fi

# NEW DROP SIDS
# The SIDs that became drop since the last run, plus their past alerts.
# suricataupdate.sh runs once a day; any alert for a SID that already
# happened before its conversion to drop would otherwise be lost forever,
# since the scan below only tails NEW eve.json content. Backfill by doing a
# one-time full scan restricted to just the newly-dropped SIDs.
touch "$sids_file"
mapfile -t new_sids < <(comm -23 <(printf '%s\n' "${drop_sids[@]}") <(sort -u "$sids_file"))

backfill_ips=""
backfill_failed=0
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
    # grep's exit status is discarded on purpose: no match means the SID has
    # no history in eve.json, which is normal. Only jq's status is read, so
    # the two cases stay apart.
    grep -aF -f "$sid_grep_file" "$eve_log" > "$backfill_raw_file" || true
    backfill_ips=$(jq -r --slurpfile sids "$new_sid_map_file" '
        select(.event_type=="alert")
        | select(.alert.signature_id != null)
        | select($sids[0][(.alert.signature_id|tostring)] == true)
        | .dest_ip
    ' "$backfill_raw_file" 2>>"$log_file") || backfill_failed=1
    backfill_ips=$(printf '%s' "$backfill_ips" | sort -u)
fi

# the SID list only advances when its rescan finished: a failed backfill stays
# pending so the next run retries it, same criterion the eve scan uses
if (( backfill_failed )); then
    log "WARNING: jq failed rescanning eve.json for new SIDs"
    log "WARNING: they stay pending, retried next run -alert"
elif ! printf '%s\n' "${drop_sids[@]}" > "$sids_file"; then
    log "WARNING: cannot update $(basename "$sids_file")"
    log "WARNING: SID list may be incomplete -alert"
fi

# EVE JSON
# Reads only what eve.json grew since the last run, by saved offset
current_size=$(stat -c%s "$eve_log" 2>/dev/null || echo 0)
last_offset=0
if [ -f "$offset_file" ]; then
    last_offset=$(cat "$offset_file" 2>/dev/null)
    [[ "$last_offset" =~ $UH_UINT ]] || last_offset=0
fi
if ! [ "$last_offset" -le "$current_size" ] 2>/dev/null; then
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
    log "WARNING: eve.json parse failed; retry next run -alert"
else
    echo "$current_size" > "$offset_file"
fi

new_ips=$(printf '%s\n%s\n' "$new_ips" "$backfill_ips" | sed '/^$/d' | sort -u)

# NEW IPS
# Appends the valid, not-yet-listed, non-local IPs to suridata.txt
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

# IPSET UPDATE
# Patches the live ipset so the block applies before the next firewall
# reload. iptables.sh remains the source of truth for the rule itself
# (ipset creation + FORWARD drop); this only keeps membership current
# between reloads.
if ipset list suridata &>/dev/null; then
    while IFS= read -r ip; do
        [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
        [[ "$ip" =~ $UH_IPV4 ]] && ipset add suridata "$ip" -exist
    done < "$out_file"
else
    log "INFO: ipset 'suridata' does not exist yet -skip"
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "suridata done at: $(date '+%Y-%m-%d %H:%M:%S')"
