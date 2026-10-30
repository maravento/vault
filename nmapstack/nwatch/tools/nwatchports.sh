#!/bin/bash
# maravento.com
#
################################################################################
#
# nwatchports - Port Auditing Daemon + CLI
# FILE: tools/nwatchports.sh
#
# USAGE:
# ./nwatchports.sh {--start|--stop|--status}
# ./nwatchports.sh --mode server
# ./nwatchports.sh --mode target <host>
# ./nwatchports.sh --list
#
# LOG: /var/log/nwatch.log (root:root, 640) -- shared by both daemons
#      (nwatchlan.sh + nwatchports.sh). The installer writes its own
#      nwatchsetup.log next to itself.
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/nwatch.log"
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

# dependencies
for dep in sqlite3 nmap iproute2 procps coreutils util-linux; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# PATHS
# Declare the file and directory paths used below
nwatch_env="/etc/nwatch/nwatch.env"
db_file="/var/www/nwatch/data/nwatch.db"
ports_mode_file="/var/www/nwatch/data/ports_mode.conf"
scan_status_file="/var/www/nwatch/data/port_scan_status.conf"
pid_file="/run/nwatchports.pid"

# validation -- one variable per thing validated; use directly with =~
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
UH_HOST='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
UH_UINT='^(0|[1-9][0-9]*)$'
UH_SINT='^(0|-?[1-9][0-9]*)$'
UH_MAX=9223372036854775807
UH_MIN=-9223372036854775808

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# validation - integer is representable as a signed 64-bit value
uh_fits() {
    local value="${1-}" limit
    [[ "$value" =~ $UH_SINT ]] || return 1
    if [[ "${value:0:1}" == - ]]; then
        limit="${UH_MIN#-}"
        value="${value#-}"
    else
        limit="$UH_MAX"
    fi
    (( ${#value} < ${#limit} )) && return 0
    (( ${#value} > ${#limit} )) && return 1
    [[ "$value" > "$limit" ]] && return 1
    return 0
}

valid_host() {
    [[ "$1" =~ $UH_IPV4 ]] || [[ "$1" =~ $UH_FQDN ]] || [[ "$1" =~ $UH_HOST ]]
}

# PID CHECK
# Check whether the recorded process belongs to this daemon
daemon_alive() {
    local pid="$1" args=() self i
    [ -n "$pid" ] || return 1
    { mapfile -d '' -t args < "/proc/$pid/cmdline"; } 2>/dev/null || return 1
    self="$(basename -- "$0")"
    case "$(basename -- "${args[0]:-}")" in
        "$self") i=0 ;;
        bash|sh) i=1 ;;
        *) return 1 ;;
    esac
    [ "$(basename -- "${args[i]:-}")" = "$self" ] || return 1
    [ "${args[i+1]:-}" = --start ]
}

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

# PORTS MODE (server | target <ip>) -- kept in its own file, not
# nwatch.env, so the web-facing PHP process can write it without
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
    local dir tmp_file=""
    dir="$(dirname "$ports_mode_file")"
    if mkdir -p "$dir" \
        && tmp_file=$(mktemp "${ports_mode_file}.XXXXXX") \
        && printf 'PORTS_MODE="%s"\nPORTS_TARGET_IP="%s"\n' "$mode" "$target" > "$tmp_file" \
        && { chown www-data:www-data "$tmp_file" 2>/dev/null || true; } \
        && chmod 664 "$tmp_file" \
        && mv -f "$tmp_file" "$ports_mode_file"; then
        return 0
    fi
    log "ERROR: cannot save $(basename "$ports_mode_file") -abort"
    rm -f "$tmp_file"
    return 1
}

write_scan_marker() {
    local source="$1" host="$2" now="$3" found="$4" status="${5:-complete}"
    local scan_source="$source" scan_host="$host" scan_time="$now" scan_found="$found"
    local dir tmp_file=""

    if [ "$status" = "failed" ]; then
        scan_source=$(awk -F'"' '$1 == "LAST_SCAN_SOURCE=" { print $2 }' "$scan_status_file" 2>/dev/null)
        scan_host=$(awk -F'"' '$1 == "LAST_SCAN_HOST=" { print $2 }' "$scan_status_file" 2>/dev/null)
        scan_time=$(awk -F'"' '$1 == "LAST_SCAN_TIME=" { print $2 }' "$scan_status_file" 2>/dev/null)
        scan_found=$(awk -F'"' '$1 == "LAST_SCAN_FOUND=" { print $2 }' "$scan_status_file" 2>/dev/null)
        scan_found="${scan_found:-0}"
    fi

    dir="$(dirname "$scan_status_file")"
    if mkdir -p "$dir" \
        && tmp_file=$(mktemp "${scan_status_file}.XXXXXX") \
        && cat > "$tmp_file" <<EOF \
        && { chown www-data:www-data "$tmp_file" 2>/dev/null || true; } \
        && chmod 664 "$tmp_file" \
        && mv -f "$tmp_file" "$scan_status_file"
LAST_SCAN_SOURCE="${scan_source}"
LAST_SCAN_HOST="${scan_host}"
LAST_SCAN_TIME="${scan_time}"
LAST_SCAN_FOUND="${scan_found}"
LAST_ATTEMPT_SOURCE="${source}"
LAST_ATTEMPT_HOST="${host}"
LAST_ATTEMPT_TIME="${now}"
LAST_ATTEMPT_STATUS="${status}"
EOF
    then
        return 0
    fi
    log "WARNING: cannot save $(basename "$scan_status_file") -alert"
    rm -f "$tmp_file"
    return 1
}

scan_attempt_failed() {
    local source="$1" host="$2"
    [ -f "$scan_status_file" ] || return 1
    grep -Fxq "LAST_ATTEMPT_SOURCE=\"$source\"" "$scan_status_file" &&
        grep -Fxq "LAST_ATTEMPT_HOST=\"$host\"" "$scan_status_file" &&
        grep -Fxq 'LAST_ATTEMPT_STATUS="failed"' "$scan_status_file"
}

cmd_mode() {
    case "${2:-}" in
        server)
            write_ports_mode "server" "" || exit 1
            log "INFO: Mode set to: server"
            ;;
        target)
            local ip="${3:-}"
            if [ -z "$ip" ]; then
                echo "Usage: $(basename "$0") --mode target <host>"
                exit 1
            fi
            valid_host "$ip" || { log "ERROR: invalid target: $ip -abort"; exit 1; }
            write_ports_mode "target" "$ip" || exit 1
            log "INFO: Mode set to: target ($ip)"
            ;;
        *)
            echo "Usage: $(basename "$0") --mode {server|target <host>}"
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
    sqlite3 -cmd ".bail on" -cmd "PRAGMA busy_timeout=${NWATCH_DB_TIMEOUT_MS};" "$db_file" >/dev/null 2>>"$log_file" <<SQL
