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
#
# ports_mode.conf variables:
# PORTS_MODE : "server" or "target"
# PORTS_TARGET_IP : target host/IP, only used when PORTS_MODE=target
#
# Log file:
# /var/log/netwatch.log (root:root, 640) -- shared by all three netwatch
# scripts (installer + netwatchlan.sh + netwatchports.sh).
#
# Usage:
# ./netwatchports.sh {start|stop|status}
# ./netwatchports.sh mode server
# ./netwatchports.sh mode target <host>
# ./netwatchports.sh list
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
    log "ERROR: This script must be run as root"
    exit 1
fi

### PATHS
NETWATCH_ENV="/etc/netwatch/netwatch.env"
DB_FILE="/var/www/netwatch/data/netwatch.db"
PORTS_MODE_FILE="/var/www/netwatch/data/ports_mode.conf"
PIDFILE="/var/run/netwatchports.pid"

### DEPENDENCIES
for dep in sqlite3 nmap iproute2 procps gawk coreutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: Required dependency '$dep' is not installed."
        exit 1
    fi
done

### LOAD ENV
if [ ! -f "$NETWATCH_ENV" ]; then
    log "ERROR: netwatch is not installed. Run netwatchinstall.sh --install first."
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
    # $key is always a fixed constant from call sites in this script today
    # (never external input), but escape it for grep/sed's regex metachars
    # anyway rather than assume that stays true.
    esc_key=$(printf '%s' "$key" | sed 's/[.[\*^$]/\\&/g')
    if grep -q "^${esc_key}=" "$NETWATCH_ENV"; then
        sed -i "s|^${esc_key}=.*|${key}=\"${esc_val}\"|" "$NETWATCH_ENV"
    else
        echo "${key}=\"${val}\"" >> "$NETWATCH_ENV"
    fi
}

### DB CHECK
if [ ! -f "$DB_FILE" ]; then
    log "ERROR: Database not found at $DB_FILE. Run netwatchinstall.sh --install first."
    exit 1
fi

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

sql_escape() { printf '%s' "$1" | sed "s/'/''/g"; }

valid_host() {
    [[ "$1" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,251}[a-zA-Z0-9])?$ ]]
}

### PORTS MODE (server | target <ip>) -- kept in its own file, not
### netwatch.env, so the web-facing PHP process can write it without
### touching the panel's access-control config.
load_ports_mode() {
    PORTS_MODE="server"
    PORTS_TARGET_IP=""
    if [ -f "$PORTS_MODE_FILE" ]; then
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
        done < "$PORTS_MODE_FILE"
    fi
}

write_ports_mode() {
    local mode="$1" target="$2"
    local dir tmp_file
    dir="$(dirname "$PORTS_MODE_FILE")"
    mkdir -p "$dir"

    # Atomic write: build the new content in a temp file in the same
    # directory, then rename() into place. A reader (PHP or this script)
    # never sees a truncated/partial file mid-write -- mv/rename within the
    # same filesystem is atomic, unlike writing directly into
    # PORTS_MODE_FILE via `cat >`.
    tmp_file=$(mktemp "${PORTS_MODE_FILE}.XXXXXX")
    cat > "$tmp_file" <<EOF
PORTS_MODE="${mode}"
PORTS_TARGET_IP="${target}"
EOF
    chown www-data:www-data "$tmp_file" 2>/dev/null || true
    chmod 664 "$tmp_file"
    mv -f "$tmp_file" "$PORTS_MODE_FILE"
}

cmd_mode() {
    case "${2:-}" in
        server)
            write_ports_mode "server" ""
            echo "Mode set to: server"
            ;;
        target)
            local ip="$3"
            if [ -z "$ip" ]; then
                echo "Usage: $(basename "$0") mode target <host>"
                exit 1
            fi
            valid_host "$ip" || { echo "ERROR: Invalid target: $ip"; exit 1; }
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
    sqlite3 -separator '|' "$DB_FILE" "SELECT port, proto, status, IFNULL(service,'') FROM port_scan_state WHERE source='$(sql_escape "$PORTS_MODE")' AND host='$(sql_escape "$host")' ORDER BY port;" | \
        while IFS='|' read -r port proto status service; do
            printf "%-6s %-6s %-7s %s\n" "$port" "$proto" "$status" "$service"
        done
}

