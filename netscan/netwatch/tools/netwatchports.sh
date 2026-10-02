#!/bin/bash
# maravento.com
#
################################################################################
#
# netwatchports - Port Auditing Daemon + CLI
# https://github.com/maravento/vault
#
# Watches TCP and UDP ports in one of two mutually exclusive modes (only one
# runs at a time, to avoid mixing self-audit and target-audit traffic/noise
# into the same audit trail):
#
# server (default) -- reads the server's own listening TCP+UDP sockets live
# via `ss -tulnp` (kernel-accurate, no probing).
# target -- runs a fast nmap TCP+UDP scan (top ~100 ports each,
# -sT -sU -F) against a user-chosen external host
# every poll cycle.
#
# Active mode + target IP are stored in ports_mode.conf (NOT netwatch.env --
# that file also holds the panel's access-control CIDR, and ports_mode.conf
# must be writable by the web-facing PHP process, which must never be able
# to touch access control).
#
# Both modes write to the same "port_scan_state" table (current state) in
# netwatch.db, appending a row to "port_events" only when a port's status
# actually transitions (opened / closed) -- not on every poll.
#
# netwatch.env variables:
# PORT_POLL_INTERVAL : seconds between poll cycles (default: 30)
# PURGE_CLOSED_AFTER_HOURS : how long closed ports are kept before being
#                            purged from port_scan_state (default: 6)
#
# ports_mode.conf variables:
# PORTS_MODE : "server" or "target"
# PORTS_TARGET_IP : target host/IP, only used when PORTS_MODE=target
#
# LOG: /var/log/netwatch.log (root:root, 640) -- shared by both daemons
#      (netwatchlan.sh + netwatchports.sh). The installer writes its own
#      netwatchsetup.log next to itself.
#
# USAGE:
# ./netwatchports.sh {start|stop|status}
# ./netwatchports.sh mode server
# ./netwatchports.sh mode target <host>
# ./netwatchports.sh list
#
################################################################################

set -uo pipefail

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/netwatch.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# PATHS
netwatch_env="/etc/netwatch/netwatch.env"
db_file="/var/www/netwatch/data/netwatch.db"
ports_mode_file="/var/www/netwatch/data/ports_mode.conf"
scan_status_file="/var/www/netwatch/data/port_scan_status.conf"
pid_file="/run/netwatchports.pid"

# dependencies
for dep in sqlite3 nmap iproute2 procps coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -- abort"
        exit 1
    fi
done

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
UH_HOST='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
UH_UINT='^(0|[1-9][0-9]*)$'

valid_host() {
    [[ "$1" =~ $UH_IPV4 ]] || [[ "$1" =~ $UH_FQDN ]] || [[ "$1" =~ $UH_HOST ]]
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
env_specs=("$netwatch_env root:www-data 640")
for env_spec in "${env_specs[@]}"; do
    read -r env_path env_owner_want env_perms_want <<< "$env_spec"
    if [ ! -f "$env_path" ]; then
        log "ERROR: $(basename "$env_path") not found -- abort"
        exit 1
    fi
    env_owner=$(stat -c '%U:%G' "$env_path" 2>/dev/null)
    env_perms=$(stat -c '%a' "$env_path" 2>/dev/null)
    if [[ "$env_owner" != "$env_owner_want" ]] \
       || [[ "$env_perms" != "$env_perms_want" ]]; then
        if chown "$env_owner_want" "$env_path" 2>/dev/null \
           && chmod "$env_perms_want" "$env_path" 2>/dev/null; then
            log "INFO: $(basename "$env_path") perms fixed -- fixed"
        else
            log "ERROR: cannot fix $(basename "$env_path") perms -- abort"
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
    [[ ! -f "$conf_file" ]] && { log "WARNING: $conf_file not found -- fallback"; return 1; }
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            log "ERROR: malformed line in $(basename "$conf_file"): '$env_line' -- abort"
            exit 1
        fi
        case "$env_key" in
            SERVER_IP|PORT_POLL_INTERVAL|PURGE_CLOSED_AFTER_HOURS)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}

# LOAD
load_conf "$netwatch_env" || true

# KEY CHECK
# Collect every failure first, then decide -- a single abort reports them all
key_errors=()
for env_key in SERVER_IP; do
    if ! grep -q "^${env_key}=" "$netwatch_env"; then
        key_errors+=("$env_key missing line")
    elif [[ -z "${!env_key:-}" ]]; then
        key_errors+=("$env_key not set")
    fi
