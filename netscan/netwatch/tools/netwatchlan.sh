#!/bin/bash
# maravento.com
#
################################################################################
#
# netwatchlan - LAN Devices Watchdog
# https://github.com/maravento/vault
#
# Periodically arp-scans every configured interface (LAN and/or WAN -- a
# server can have more than one) and keeps the "devices" table in
# netwatch.db up to date (current state), appending a row to
# "device_events" only when a device's state actually transitions
# (new_device / online / offline) -- not on every poll.
#
# Hostname resolution tries, in order: reverse DNS (getent), then mDNS
# (avahi-resolve-address) and NetBIOS (nbtscan) if those optional packages
# are installed -- see resolve_hostname(). Neither is required for the
# daemon to run; without them it just falls back to DNS-only resolution.
#
# netwatch.env variables:
# LAN_IFACES : comma-separated network interfaces to arp-scan
# LAN_POLL_INTERVAL : seconds between scans (default: 60)
# LAN_OFFLINE_GRACE : consecutive missed polls before marking offline (default: 3)
#
# On start, waits up to 2 minutes for at least one interface in LAN_IFACES to
# report link state "up" before entering the scan loop (see check_interfaces())
# -- needed for @reboot, since bonded/aggregated interfaces can come up later
# than the LAN's physical NICs. If none is up after 2 minutes, the daemon
# starts anyway and keeps retrying each interface every poll cycle.
#
# Log file:
# /var/log/netwatch.log (root:root, 640) -- shared by both daemons
# (netwatchlan.sh + netwatchports.sh). The installer writes its own
# netwatchinstall.log next to itself.
#
# Usage:
# ./netwatchlan.sh {start|stop|status}
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/netwatch.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

### PATHS
NETWATCH_ENV="/etc/netwatch/netwatch.env"
DB_FILE="/var/www/netwatch/data/netwatch.db"
PIDFILE="/run/netwatchlan.pid"

### DEPENDENCIES
for dep in arp-scan sqlite3 iproute2 procps coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -- abort"
        exit 1
    fi
done

# VALIDATION -- integer only; use directly with =~
_UH_UINT='^(0|[1-9][0-9]*)$'
### LOAD ENV
if [ ! -f "$NETWATCH_ENV" ]; then
    log "ERROR: netwatch is not installed -- abort"
    log "Run netwatchinstall.sh --install first"
    exit 1
fi

load_env() {
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Z_]+=.* ]]; then
            key="${line%%=*}"
            val="${line#*=}"
            val="${val//\"}"
            export "$key=$val"
        fi
    done < "$NETWATCH_ENV"
}
load_env

set_env_var() {
    local key="$1" val="$2"
    local esc_val esc_key
    val=$(printf '%s' "$val" | tr -d '\r\n')
    esc_val=$(printf '%s' "$val" | sed -e 's/[\&|]/\\&/g')
    esc_key=$(printf '%s' "$key" | sed 's/[.[\*^$]/\\&/g')
    if grep -q "^${esc_key}=" "$NETWATCH_ENV"; then
        sed -i "s|^${esc_key}=.*|${key}=\"${esc_val}\"|" "$NETWATCH_ENV"
    else
        echo "${key}=\"${val}\"" >> "$NETWATCH_ENV"
    fi
}

### DB CHECK
if [ ! -f "$DB_FILE" ]; then
    log "ERROR: database not found at $DB_FILE -- abort"
    log "Run netwatchinstall.sh --install first"
    exit 1
fi

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

# One transaction per scan cycle in a single sqlite3 process: run_scan loads
# the devices table once, computes transitions in bash, and hands the whole set
# of statements here. Data is substituted into the heredoc once (bash expansion
# is single-pass, so a '$' inside a value is not re-expanded); an empty batch is
# a no-op.
run_batch() {
    [ -z "${1:-}" ] && return 0
    sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" >/dev/null 2>>"$log_file" <<SQL
BEGIN IMMEDIATE;
${1}COMMIT;
SQL
}

# Hostname resolution fallback chain: reverse DNS -> mDNS (avahi) -> NetBIOS
# (nbtscan). avahi-utils/nbtscan are optional -- if not installed, this
# silently falls back to DNS-only behavior (their absence never blocks
# install or scanning). Each unresolved device costs up to ~4s per poll
# cycle (1s getent + 1s avahi + 2s nbtscan) since all three are tried in
# sequence every time DNS comes up empty -- on a LAN with many
# never-resolving devices this can stretch a cycle past LAN_POLL_INTERVAL;
# the daemon self-throttles (next cycle only starts after this one
# finishes), so it degrades to slower cycles rather than overlapping runs.
resolve_hostname() {
    local ip="$1"
    local h=""

    h=$(timeout 1 getent hosts "$ip" 2>/dev/null | awk '{print $2; exit}')

    if [ -z "$h" ] && command -v avahi-resolve-address &>/dev/null; then
        h=$(timeout 1 avahi-resolve-address -a "$ip" 2>/dev/null | awk '{print $2; exit}')
    fi

    if [ -z "$h" ] && command -v nbtscan &>/dev/null; then
        h=$(timeout 2 nbtscan -q "$ip" 2>/dev/null | awk '{print $2; exit}')
    fi

    printf '%s' "$h"
}