### BATCHED WRITE
# One transaction per poll cycle in a single sqlite3 process: each poll
# function loads the source/host's current state once, computes the transitions
# in bash, and hands the whole set of statements here. Data is substituted into
# the heredoc once (bash expansion is single-pass, so a '$' inside a value is
# not re-expanded); an empty batch is a no-op.
run_batch() {
    [ -z "${1:-}" ] && return 0
    sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" >/dev/null 2>>"$log_file" <<SQL
BEGIN IMMEDIATE;
${1}COMMIT;
SQL
}

### POLL: SERVER MODE
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
    done < <(sqlite3 -separator '|' "$DB_FILE" "SELECT proto, port, status FROM port_scan_state WHERE source='server' AND host='$esc_host';" 2>>"$log_file")

    local sql=""

    # ss -Htulnp: no header, tcp+udp, listening, numeric ports, show owning
    # process. Fields: Netid State Recv-Q Send-Q LocalAddress:Port PeerAddress:Port Process
    # (udp sockets show State as "UNCONN" instead of "LISTEN" -- still the
    # right thing to report as an open/listening port).
    local netid _state _recvq _sendq local_addr _peer_addr proc_field
    while read -r netid _state _recvq _sendq local_addr _peer_addr proc_field; do
        local port="${local_addr##*:}"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
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
            log "Port opened: [server] ${host}:${port}/${proto} (${service:-unknown})"
        else
            sql+="UPDATE port_scan_state SET service='$esc_service', status='open', last_checked='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
"
            if [ "${prev[$key]}" != "open" ]; then
                sql+="UPDATE port_scan_state SET last_changed='$now' WHERE source='server' AND host='$esc_host' AND port=${port} AND proto='$proto';
INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('server', '$esc_host', ${port}, 'opened', '$now');
"
                log "Port opened: [server] ${host}:${port}/${proto} (${service:-unknown})"
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
        log "Port closed: [server] ${host}:${port}/${proto}"
    done

    run_batch "$sql"
}

### POLL: TARGET MODE
poll_target() {
    local target="$1" now="$2"

    # -Pn: skip host-discovery (ICMP ping) and scan ports directly. Without
    # it, a target whose firewall drops ICMP looks "down" to nmap and the
    # whole scan is skipped -- even though its ports are actually reachable.
    # The target here was chosen explicitly by the operator, so there's no
    # need to first confirm the host is "up" the way a network sweep would.
    #
    # --host-timeout 60s: the poll loop is sequential (run_poll then sleep),
    # so an unbounded scan against a target that silently drops UDP probes
    # would stall every later cycle too, not just this one. Bail out after
    # 60s and pick up wherever it left off next cycle instead.
    local nmap_out
    nmap_out=$(nmap -Pn -sT -sU -F -T4 --host-timeout 60s -oG - "$target" 2>>"$log_file") || true

    local ports_field
    ports_field=$(printf '%s\n' "$nmap_out" | grep '^Host:' | sed -n 's/.*Ports: //p')

    if [ -z "$ports_field" ]; then
        log "WARNING: nmap returned no port data for target '$target' (host may be down/unreachable)"
        return
    fi

    local esc_target
    esc_target=$(sql_escape "$target")

    # current state (proto:port -> status), loaded once for the whole cycle
    declare -A prev=() seen=()
    local p_proto p_port p_stat
    while IFS='|' read -r p_proto p_port p_stat; do
        [ -z "$p_port" ] && continue
        prev["${p_proto}:${p_port}"]="$p_stat"
    done < <(sqlite3 -separator '|' "$DB_FILE" "SELECT proto, port, status FROM port_scan_state WHERE source='target' AND host='$esc_target';" 2>>"$log_file")

    local sql=""
    local entries entry
    IFS=',' read -ra entries <<< "$ports_field"
    for entry in "${entries[@]}"; do
        entry="${entry# }"
        [ -z "$entry" ] && continue
        local port state proto service _rest
        IFS='/' read -r port state proto _owner service _rest <<< "$entry"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        [ "$proto" = "tcp" ] || [ "$proto" = "udp" ] || continue
        local key="${proto}:${port}"
        [ -n "${seen[$key]:-}" ] && continue
        seen["$key"]=1
        # nmap can report open|filtered / closed|filtered / filtered -- treat
        # anything other than a clean 'open' as closed for this audit view.
        local status="closed"
        [ "$state" = "open" ] && status="open"
        local esc_service
        esc_service=$(sql_escape "$service")

        if [ -z "${prev[$key]:-}" ]; then
            sql+="INSERT INTO port_scan_state (source, host, port, proto, service, status, last_checked, last_changed) VALUES ('target', '$esc_target', ${port}, '$proto', '$esc_service', '$status', '$now', '$now');
"
            if [ "$status" = "open" ]; then
                sql+="INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('target', '$esc_target', ${port}, 'opened', '$now');
"
                log "Port opened: [target] ${target}:${port}/${proto} (${service:-unknown})"
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
                log "Port ${event_type}: [target] ${target}:${port}/${proto} (${service:-unknown})"
            fi
        fi
    done

    run_batch "$sql"
}