done
for env_key in PORT_POLL_INTERVAL PURGE_CLOSED_AFTER_HOURS; do
    if ! grep -q "^${env_key}=" "$netwatch_env"; then
        key_errors+=("$env_key missing line")
    elif [[ -z "${!env_key:-}" ]]; then
        key_errors+=("$env_key not set")
    elif ! [[ "${!env_key}" =~ $UH_UINT ]] || (( ${!env_key} == 0 )); then
        key_errors+=("$env_key invalid count")
    fi
done
if (( ${#key_errors[@]} > 0 )); then
    for key_error in "${key_errors[@]}"; do
        log "ERROR: $key_error"
    done
    log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$netwatch_env")"
    log "ERROR: run netwatchsetup.sh --install first -- abort"
    exit 1
fi
unset key_errors key_error env_key

# FALLBACK
# Second layer of protection, behind KEY CHECK -- by design never reached
if [ -z "${PORT_POLL_INTERVAL:-}" ]; then
    log "WARNING: no PORT_POLL_INTERVAL in netwatch.env -- fallback"
fi
PORT_POLL_INTERVAL="${PORT_POLL_INTERVAL:-30}"
if [ -z "${PURGE_CLOSED_AFTER_HOURS:-}" ]; then
    log "WARNING: no PURGE_CLOSED_AFTER_HOURS in netwatch.env -- fallback"
fi
PURGE_CLOSED_AFTER_HOURS="${PURGE_CLOSED_AFTER_HOURS:-6}"

# DB CHECK
if [ ! -f "$db_file" ]; then
    log "ERROR: database not found at $db_file"
    log "ERROR: run netwatchsetup.sh --install first -- abort"
    exit 1
fi

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

# PORTS MODE (server | target <ip>) -- kept in its own file, not
# netwatch.env, so the web-facing PHP process can write it without
# touching the panel's access-control config.
load_ports_mode() {
    PORTS_MODE="server"
    PORTS_TARGET_IP=""
    if [ -f "$ports_mode_file" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[A-Z_]+=.* ]]; then
                local key val
                key="${line%%=*}"
                val="${line#*=}"
                val="${val//\"}"
                case "$key" in
                    PORTS_MODE) PORTS_MODE="$val" ;;
                    PORTS_TARGET_IP) PORTS_TARGET_IP="$val" ;;
                esac
            fi
        done < "$ports_mode_file"
    fi
}

write_ports_mode() {
    local mode="$1" target="$2"
    local dir tmp_file
    dir="$(dirname "$ports_mode_file")"
    mkdir -p "$dir"

    tmp_file=$(mktemp "${ports_mode_file}.XXXXXX")
    cat > "$tmp_file" <<EOF
PORTS_MODE="${mode}"
PORTS_TARGET_IP="${target}"
EOF
    chown www-data:www-data "$tmp_file" 2>/dev/null || true
    chmod 664 "$tmp_file"
    mv -f "$tmp_file" "$ports_mode_file"
}

# Records that a poll cycle finished for (source, host), whether or not it
# found anything -- this is what lets the panel tell "no scan yet" apart
# from "scanned, nothing open", instead of showing "Scanning..." forever.
write_scan_marker() {
    local source="$1" host="$2" now="$3" found="$4"
    local dir tmp_file
    dir="$(dirname "$scan_status_file")"
    mkdir -p "$dir"

    tmp_file=$(mktemp "${scan_status_file}.XXXXXX")
    cat > "$tmp_file" <<EOF
LAST_SCAN_SOURCE="${source}"
LAST_SCAN_HOST="${host}"
LAST_SCAN_TIME="${now}"
LAST_SCAN_FOUND="${found}"
EOF
    chown www-data:www-data "$tmp_file" 2>/dev/null || true
    chmod 664 "$tmp_file"
    mv -f "$tmp_file" "$scan_status_file"
}

cmd_mode() {
    case "${2:-}" in
        server)
            write_ports_mode "server" ""
            echo "Mode set to: server"
            ;;
        target)
            local ip="${3:-}"
            if [ -z "$ip" ]; then
                echo "Usage: $(basename "$0") mode target <host>"
                exit 1
            fi
            valid_host "$ip" || { log "ERROR: invalid target: $ip -- abort"; exit 1; }
            write_ports_mode "target" "$ip"
            echo "Mode set to: target ($ip)"
            ;;
        *)
            echo "Usage: $(basename "$0") mode {server|target <host>}"
            exit 1
            ;;
    esac
}