BEGIN IMMEDIATE;
${1}COMMIT;
SQL
}

# POLL: SERVER MODE
# Read the local listening sockets and record port state changes
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

    local ss_out
    if ! ss_out=$(ss -Htulnp 2>/dev/null); then
        if ! scan_attempt_failed "server" "$host"; then
            log "WARNING: ss did not complete for '$host' -alert"
        fi
        write_scan_marker "server" "$host" "$now" 0 "failed"
        return
    fi

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
            log "server port ${host}:${port}/${proto}"
            log "INFO: server port opened; service=${service:-unknown}"
        else
            sql+="UPDATE port_scan_state SET service='$esc_service', status='open', last_checked='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
"
            if [ "${prev[$key]}" != "open" ]; then
                sql+="UPDATE port_scan_state SET last_changed='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('server', '$esc_host', ${port}, 'opened', '$now');
"
                log "server port ${host}:${port}/${proto}"
                log "INFO: server port opened; service=${service:-unknown}"
            fi
        fi
    done <<< "$ss_out"

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

    if ! run_batch "$sql"; then
        if ! scan_attempt_failed "server" "$host"; then
            log "WARNING: could not store server scan for '$host' -alert"
        fi
        write_scan_marker "server" "$host" "$now" 0 "failed"
        return
    fi
    write_scan_marker "server" "$host" "$now" "${#seen[@]}"
}