### CHECK INTERFACES (essential for @reboot -- bonded/aggregated
### interfaces like bond0 can take longer than the LAN's physical NICs to
### come up and report link state)
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

check_interfaces() {
    local list="${1:-}" max_attempts="${2:-24}" attempt=1
    local iface state ready states

    [ -n "$list" ] || list="$(list_ifaces | awk '{print $1}' | paste -sd,)"

    while (( attempt <= max_attempts )); do
        ready=0
        states=()
        for iface in ${list//,/ }; do
            if [ "$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')" = "UP" ]; then
                state="UP"
                ready=1
            else
                state="DOWN"
            fi
            states+=("$iface=$state")
        done
        if [ "$attempt" -eq 1 ] || [ "$ready" -eq 1 ]; then
            for state in "${states[@]}"; do
                log "INFO: interface: $state"
            done
        fi
        if [ "$ready" -eq 1 ]; then
            return 0
        fi
        log "INFO: waiting for interfaces ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

### ONE SCAN CYCLE
run_scan() {
    if [ -z "${LAN_IFACES:-}" ]; then
        log "ERROR: LAN_IFACES is not set"
        return 1
    fi

    local now
    now=$(now_iso)

    # Load the devices table once (mac -> status / miss_count / ip) so both the
    # scan loop and the offline sweep decide transitions in bash.
    declare -A dev_status=() dev_miss=() dev_ip=() seen_macs=()
    local d_mac d_status d_miss d_ip
    while IFS='|' read -r d_mac d_status d_miss d_ip; do
        [ -z "$d_mac" ] && continue
        dev_status["$d_mac"]="$d_status"
        dev_miss["$d_mac"]="$d_miss"
        dev_ip["$d_mac"]="$d_ip"
    done < <(sqlite3 -separator '|' "$DB_FILE" "SELECT mac, status, miss_count, ip FROM devices;" 2>>"$log_file")

    local sql=""

    local ifaces iface
    IFS=',' read -ra ifaces <<< "$LAN_IFACES"
    for iface in "${ifaces[@]}"; do
        if ! ip link show "$iface" &>/dev/null; then
            log "WARNING: interface '$iface' does not exist, skipping"
            continue
        fi

        # arp-scan -x -g: plain tab-separated output, without -q (-q strips vendor).
        local scan_out
        scan_out=$(arp-scan --interface="$iface" --localnet -x -g 2>>"$log_file") || true

        local ip mac vendor
        while IFS=$'\t' read -r ip mac vendor; do
            [ -z "$ip" ] && continue
            [ -z "$mac" ] && continue
            mac="${mac,,}"
            # a device answering on more than one configured interface appears
            # once per interface: record it once per cycle (first one wins)
            [ -n "${seen_macs[$mac]:-}" ] && continue
            seen_macs["$mac"]=1

            local hostname hostname_esc esc_mac esc_ip esc_iface esc_vendor
            hostname=$(resolve_hostname "$ip")
            hostname_esc=$(sql_escape "$hostname")
            esc_mac=$(sql_escape "$mac")
            esc_ip=$(sql_escape "$ip")
            esc_iface=$(sql_escape "$iface")
            esc_vendor=$(sql_escape "$vendor")

            if [ -z "${dev_status[$mac]:-}" ]; then
                sql+="INSERT INTO devices (mac, ip, iface, vendor, hostname, status, first_seen, last_seen, miss_count) VALUES ('$esc_mac', '$esc_ip', '$esc_iface', '$esc_vendor', '$hostname_esc', 'online', '$now', '$now', 0);
INSERT INTO device_events (mac, ip, event_type, event_time) VALUES ('$esc_mac', '$esc_ip', 'new_device', '$now');
"
                log "INFO: new device $ip ($mac) on $iface"
            else
                # A transient resolution failure (empty hostname this cycle)
                # must not blank out a hostname resolved on a previous cycle.
                sql+="UPDATE devices SET ip='$esc_ip', iface='$esc_iface', vendor='$esc_vendor', hostname=CASE WHEN '$hostname_esc' != '' THEN '$hostname_esc' ELSE hostname END, status='online', last_seen='$now', miss_count=0 WHERE mac='$esc_mac';
"
                if [ "${dev_status[$mac]}" = "offline" ]; then
                    sql+="INSERT INTO device_events (mac, ip, event_type, event_time) VALUES ('$esc_mac', '$esc_ip', 'online', '$now');
"
                    log "INFO: device online $ip ($mac) on $iface"
                fi
            fi
        done <<< "$scan_out"
    done

    # mark devices not seen this cycle on ANY configured interface
    local mac new_miss esc_mac ip_addr esc_ip_addr
    for mac in "${!dev_status[@]}"; do
        [ "${dev_status[$mac]}" = "online" ] || continue
        [ -n "${seen_macs[$mac]:-}" ] && continue
        new_miss=$(( ${dev_miss[$mac]:-0} + 1 ))
        esc_mac=$(sql_escape "$mac")
        sql+="UPDATE devices SET miss_count=${new_miss} WHERE mac='$esc_mac';
"
        if [ "$new_miss" -ge "${LAN_OFFLINE_GRACE:-3}" ]; then
            ip_addr="${dev_ip[$mac]:-}"
            esc_ip_addr=$(sql_escape "$ip_addr")
            sql+="UPDATE devices SET status='offline' WHERE mac='$esc_mac' AND status='online';
INSERT INTO device_events (mac, ip, event_type, event_time) VALUES ('$esc_mac', '$esc_ip_addr', 'offline', '$now');
"
            log "INFO: device offline $ip_addr ($mac)"
        fi
    done

    run_batch "$sql"
}

### START
start() {
    # prevent overlapping runs
    SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$SCRIPT_LOCK")
    exec 200>"$SCRIPT_LOCK"
    if ! flock -n 200; then
        log "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        log "ERROR: netwatchlan is already running -- abort"
        exit 1
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "netwatchlan is already running with PID $(cat "$PIDFILE")"
        exit 1
    fi

    # Enforce perms unconditionally: the shared /var/log/netwatch.log may
    # already exist (created by the installer or the other daemon), so
    # normalize ownership/mode on every start rather than only on creation.
    touch "$log_file"
    chmod 640 "$log_file"
    chown root:root "$log_file"

    ### CHECK LAN_IFACES
    if [ -z "${LAN_IFACES:-}" ]; then
        log "ERROR: LAN_IFACES is not set in $NETWATCH_ENV"
        exit 1
    fi

    ### CHECK INTERFACES (essential for @reboot)
    if ! check_interfaces "$LAN_IFACES"; then
        log "WARNING: no operational interface -- alert"
    fi

    ### CHECK AND SET LAN_POLL_INTERVAL
    if [ -z "${LAN_POLL_INTERVAL:-}" ] || ! [[ "$LAN_POLL_INTERVAL" =~ $_UH_UINT ]]; then
        [ -n "${LAN_POLL_INTERVAL:-}" ] && log "WARNING: invalid LAN_POLL_INTERVAL -- fallback"
        LAN_POLL_INTERVAL=60
        set_env_var "LAN_POLL_INTERVAL" "$LAN_POLL_INTERVAL"
    fi

    ### CHECK AND SET LAN_OFFLINE_GRACE
    if [ -z "${LAN_OFFLINE_GRACE:-}" ] || ! [[ "$LAN_OFFLINE_GRACE" =~ $_UH_UINT ]]; then
        [ -n "${LAN_OFFLINE_GRACE:-}" ] && log "WARNING: invalid LAN_OFFLINE_GRACE -- fallback"
        LAN_OFFLINE_GRACE=3
        set_env_var "LAN_OFFLINE_GRACE" "$LAN_OFFLINE_GRACE"
    fi

    log "netwatchlan start..."
    log "Interfaces : $LAN_IFACES"
    log "Interval : ${LAN_POLL_INTERVAL}s"
    log "Offline grace: ${LAN_OFFLINE_GRACE} polls"
    log "Database : $DB_FILE"
    log "Log : $log_file"

    rm -f "$PIDFILE"
    (
        exec 200>&-
        echo "$BASHPID" > "$PIDFILE"
        while true; do
            log "netwatchlan cycle start..."
            run_scan
            sleep "$LAN_POLL_INTERVAL"
        done
    ) </dev/null >/dev/null 2>&1 &
    disown

    # Wait (briefly) for the child to have written its PID before logging it.
    for _ in $(seq 1 20); do
        [ -s "$PIDFILE" ] && break
        sleep 0.05
    done
    log "netwatchlan started with PID $(cat "$PIDFILE" 2>/dev/null)"
}

### STOP
stop() {
    log "Stopping netwatchlan..."
    if [ -f "$PIDFILE" ]; then
        local PID
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null
            log "netwatchlan stopped (PID $PID)"
        else
            log "netwatchlan was not running (stale PID file removed)"
        fi
        rm -f "$PIDFILE"
    else
        log "netwatchlan is not running"
    fi
}

### STATUS
status() {
    log "netwatchlan status..."
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "netwatchlan is RUNNING (PID $(cat "$PIDFILE"))"
        log "Interfaces : ${LAN_IFACES:-unset}"
        log "Interval : ${LAN_POLL_INTERVAL:-60}s"
        if [ -f "$DB_FILE" ]; then
            local counts
            counts=$(sqlite3 "$DB_FILE" "SELECT status, COUNT(*) FROM devices GROUP BY status;" 2>/dev/null)
            log "Devices :"
            echo "$counts" | sed 's/^/ /' | tee -a "$log_file"
        fi
    else
        log "netwatchlan is STOPPED"
    fi
}

### MAIN
case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) log "Usage: $(basename "$0") {start|stop|status}" ;;
esac