### ONE POLL CYCLE
# port_scan_state tracks current state, not history (port_events is the
# audit log and is never touched here) -- a 'closed' row that hasn't changed
# in PURGE_CLOSED_AFTER_HOURS is almost always a one-shot ephemeral port
# (mDNS/SSDP discovery, desktop apps opening transient sockets, etc.) that
# will never reopen, and left unpruned this table grows without bound: seen
# in production, ~4000 new closed rows/day for a single host (mostly
# "discovery", Firefox's "Socket Process", and even this project's own
# nbtscan calls from netwatchlan.sh's hostname resolution getting caught
# mid-flight by this daemon's `ss -tulnp` poll) -- a 7-day window was still
# far too long at that rate. Runs every cycle -- a no-op once caught up,
# since the WHERE clause only ever matches rows older than the window.
PURGE_CLOSED_AFTER_HOURS=6
purge_stale_closed_ports() {
    # julianday(), not a raw string comparison against datetime('now', ...):
    # last_changed is stored as "YYYY-MM-DDTHH:MM:SSZ" (now_iso()) but
    # datetime()'s own output is "YYYY-MM-DD HH:MM:SS" (space, no
    # trailing Z) -- comparing those two formats as strings is wrong right
    # at same-day boundaries (the 'T' vs ' ' byte sorts out of order).
    # julianday() parses ISO-8601 with 'T'/'Z' correctly and compares as
    # actual numeric time.
    sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" \
        "DELETE FROM port_scan_state WHERE status='closed' AND julianday(last_changed) < julianday('now', '-${PURGE_CLOSED_AFTER_HOURS} hours');" \
        2>>"$log_file"
}

run_poll() {
    load_ports_mode
    local now
    now=$(now_iso)

    if [ "$PORTS_MODE" = "target" ]; then
        if [ -z "$PORTS_TARGET_IP" ]; then
            log "WARNING: mode is 'target' but no target host is set; skipping cycle"
            return
        fi
        poll_target "$PORTS_TARGET_IP" "$now"
    else
        poll_server "$now"
    fi

    purge_stale_closed_ports
}