# POLL: TARGET MODE
# Scan the selected remote target and record port state changes
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

    local nmap_out nmap_err_file
    nmap_err_file=$(mktemp "/tmp/nwatchports-nmap.XXXXXX") || {
        if ! scan_attempt_failed "target" "$target"; then
            log "WARNING: no nmap output for '$target' -alert"
        fi
        write_scan_marker "target" "$target" "$now" 0 "failed"
        return
    }
    if ! nmap_out=$(nmap -Pn -sT -sU -F -T4 --host-timeout 60s -oG - "$target" 2>"$nmap_err_file") \
        || ! printf '%s\n' "$nmap_out" | grep '^Host:.*Ports:' >/dev/null; then
        if ! scan_attempt_failed "target" "$target"; then
            log "WARNING: nmap did not complete for '$target' -alert"
            [ ! -s "$nmap_err_file" ] || cat "$nmap_err_file" >> "$log_file"
        fi
        rm -f "$nmap_err_file"
        write_scan_marker "target" "$target" "$now" 0 "failed"
        return
    fi

    [ ! -s "$nmap_err_file" ] || cat "$nmap_err_file" >> "$log_file"
    rm -f "$nmap_err_file"

    local ports_field
    ports_field=$(printf '%s\n' "$nmap_out" | grep '^Host:' | sed -n 's/.*Ports: //p')

    if [ -z "$ports_field" ]; then
        log "INFO: scan '$target' complete; no open ports reported"
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
        if ! run_batch "$sql"; then
            if ! scan_attempt_failed "target" "$target"; then
                log "WARNING: could not store target scan for '$target' -alert"
            fi
            write_scan_marker "target" "$target" "$now" 0 "failed"
            return
        fi
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
                log "target port ${target}:${port}/${proto}"
                log "INFO: target port opened; service=${service:-unknown}"
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
                log "target port ${target}:${port}/${proto}"
                log "INFO: target port ${event_type}; service=${service:-unknown}"
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

    if ! run_batch "$sql"; then
        if ! scan_attempt_failed "target" "$target"; then
            log "WARNING: could not store target scan for '$target' -alert"
        fi
        write_scan_marker "target" "$target" "$now" 0 "failed"
        return
    fi
    write_scan_marker "target" "$target" "$now" "$open_count"
}

# ONE POLL CYCLE
# Remove old closed-port records before subsequent polling
purge_stale_closed_ports() {
    sqlite3 -cmd "PRAGMA busy_timeout=${NWATCH_DB_TIMEOUT_MS};" "$db_file" \
        "DELETE FROM port_scan_state WHERE status='closed' AND julianday(last_changed) < julianday('now', '-${PURGE_CLOSED_AFTER_HOURS} hours');" \
        2>>"$log_file"
}

run_poll() {
    load_ports_mode
    local now
    now=$(now_iso)

    if [ "$PORTS_MODE" = "target" ]; then
        if [ -z "$PORTS_TARGET_IP" ]; then
            log "WARNING: mode is target with no target host -alert"
            return
        fi
        if ! valid_host "$PORTS_TARGET_IP"; then
            log "WARNING: invalid target host '$PORTS_TARGET_IP' -alert"
            return
        fi
        poll_target "$PORTS_TARGET_IP" "$now"
    else
        poll_server "$now"
    fi

    purge_stale_closed_ports
}

# START
# Start the configured daemon
start() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$script_lock")
    exec 200>"$script_lock"
    if ! flock -n 200; then
        log "ERROR: script $(basename "$0") is already running -abort"
        exit 1
    fi

    if [ -f "$pid_file" ] && daemon_alive "$(cat "$pid_file" 2>/dev/null)"; then
        log "ERROR: nwatchports is already running -abort"
        exit 1
    fi

    # Enforce perms unconditionally: the shared /var/log/nwatch.log may
    # already exist (created by the installer or the other daemon), so
    # normalize ownership/mode on every start rather than only on creation.
    touch "$log_file"
    chmod 640 "$log_file"
    chown root:root "$log_file"

    if [ ! -f "$ports_mode_file" ]; then
        write_ports_mode "server" "" || exit 1
    fi

    load_ports_mode
    log "INFO: Mode: $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    log "INFO: Interval: ${PORT_POLL_INTERVAL}s"
    log "INFO: Database: $db_file"

    rm -f "$pid_file"
    (
        exec 200>&-
        echo "$BASHPID" > "$pid_file"
        while true; do
            log "EVENT: nwatchports cycle start..."
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
    log "INFO: nwatchports started with PID $(cat "$pid_file" 2>/dev/null)"
}