cmd_list() {
    load_ports_mode
    local host
    if [ "$PORTS_MODE" = "target" ]; then
        host="$PORTS_TARGET_IP"
    else
        host="${SERVER_IP:-localhost}"
    fi
    echo "Mode: $PORTS_MODE Host: $host"
    echo "PORT PROTO STATUS SERVICE"
    sqlite3 -separator '|' "$db_file" "SELECT port, proto, status, IFNULL(service,'') FROM port_scan_state WHERE source='$(sql_escape "$PORTS_MODE")' AND host='$(sql_escape "$host")' ORDER BY port;" | \
        while IFS='|' read -r port proto status service; do
            printf "%-6s %-6s %-7s %s\n" "$port" "$proto" "$status" "$service"
        done
}

# BATCHED WRITE
# One transaction per poll cycle in a single sqlite3 process: each poll
# function loads the source/host's current state once, computes the transitions
# in bash, and hands the whole set of statements here. Data is substituted into
# the heredoc once (bash expansion is single-pass, so a '$' inside a value is
# not re-expanded); an empty batch is a no-op.
run_batch() {
    [ -z "${1:-}" ] && return 0
    sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$db_file" >/dev/null 2>>"$log_file" <<SQL
BEGIN IMMEDIATE;
${1}COMMIT;
SQL
}

# POLL: SERVER MODE
poll_server() {
    local now="$1"
    local host="${SERVER_IP:-localhost}"
    local esc_host
    esc_host=$(sql_escape "$host")

    # current state (proto:port -> status), loaded once for the whole cycle
    declare -A prev=() seen=()
    local p_proto p_port p_stat
    while IFS='|' read -r p_proto p_port p_stat; do
        [ -z "$p_port" ] && continue
        prev["${p_proto}:${p_port}"]="$p_stat"
    done < <(sqlite3 -separator '|' "$db_file" "SELECT proto, port, status FROM port_scan_state WHERE source='server' AND host='$esc_host';" 2>>"$log_file")

    local sql=""

    # ss -Htulnp: no header, tcp+udp, listening, numeric ports, show owning
    # process. Fields: Netid State Recv-Q Send-Q LocalAddress:Port PeerAddress:Port Process
    # (udp sockets show State as "UNCONN" instead of "LISTEN" -- still the
    # right thing to report as an open/listening port).
    local netid local_addr proc_field
    while read -r netid _ _ _ local_addr _ proc_field; do
        local port="${local_addr##*:}"
        [[ "$port" =~ $UH_UINT ]] || continue
        local proto="tcp"
        [ "$netid" = "udp" ] && proto="udp"
        local key="${proto}:${port}"
        # the same port can be listed twice (IPv4 + IPv6): count it once
        [ -n "${seen[$key]:-}" ] && continue
        seen["$key"]=1

        local service esc_service
        service=$(printf '%s' "$proc_field" | sed -n 's/.*"\([^"]*\)".*/\1/p')
        esc_service=$(sql_escape "$service")

        if [ -z "${prev[$key]:-}" ]; then
            sql+="INSERT INTO port_scan_state (source, host, port, proto, service, status, last_checked, last_changed) VALUES ('server', '$esc_host', ${port}, '$proto', '$esc_service', 'open', '$now', '$now');
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('server', '$esc_host', ${port}, 'opened', '$now');
"
            log "INFO: server port opened ${host}:${port}/${proto} (${service:-unknown})"
        else
            sql+="UPDATE port_scan_state SET service='$esc_service', status='open', last_checked='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
"
            if [ "${prev[$key]}" != "open" ]; then
                sql+="UPDATE port_scan_state SET last_changed='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('server', '$esc_host', ${port}, 'opened', '$now');
"
                log "INFO: server port opened ${host}:${port}/${proto} (${service:-unknown})"
            fi
        fi
    done < <(ss -Htulnp 2>/dev/null)

    # ss never reports closed ports, it just omits them, so anything previously
    # 'open' that's absent this cycle must be closed explicitly. seen[] keys are
    # "proto:port" so tcp and udp on the same port number don't collide.
    local key proto port
    for key in "${!prev[@]}"; do
        [ "${prev[$key]}" = "open" ] || continue
        [ -n "${seen[$key]:-}" ] && continue
        proto="${key%%:*}"
        port="${key##*:}"
        sql+="UPDATE port_scan_state SET status='closed', last_checked='$now', last_changed='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('server', '$esc_host', ${port}, 'closed', '$now');
"
        log "INFO: server port closed ${host}:${port}/${proto}"
    done

    run_batch "$sql"
    write_scan_marker "server" "$host" "$now" "${#seen[@]}"
}

