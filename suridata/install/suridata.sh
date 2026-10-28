#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata
# FILE: suridata.sh
#
# USAGE:
# sudo bash suridata.sh
#
# LOG: /var/log/suridata.log
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
log_file="/var/log/suridata.log"
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
    log "ERROR: cannot open $(basename "$script_lock") -abort"
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies
for dep in jq ipset iptables ulogd2 coreutils grep iproute2 python3 util-linux sed; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q 'ok installed'; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_NETMASK='^(0\.0\.0\.0|128\.0\.0\.0|192\.0\.0\.0|224\.0\.0\.0|240\.0\.0\.0|248\.0\.0\.0|252\.0\.0\.0|254\.0\.0\.0|255\.0\.0\.0|255\.128\.0\.0|255\.192\.0\.0|255\.224\.0\.0|255\.240\.0\.0|255\.248\.0\.0|255\.252\.0\.0|255\.254\.0\.0|255\.255\.0\.0|255\.255\.128\.0|255\.255\.192\.0|255\.255\.224\.0|255\.255\.240\.0|255\.255\.248\.0|255\.255\.252\.0|255\.255\.254\.0|255\.255\.255\.0|255\.255\.255\.128|255\.255\.255\.192|255\.255\.255\.224|255\.255\.255\.240|255\.255\.255\.248|255\.255\.255\.252|255\.255\.255\.254|255\.255\.255\.255)$'
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_UINT='^(0|[1-9][0-9]*)$'

rules_file="/var/lib/suricata/rules/suricata.rules"
eve_log="/var/log/suricata/eve.json"
offset_file="/var/lib/suricata/suridata.offset"
sids_file="/var/lib/suricata/suridata.sids"
out_file="/etc/suricata/data/suridata.txt"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# LOCAL NETWORKS
# Match IPv4 addresses against the calculated LAN and WAN bounds
is_local_ipv4() {
    local address="$1" address_int first_address last_address bound
    local octet_1 octet_2 octet_3 octet_4
    [[ "$address" =~ $UH_IPV4 ]] || return 1
    IFS=. read -r octet_1 octet_2 octet_3 octet_4 <<< "$address"
    address_int=$(( (octet_1 << 24) + (octet_2 << 16) + (octet_3 << 8) + octet_4 ))
    for bound in "${local_bounds[@]}"; do
        read -r first_address last_address <<< "$bound"
        if (( address_int >= first_address && address_int <= last_address )); then
            return 0
        fi
    done
    return 1
}