### START
start() {
    # prevent overlapping runs
    SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$SCRIPT_LOCK")
    exec 200>"$SCRIPT_LOCK"
    if ! flock -n 200; then
        log "Script $(basename "$0") is already running"
        exit 1
    fi

    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "netwatchports is already running with PID $(cat "$PIDFILE")"
        exit 1
    fi

    # Enforce perms unconditionally: the shared /var/log/netwatch.log may
    # already exist (created by the installer or the other daemon), so
    # normalize ownership/mode on every start rather than only on creation.
    touch "$log_file"
    chmod 640 "$log_file"
    chown root:root "$log_file"

    if [ ! -f "$PORTS_MODE_FILE" ]; then
        write_ports_mode "server" ""
    fi

    # A non-numeric value here (e.g. hand-edited netwatch.env) would make
    # `sleep "$PORT_POLL_INTERVAL"` fail every cycle without actually
    # sleeping, turning the loop into a busy-spin -- fall back to the
    # default instead of just checking for empty.
    if [ -z "${PORT_POLL_INTERVAL:-}" ] || ! [[ "$PORT_POLL_INTERVAL" =~ ^[0-9]+$ ]]; then
        [ -n "${PORT_POLL_INTERVAL:-}" ] && log "WARNING: PORT_POLL_INTERVAL='$PORT_POLL_INTERVAL' is not a valid number, defaulting to 30"
        PORT_POLL_INTERVAL=30
        set_env_var "PORT_POLL_INTERVAL" "$PORT_POLL_INTERVAL"
    fi

    load_ports_mode
    log "Starting netwatchports..."
    log "Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    log "Interval : ${PORT_POLL_INTERVAL}s"
    log "Database : $DB_FILE"
    log "Log : $log_file"

    # Fork the loop (keeps this function's variables/functions in scope,
    # unlike a re-exec'd `bash -c`), but explicitly detach it from the
    # controlling terminal: redirect all three fds away from the tty and
    # disown the job. A bare `(...) &` still inherits stdin/stdout/stderr,
    # which is why a foreground `./netwatchports.sh start` never returned
    # control -- the shell/terminal waits for those fds to close.
    # stdout/stderr go to /dev/null, not $log_file: log() already appends
    # every line to $log_file itself via `tee -a`, so redirecting the
    # subshell's inherited stdout there too would double-write each line
    # (tee's own stdout copy landing back in the same file a second time).
    # The child writes its own PID (via $BASHPID) as its very first action,
    # before entering the loop -- not the parent writing $! after
    # backgrounding. That used to leave a window where the daemon was
    # already running but PIDFILE didn't exist yet (stop()/status() would
    # report it as not running).
    rm -f "$PIDFILE"
    (
        echo "$BASHPID" > "$PIDFILE"
        while true; do
            run_poll
            sleep "$PORT_POLL_INTERVAL"
        done
    ) </dev/null >/dev/null 2>&1 &
    disown

    # Wait (briefly) for the child to have written its PID before logging it.
    for _ in $(seq 1 20); do
        [ -s "$PIDFILE" ] && break
        sleep 0.05
    done
    log "netwatchports started with PID $(cat "$PIDFILE" 2>/dev/null)"
}

### STOP
stop() {
    log "Stopping netwatchports..."
    if [ -f "$PIDFILE" ]; then
        local PID PGID
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
            PGID=$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ')
            if [ -n "$PGID" ]; then
                kill -- "-$PGID" 2>/dev/null
            else
                kill "$PID" 2>/dev/null
            fi
            log "netwatchports stopped (PID $PID)"
        else
            log "netwatchports was not running (stale PID file removed)"
        fi
        rm -f "$PIDFILE"
    else
        log "netwatchports is not running"
    fi
}

### STATUS
status() {
    log "netwatchports status..."
    load_ports_mode
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        log "netwatchports is RUNNING (PID $(cat "$PIDFILE"))"
        log "Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
        log "Interval : ${PORT_POLL_INTERVAL:-30}s"
        if [ -f "$DB_FILE" ]; then
            local counts
            counts=$(sqlite3 "$DB_FILE" "SELECT status, COUNT(*) FROM port_scan_state WHERE source='$(sql_escape "$PORTS_MODE")' GROUP BY status;" 2>/dev/null)
            log "Ports :"
            echo "$counts" | sed 's/^/ /' | tee -a "$log_file"
        fi
    else
        log "netwatchports is STOPPED"
        log "Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    fi
}

### MAIN
case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    mode) cmd_mode "$@" ;;
    list) cmd_list ;;
    *) log "Usage: $(basename "$0") {start|stop|status|mode server|mode target <host>|list}" ;;
esac