# POLL: TARGET MODE
poll_target() {
    local target="$1" now="$2"

    local esc_target
    esc_target=$(sql_escape "$target")

    # current state (proto:port -> status), loaded once for the whole cycle --
    # loaded before the nmap call (not after) so it's also available to the
    # "nothing reported" branch below.
    declare -A prev=() seen=()
    local p_proto p_port p_stat
    while IFS='|' read -r p_proto p_port p_stat; do
        [ -z "$p_port" ] && continue
        prev["${p_proto}:${p_port}"]="$p_stat"
    done < <(sqlite3 -separator '|' "$db_file" "SELECT proto, port, status FROM port_scan_state WHERE source='target' AND host='$esc_target';" 2>>"$log_file")

    local nmap_out
    nmap_out=$(nmap -Pn -sT -sU -F -T4 --host-timeout 60s -oG - "$target" 2>>"$log_file") || true

    local ports_field
    ports_field=$(printf '%s\n' "$nmap_out" | grep '^Host:' | sed -n 's/.*Ports: //p')

    if [ -z "$ports_field" ]; then
        # -F rolls most/all ports under "Ignored State" when they share one
        # state, so "Ports:" is often empty even on a clean scan -- that's
        # not a failure, just nothing to report individually. Still close
        # out anything that was previously open, and always record that the
        # cycle completed (write_scan_marker) so the panel can tell "no scan
        # yet" apart from "scanned, nothing open" instead of waiting forever.
        log "INFO: scan completed for '$target' -- no open/reported ports found"
        local sql="" key proto port
        for key in "${!prev[@]}"; do
            [ "${prev[$key]}" = "open" ] || continue
            proto="${key%%:*}"
            port="${key##*:}"
            sql+="UPDATE port_scan_state SET status='closed', last_checked='$now', last_changed='$now' WHERE source='target' AND host='$esc_target' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('target', '$esc_target', ${port}, 'closed', '$now');
"
            log "INFO: target port closed ${target}:${port}/${proto}"
        done
        run_batch "$sql"
        write_scan_marker "target" "$target" "$now" 0
        return
    fi

    local sql="" open_count=0
    local entries entry
    IFS=',' read -ra entries <<< "$ports_field"
    for entry in "${entries[@]}"; do
        entry="${entry# }"
        [ -z "$entry" ] && continue
        local port state proto service
        IFS='/' read -r port state proto _ service _ <<< "$entry"
        [[ "$port" =~ $UH_UINT ]] || continue
        [ "$proto" = "tcp" ] || [ "$proto" = "udp" ] || continue
        local key="${proto}:${port}"
        [ -n "${seen[$key]:-}" ] && continue
        seen["$key"]=1
        # nmap can report open|filtered / closed|filtered / filtered -- treat
        # anything other than a clean 'open' as closed for this audit view.
        local status="closed"
        [ "$state" = "open" ] && status="open"
        [ "$status" = "open" ] && open_count=$((open_count + 1))
        local esc_service
        esc_service=$(sql_escape "$service")

        if [ -z "${prev[$key]:-}" ]; then
            sql+="INSERT INTO port_scan_state (source, host, port, proto, service, status, last_checked, last_changed) VALUES ('target', '$esc_target', ${port}, '$proto', '$esc_service', '$status', '$now', '$now');
"
            if [ "$status" = "open" ]; then
                sql+="INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('target', '$esc_target', ${port}, 'opened', '$now');
"
                log "INFO: target port opened ${target}:${port}/${proto} (${service:-unknown})"
            fi
        else
            sql+="UPDATE port_scan_state SET service='$esc_service', status='$status', last_checked='$now' WHERE source='target' AND host='$esc_target' AND port=${port} AND proto='$proto';
"
            if [ "$status" != "${prev[$key]}" ]; then
                # port_events.event_type is 'opened'/'closed', status is
                # 'open'/'closed' -- map here.
                local event_type="closed"
                [ "$status" = "open" ] && event_type="opened"
                sql+="UPDATE port_scan_state SET last_changed='$now' WHERE source='target' AND host='$esc_target' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('target', '$esc_target', ${port}, '$event_type', '$now');
"
                log "INFO: target port ${event_type} ${target}:${port}/${proto} (${service:-unknown})"
            fi
        fi
    done

    # entries[] only lists ports nmap reported individually -- ports it
    # rolled up under "Ignored State" (the common case with -F once most
    # ports share the same state) never reach the loop above. Anything
    # still marked 'open' in the DB that wasn't seen this cycle must be
    # closed explicitly, same as poll_server does.
    local key proto port
    for key in "${!prev[@]}"; do
        [ "${prev[$key]}" = "open" ] || continue
        [ -n "${seen[$key]:-}" ] && continue
        proto="${key%%:*}"
        port="${key##*:}"
        sql+="UPDATE port_scan_state SET status='closed', last_checked='$now', last_changed='$now' WHERE source='target' AND host='$esc_target' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('target', '$esc_target', ${port}, 'closed', '$now');
"
        log "INFO: target port closed ${target}:${port}/${proto}"
    done

    run_batch "$sql"
    write_scan_marker "target" "$target" "$now" "$open_count"
}