# APPLY
# Rebuilds the live ipset from suridata.txt and makes sure both rules are
# in place. Runs on every path, because an existing list must stay blocked
# even on a run that finds no SID to match.
apply_blocklist() {
    # IPSET UPDATE
    # Rebuilds the live ipset from suridata.txt on every run, so an IP
    # removed from the file by hand stops being blocked on the next run.
    # The new set is filled apart and swapped in, with no empty window.
    local ip load_failed=0 read_failed=0
    local -a load_ips=()
    if ! ipset -! create suridata hash:ip; then
        log "ERROR: cannot create ipset 'suridata' -abort"
        exit 1
    fi

    # the file is read whole first: publishing a half-read list would lift
    # blocks that are still current
    if [ ! -f "$out_file" ]; then
        log "WARNING: cannot read $(basename "$out_file") -alert"
        log "WARNING: ipset left as it is -alert"
        return 0
    fi

    while IFS= read -r ip || [[ -n "$ip" ]]; do
        [[ "$ip" =~ ^#.*$ || -z "$ip" ]] && continue
        if [[ "$ip" =~ $UH_IPV4 ]]; then
            load_ips+=("$ip")
        fi
    done < "$out_file" || read_failed=1
    if (( read_failed )); then
        log "WARNING: cannot read $(basename "$out_file") -alert"
        log "WARNING: ipset left as it is -alert"
        return 0
    fi

    if ! ipset -! create suridata_new hash:ip; then
        load_failed=1
        log "WARNING: cannot create ipset 'suridata_new' -alert"
    elif ! ipset flush suridata_new; then
        load_failed=1
        log "WARNING: cannot flush ipset 'suridata_new' -alert"
    else
        for ip in "${load_ips[@]}"; do
            if ! ipset add suridata_new "$ip" -exist; then
                load_failed=1
                log "WARNING: cannot add $ip to 'suridata_new' -alert"
                break
            fi
        done
    fi

    if (( load_failed )); then
        log "WARNING: load incomplete, current blocks kept -alert"
        ipset destroy suridata_new 2>/dev/null || true
    elif ipset swap suridata_new suridata; then
        log "INFO: ${#load_ips[@]} IP(s) published"
        if ! ipset destroy suridata_new; then
            log "WARNING: cannot destroy ipset 'suridata_new' -alert"
        fi
    else
        log "WARNING: cannot swap new set, current blocks kept -alert"
        ipset destroy suridata_new 2>/dev/null || true
    fi

    # IPTABLES RULES
    # Adds each rule only when it is absent, because this script runs from cron.
    # DROP goes in first so that NFLOG, inserted after it, ends up above it and
    # logs the attempt before the packet is discarded.
    iptables_insert() {
        iptables -t mangle -C PREROUTING "$@" 2>/dev/null && return 0
        if ! iptables -t mangle -I PREROUTING 1 "$@"; then
            log "WARNING: cannot apply iptables rule -alert"
        fi
    }
    iptables_insert -i "$INTERFACESv4" -m set --match-set suridata dst -j DROP
    iptables_insert -i "$INTERFACESv4" -m set --match-set suridata dst \
        -j NFLOG --nflog-prefix "SURIDATA DROP: "
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
suridata_env="/etc/suricata/data/suridata.env"
env_specs=("$suridata_env root:root 640")
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
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/suridataenv.sh" || {
    log "ERROR: cannot load suridataenv.sh -abort"
    exit 1
}
env_keys="WAN_IFACE|INTERFACESv4|SERV_SUBNET|SERV_MASK"

# LOAD
load_suridata_env "$suridata_env" "$env_keys" || true

# KEY CHECK
# Collect every failure first, then decide -- a single abort reports them all
key_errors=()
if ! grep -q "^WAN_IFACE=" "$suridata_env"; then
    key_errors+=("WAN_IFACE missing line")
elif [[ -z "${WAN_IFACE:-}" ]]; then
    key_errors+=("WAN_IFACE not set")
fi
if ! grep -q "^INTERFACESv4=" "$suridata_env"; then
    key_errors+=("INTERFACESv4 missing line")
elif [[ -z "${INTERFACESv4:-}" ]]; then
    key_errors+=("INTERFACESv4 not set")
fi
if ! grep -q "^SERV_SUBNET=" "$suridata_env"; then
    key_errors+=("SERV_SUBNET missing line")
elif [[ -z "${SERV_SUBNET:-}" ]]; then
    key_errors+=("SERV_SUBNET not set")
elif ! [[ "$SERV_SUBNET" =~ $UH_IPV4 ]]; then
    key_errors+=("SERV_SUBNET invalid IPv4")
fi
if ! grep -q "^SERV_MASK=" "$suridata_env"; then
    key_errors+=("SERV_MASK missing line")
elif [[ -z "${SERV_MASK:-}" ]]; then
    key_errors+=("SERV_MASK not set")
elif ! [[ "$SERV_MASK" =~ $UH_NETMASK ]]; then
    key_errors+=("SERV_MASK invalid netmask")
fi
if (( ${#key_errors[@]} > 0 )); then
    for key_error in "${key_errors[@]}"; do
        log "WARNING: $key_error -alert"
    done
    log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$suridata_env") -abort"
    exit 1
fi
unset key_errors key_error

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "EVENT: suridata start..."

for f in "$rules_file" "$eve_log"; do
    if [ ! -f "$f" ]; then
        log "ERROR: $(basename "$f") not found -abort"
        exit 1
    fi
done

# EXCLUSION NETWORKS
# Use the configured LAN mask and current WAN IPv4 prefixes
mapfile -t wan_cidrs < <(ip -4 -o addr show dev "$WAN_IFACE" scope global 2>/dev/null | awk '{print $4}')
if (( ${#wan_cidrs[@]} == 0 )); then
    log "ERROR: WAN_IFACE in $(basename "$suridata_env") has no IPv4 address -abort"
    exit 1
fi
local_ranges=$(python3 -c '
import ipaddress, json, sys
networks = [ipaddress.IPv4Network(sys.argv[1] + "/" + sys.argv[2], strict=False)]
networks.extend(ipaddress.IPv4Interface(value).network for value in sys.argv[3:])
print(json.dumps([[int(net.network_address), int(net.broadcast_address)] for net in networks]))
' "$SERV_SUBNET" "$SERV_MASK" "${wan_cidrs[@]}") || {
    log "ERROR: cannot calculate exclusion networks -abort"
    exit 1
}
mapfile -t local_bounds < <(printf '%s' "$local_ranges" | jq -r '.[] | "\(.[0]) \(.[1])"')
touch "$out_file"

# LOCAL IP PURGE
# Remove listed addresses that belong to an excluded LAN or WAN network
purged=0
clean_file=$(mktemp) || {
    log "ERROR: cannot create blocklist temporary file -abort"
    exit 1
}
while IFS= read -r ip || [[ -n "$ip" ]]; do
    [ -z "$ip" ] && continue
    if is_local_ipv4 "$ip"; then
        log "INFO: $ip removed (LAN/WAN range)"
        ipset del suridata "$ip" 2>/dev/null || true
        (( purged++ )) || true
        continue
    fi
    echo "$ip" >> "$clean_file"
done < "$out_file"
if (( purged > 0 )); then
    chmod 600 "$clean_file"
    mv "$clean_file" "$out_file"
    log "INFO: $purged local IP(s) purged"
else
    rm -f "$clean_file"
fi

# DROP SIDS
# The SIDs that suricata-update currently resolves to the drop action
mapfile -t drop_sids < <(grep '^drop ' "$rules_file" 2>/dev/null | grep -oP 'sid:\K\d+' | sort -u)
if [ "${#drop_sids[@]}" -eq 0 ]; then
    log "INFO: no drop SIDs in $(basename "$rules_file")"
    apply_blocklist
    log "EVENT: suridata done"
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
eve_chunk_file=$(mktemp)
trap 'rm -f "$sid_map_file" "$new_sid_map_file" "$sid_grep_file" "$backfill_raw_file" "$eve_chunk_file"' EXIT
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
    log "INFO: rescanning eve.json for ${#new_sids[@]} new drop SID(s)"
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
    # eve.json holds one event per line, so a damaged line is read as text and
    # skipped. Without this a single damaged line would discard the whole scan.
    backfill_ips=$(jq -rR --slurpfile sids "$new_sid_map_file" --argjson networks "$local_ranges" --arg ipv4_re "$UH_IPV4" '
        def loc:
            if type != "string" then false
            elif (test($ipv4_re) | not) then false
            else split(".") | map(tonumber) as $octets
            | if any($octets[]; . > 255) then false
              else ($octets | reduce .[] as $octet (0; . * 256 + $octet)) as $ip
              | any($networks[]; $ip >= .[0] and $ip <= .[1]) end
            end;
        (try fromjson catch null) as $eve_event
        | if ($eve_event | type) != "object" then "!"
          else $eve_event
            | select(.event_type=="alert")
            | select(.alert.signature_id != null)
            | select($sids[0][(.alert.signature_id|tostring)] == true)
            | if (.src_ip|loc) and (.dest_ip|loc) then empty
              elif (.src_ip|loc) then .dest_ip
              elif (.dest_ip|loc) then .src_ip
              else empty end
          end
    ' "$backfill_raw_file" 2>>"$log_file") || backfill_failed=1
    if (( backfill_failed == 0 )); then
        backfill_bad=$(printf '%s\n' "$backfill_ips" | grep -c '^!$') || backfill_bad=0
        if (( backfill_bad > 0 )); then
            log "WARNING: $backfill_bad damaged line(s) in the SID rescan -alert"
        fi
        backfill_ips=$(printf '%s\n' "$backfill_ips" | grep -v '^!$')
    fi
    backfill_ips=$(printf '%s' "$backfill_ips" | sort -u)
fi

# the SID list only advances when its rescan finished: a failed backfill stays
# pending so the next run retries it, same criterion the eve scan uses
if (( backfill_failed )); then
    log "WARNING: jq failed rescanning eve.json for new SIDs -alert"
    log "WARNING: new SIDs pending; retry next run -alert"
elif ! printf '%s\n' "${drop_sids[@]}" > "$sids_file"; then
    log "WARNING: cannot update $(basename "$sids_file") -alert"
    log "WARNING: SID list may be incomplete -alert"
fi

# EVE JSON
# Reads only what eve.json grew since the last run, by saved offset
current_state=$(stat -c '%d:%i %s' "$eve_log" 2>/dev/null) || {
    log "ERROR: cannot inspect eve.json state -abort"
    exit 1
}
read -r current_identity current_size <<< "$current_state"
last_offset=0
last_identity=""
if [ -f "$offset_file" ]; then
    read -r last_offset last_identity < "$offset_file" || true
    [[ "$last_offset" =~ $UH_UINT ]] || last_offset=0
    if [ -n "$last_identity" ] && [ "$last_identity" != "$current_identity" ]; then
        log "INFO: eve.json identity changed -- offset reset to 0"
        last_offset=0
    fi
fi
if ! [ "$last_offset" -le "$current_size" ] 2>/dev/null; then
    log "INFO: eve.json truncated -- offset reset to 0"
    last_offset=0
fi

new_ips=""
jq_failed=0
read_failed=0
eve_bytes=0
if (( current_size > last_offset )); then
    if ! dd if="$eve_log" bs=64K iflag=skip_bytes,count_bytes skip="$last_offset" count="$((current_size - last_offset))" status=none > "$eve_chunk_file" 2>/dev/null; then
        read_failed=1
    else
        # eve.json holds one event per line, so a line ending on a newline is
        # complete. What follows the last newline is an event Suricata is still
        # writing: it stays pending and the offset stops before it. LC_ALL=C
        # makes awk count bytes, so a multibyte signature cannot shift it.
        eve_tail=0
        if [ -n "$(tail -c 1 "$eve_chunk_file")" ]; then
            eve_tail=$(LC_ALL=C awk 'BEGIN { RS = "\n" } END { print length($0) }' "$eve_chunk_file")
            [[ "$eve_tail" =~ $UH_UINT ]] || eve_tail=0
        fi
        eve_bytes=$(( $(stat -c%s "$eve_chunk_file") - eve_tail ))
        if (( eve_bytes > 0 )); then
            eve_scan=$(head -c "$eve_bytes" "$eve_chunk_file" | jq -rR --slurpfile sids "$sid_map_file" --argjson networks "$local_ranges" --arg ipv4_re "$UH_IPV4" '
        def loc:
            if type != "string" then false
            elif (test($ipv4_re) | not) then false
            else split(".") | map(tonumber) as $octets
            | if any($octets[]; . > 255) then false
              else ($octets | reduce .[] as $octet (0; . * 256 + $octet)) as $ip
              | any($networks[]; $ip >= .[0] and $ip <= .[1]) end
            end;
        (try fromjson catch null) as $eve_event
        | if ($eve_event | type) != "object" then "!"
          else $eve_event
            | select(.event_type=="alert")
            | select(.alert.signature_id != null)
            | select($sids[0][(.alert.signature_id|tostring)] == true)
            | if (.src_ip|loc) and (.dest_ip|loc) then empty
              elif (.src_ip|loc) then .dest_ip
              elif (.dest_ip|loc) then .src_ip
              else empty end
          end
    ' 2>>"$log_file") || jq_failed=1
            if (( jq_failed == 0 )); then
                eve_bad=$(printf '%s\n' "$eve_scan" | grep -c '^!$') || eve_bad=0
                if (( eve_bad > 0 )); then
                    log "WARNING: $eve_bad damaged line(s) in the eve.json batch -alert"
                fi
                new_ips=$(printf '%s\n' "$eve_scan" | grep -v '^!$' | sed '/^$/d' | sort -u)
            fi
        fi
    fi
fi
if (( read_failed )); then
    log "WARNING: cannot read eve.json; retry next run -alert"
elif (( jq_failed )); then
    log "WARNING: eve.json parse failed; retry next run -alert"
else
    printf '%s %s\n' "$(( last_offset + eve_bytes ))" "$current_identity" > "$offset_file"
fi

new_ips=$(printf '%s\n%s\n' "$new_ips" "$backfill_ips" | sed '/^$/d' | sort -u)

# NEW IPS
# Appends the valid, not-yet-listed, non-local IPs to suridata.txt
added=0
if [ -n "$new_ips" ]; then
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        [[ "$ip" =~ $UH_IPV4 ]] || continue
        is_local_ipv4 "$ip" && continue
        grep -qxF "$ip" "$out_file" 2>/dev/null && continue
        if ! echo "$ip" >> "$out_file"; then
            log "WARNING: cannot add $ip to suridata.txt -alert"
            continue
        fi
        log "INFO: $ip added to suridata.txt"
        (( added++ )) || true
    done <<< "$new_ips"
fi

if (( added > 0 )); then
    log "INFO: $added new IP(s) added"
    sort -t . -k1,1n -k2,2n -k3,3n -k4,4n -o "$out_file" "$out_file"
fi

apply_blocklist

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: suridata done"