# STOP
# Stop the recorded daemon process
stop() {
    log "EVENT: Stopping nwatchports..."
    if [ -f "$pid_file" ]; then
        local daemon_pid
        daemon_pid=$(cat "$pid_file")
        if daemon_alive "$daemon_pid"; then
            if ! kill "$daemon_pid" 2>/dev/null; then
                log "ERROR: cannot signal nwatchports (PID $daemon_pid) -abort"
                return 1
            fi
            sleep 1
            if daemon_alive "$daemon_pid"; then
                log "WARNING: nwatchports still running (PID $daemon_pid) -alert"
                return 1
            fi
            log "INFO: nwatchports stopped (PID $daemon_pid)"
        else
            log "INFO: nwatchports was not running (stale PID file removed)"
        fi
        rm -f "$pid_file"
    else
        log "INFO: nwatchports is not running"
    fi
}

# STATUS
# Report the current daemon or installation state
status() {
    log "EVENT: nwatchports status..."
    load_ports_mode
    if [ -f "$pid_file" ] && daemon_alive "$(cat "$pid_file")"; then
        log "INFO: nwatchports is RUNNING (PID $(cat "$pid_file"))"
        log "INFO: Mode: $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
        log "INFO: Interval: ${PORT_POLL_INTERVAL:-30}s"
        if [ -f "$db_file" ]; then
            local counts
            counts=$(sqlite3 "$db_file" "SELECT status, COUNT(*) FROM port_scan_state WHERE source='$(sql_escape "$PORTS_MODE")' GROUP BY status;" 2>/dev/null)
            log "INFO: Ports:"
            echo "$counts" | sed 's/^/ /' | tee -a "$log_file"
        fi
    else
        log "INFO: nwatchports is STOPPED"
        log "INFO: Mode: $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    fi
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# stop() needs only the PID file, so these checks are skipped for it
if [ "${1:-}" != --stop ]; then
    # PERMS
    # Owner and mode of every .env this script reads
    env_specs=("$nwatch_env root:www-data 640")
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
    source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/nwatchenv.sh"
    env_keys='SERVER_IP PORT_POLL_INTERVAL PURGE_CLOSED_AFTER_HOURS NWATCH_DB_TIMEOUT_MS'

    # LOAD
    load_nwatch_env "$nwatch_env" "$env_keys" || true

    # KEY CHECK
    # Collect every failure first, then decide -- a single abort reports them all
    key_errors=()
    for env_key in SERVER_IP; do
        if ! grep -q "^${env_key}=" "$nwatch_env"; then
            key_errors+=("$env_key missing line")
        elif [[ -z "${!env_key:-}" ]]; then
            key_errors+=("$env_key not set")
        fi
    done
    for env_key in PORT_POLL_INTERVAL PURGE_CLOSED_AFTER_HOURS NWATCH_DB_TIMEOUT_MS; do
        if ! grep -q "^${env_key}=" "$nwatch_env"; then
            key_errors+=("$env_key missing line")
        elif [[ -z "${!env_key:-}" ]]; then
            key_errors+=("$env_key not set")
        elif ! [[ "${!env_key}" =~ $UH_UINT ]] || [[ "${!env_key}" == 0 ]]; then
            key_errors+=("$env_key invalid count")
        elif ! uh_fits "${!env_key}"; then
            key_errors+=("$env_key exceeds the Bash integer range")
        fi
    done
    if (( ${#key_errors[@]} > 0 )); then
        for key_error in "${key_errors[@]}"; do
            log "WARNING: $key_error -alert"
        done
        log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$nwatch_env") -abort"
        log "ERROR: run nwatchsetup first -abort"
        exit 1
    fi
    unset key_errors key_error env_key

    # DB CHECK
    # Require an existing database before continuing
    if [ ! -f "$db_file" ]; then
        log "ERROR: $(basename "$db_file") missing; run nwatchsetup -abort"
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: nwatchports start..."
case "${1:-}" in
    --start) start ;;
    --stop) stop ;;
    --status) status ;;
    --mode) cmd_mode "$@" ;;
    --list) cmd_list ;;
    *) log "INFO: Usage: $(basename "$0") {--start|--stop|--status|--mode server|--mode target <host>|--list}"; exit 1 ;;
esac || exit 1

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: nwatchports done"