# ONE POLL CYCLE
purge_stale_closed_ports() {
    sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$db_file" \
        "DELETE FROM port_scan_state WHERE status='closed' AND julianday(last_changed) < julianday('now', '-${PURGE_CLOSED_AFTER_HOURS} hours');" \
        2>>"$log_file"
}

run_poll() {
    load_ports_mode
    local now
    now=$(now_iso)

    if [ "$PORTS_MODE" = "target" ]; then
        if [ -z "$PORTS_TARGET_IP" ]; then
            log "WARNING: mode is target with no target host -- alert"
            return
        fi
        if ! valid_host "$PORTS_TARGET_IP"; then
            log "WARNING: invalid target host '$PORTS_TARGET_IP' -- alert"
            return
        fi
        poll_target "$PORTS_TARGET_IP" "$now"
    else
        poll_server "$now"
    fi

    purge_stale_closed_ports
}

# START
start() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$script_lock")
    exec 200>"$script_lock"
    if ! flock -n 200; then
        log "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
        log "ERROR: netwatchports is already running -- abort"
        exit 1
    fi

    # Enforce perms unconditionally: the shared /var/log/netwatch.log may
    # already exist (created by the installer or the other daemon), so
    # normalize ownership/mode on every start rather than only on creation.
    touch "$log_file"
    chmod 640 "$log_file"
    chown root:root "$log_file"

    if [ ! -f "$ports_mode_file" ]; then
        write_ports_mode "server" ""
    fi

    load_ports_mode
    log "netwatchports start..."
    log "INFO: Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    log "INFO: Interval : ${PORT_POLL_INTERVAL}s"
    log "INFO: Database : $db_file"
    log "INFO: Log : $log_file"

    rm -f "$pid_file"
    (
        exec 200>&-
        echo "$BASHPID" > "$pid_file"
        while true; do
            log "netwatchports cycle start..."
            run_poll
            sleep "$PORT_POLL_INTERVAL"
        done
    ) </dev/null >/dev/null 2>&1 &
    disown

    # Wait (briefly) for the child to have written its PID before logging it.
    for _ in $(seq 1 20); do
        [ -s "$pid_file" ] && break
        sleep 0.05
    done
    log "INFO: netwatchports started with PID $(cat "$pid_file" 2>/dev/null)"
}

# STOP
stop() {
    log "INFO: Stopping netwatchports..."
    if [ -f "$pid_file" ]; then
        local daemon_pid
        daemon_pid=$(cat "$pid_file")
        if kill -0 "$daemon_pid" 2>/dev/null; then
            kill "$daemon_pid" 2>/dev/null
            log "INFO: netwatchports stopped (PID $daemon_pid)"
        else
            log "INFO: netwatchports was not running (stale PID file removed)"
        fi
        rm -f "$pid_file"
    else
        log "INFO: netwatchports is not running"
    fi
}

# STATUS
status() {
    log "netwatchports status..."
    load_ports_mode
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log "INFO: netwatchports is RUNNING (PID $(cat "$pid_file"))"
        log "INFO: Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
        log "INFO: Interval : ${PORT_POLL_INTERVAL:-30}s"
        if [ -f "$db_file" ]; then
            local counts
            counts=$(sqlite3 "$db_file" "SELECT status, COUNT(*) FROM port_scan_state WHERE source='$(sql_escape "$PORTS_MODE")' GROUP BY status;" 2>/dev/null)
            log "INFO: Ports :"
            echo "$counts" | sed 's/^/ /' | tee -a "$log_file"
        fi
    else
        log "INFO: netwatchports is STOPPED"
        log "INFO: Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    fi
}

# MAIN
case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    mode) cmd_mode "$@" ;;
    list) cmd_list ;;
    *) log "INFO: Usage: $(basename "$0") {start|stop|status|mode server|mode target <host>|list}" ;;
esac
