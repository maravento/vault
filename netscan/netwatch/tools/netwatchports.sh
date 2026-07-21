#!/bin/bash
# maravento.com
#
################################################################################
#
# netwatch - Port Auditing Daemon + CLI
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

### CHECK DEPENDENCIES
for pkg in sqlite3 nmap ss; do
    command -v "$pkg" >/dev/null 2>&1 || {
        log "ERROR: '$pkg' is missing. Run: sudo apt install sqlite3 nmap iproute2"
        exit 1
    }
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
    local esc_val
    val=$(printf '%s' "$val" | tr -d '\r\n')
    esc_val=$(printf '%s' "$val" | sed -e 's/[\&|]/\\&/g')
    if grep -q "^${key}=" "$NETWATCH_ENV"; then
        sed -i "s|^${key}=.*|${key}=\"${esc_val}\"|" "$NETWATCH_ENV"
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

### UPSERT / TRANSITION HELPERS
upsert_port() {
    local source="$1" host="$2" port="$3" proto="$4" service="$5" status="$6" now="$7"

    local existing_status
    existing_status=$(sqlite3 "$DB_FILE" "SELECT status FROM port_scan_state WHERE source='$(sql_escape "$source")' AND host='$(sql_escape "$host")' AND port=${port} AND proto='$(sql_escape "$proto")';" 2>>"$log_file")

    if [ -z "$existing_status" ]; then
        sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" >/dev/null <<SQL
INSERT INTO port_scan_state (source, host, port, proto, service, status, last_checked, last_changed)
VALUES ('$(sql_escape "$source")', '$(sql_escape "$host")', ${port}, '$(sql_escape "$proto")', '$(sql_escape "$service")', '${status}', '${now}', '${now}');
SQL
        if [ "$status" = "open" ]; then
            sqlite3 "$DB_FILE" "INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('$(sql_escape "$source")', '$(sql_escape "$host")', ${port}, 'opened', '${now}');" 2>>"$log_file"
            log "Port opened: [$source] ${host}:${port}/${proto} (${service:-unknown})"
        fi
    else
        sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" >/dev/null <<SQL
UPDATE port_scan_state SET service='$(sql_escape "$service")', status='${status}', last_checked='${now}' WHERE source='$(sql_escape "$source")' AND host='$(sql_escape "$host")' AND port=${port} AND proto='$(sql_escape "$proto")';
SQL
        if [ "$status" != "$existing_status" ]; then
            sqlite3 "$DB_FILE" "UPDATE port_scan_state SET last_changed='${now}' WHERE source='$(sql_escape "$source")' AND host='$(sql_escape "$host")' AND port=${port} AND proto='$(sql_escape "$proto")';" 2>>"$log_file"
            sqlite3 "$DB_FILE" "INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('$(sql_escape "$source")', '$(sql_escape "$host")', ${port}, '${status}', '${now}');" 2>>"$log_file"
            log "Port ${status}: [$source] ${host}:${port}/${proto} (${service:-unknown})"
        fi
    fi
}

# server mode only: ss never reports closed ports, it simply omits them, so
# anything previously 'open' that's absent from this cycle's result must be
# closed explicitly. seen_file holds one "proto:port" pair per line so tcp
# and udp on the same port number aren't confused with each other.
close_missing() {
    local source="$1" host="$2" seen_file="$3" now="$4"
    local known
    known=$(sqlite3 -separator ':' "$DB_FILE" "SELECT proto, port FROM port_scan_state WHERE source='$(sql_escape "$source")' AND host='$(sql_escape "$host")' AND status='open';" 2>>"$log_file")
    while IFS=':' read -r proto port; do
        [ -z "$port" ] && continue
        if ! grep -qxF "${proto}:${port}" "$seen_file" 2>/dev/null; then
            sqlite3 "$DB_FILE" "UPDATE port_scan_state SET status='closed', last_checked='${now}', last_changed='${now}' WHERE source='$(sql_escape "$source")' AND host='$(sql_escape "$host")' AND port=${port} AND proto='$(sql_escape "$proto")';" 2>>"$log_file"
            sqlite3 "$DB_FILE" "INSERT INTO port_events (source, host, port, event_type, event_time) VALUES ('$(sql_escape "$source")', '$(sql_escape "$host")', ${port}, 'closed', '${now}');" 2>>"$log_file"
            log "Port closed: [$source] ${host}:${port}/${proto}"
        fi
    done <<< "$known"
}

### POLL: SERVER MODE
poll_server() {
    local now="$1"
    local host="${SERVER_IP:-localhost}"
    local seen
    seen=$(mktemp)

    # ss -Htulnp: no header, tcp+udp, listening, numeric ports, show owning
    # process. Fields: Netid State Recv-Q Send-Q LocalAddress:Port PeerAddress:Port Process
    # (udp sockets show State as "UNCONN" instead of "LISTEN" -- still the
    # right thing to report as an open/listening port).
    while read -r netid _state _recvq _sendq local_addr _peer_addr proc_field; do
        local port
        port="${local_addr##*:}"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        local proto="tcp"
        [ "$netid" = "udp" ] && proto="udp"
        local service
        service=$(printf '%s' "$proc_field" | sed -n 's/.*"\([^"]*\)".*/\1/p')
        echo "${proto}:${port}" >> "$seen"
        upsert_port "server" "$host" "$port" "$proto" "$service" "open" "$now"
    done < <(ss -Htulnp 2>/dev/null)

    close_missing "server" "$host" "$seen" "$now"
    rm -f "$seen"
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

    local entries entry
    IFS=',' read -ra entries <<< "$ports_field"
    for entry in "${entries[@]}"; do
        entry="${entry# }"
        [ -z "$entry" ] && continue
        local port state proto service _rest
        IFS='/' read -r port state proto _owner service _rest <<< "$entry"
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        [ "$proto" = "tcp" ] || [ "$proto" = "udp" ] || continue
        # nmap can report open|filtered / closed|filtered / filtered -- treat
        # anything other than a clean 'open' as closed for this audit view.
        local status="closed"
        [ "$state" = "open" ] && status="open"
        upsert_port "target" "$target" "$port" "$proto" "$service" "$status" "$now"
    done
}

### ONE POLL CYCLE
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

    if [ -z "${PORT_POLL_INTERVAL:-}" ]; then
        PORT_POLL_INTERVAL=30
        set_env_var "PORT_POLL_INTERVAL" "$PORT_POLL_INTERVAL"
    fi

    load_ports_mode
    log "Starting netwatchports..."
    log "Mode : $PORTS_MODE${PORTS_TARGET_IP:+ ($PORTS_TARGET_IP)}"
    log "Interval : ${PORT_POLL_INTERVAL}s"
    log "Database : $DB_FILE"
    log "Log : $log_file"

    (
        while true; do
            run_poll
            sleep "$PORT_POLL_INTERVAL"
        done
    ) &

    echo $! > "$PIDFILE"
    log "netwatchports started with PID $(cat "$PIDFILE")"

    if ! crontab -l 2>/dev/null | grep -qF "netwatchports.sh start"; then
        crontab -l 2>/dev/null > "/var/www/netwatch/tools/crontab-$(date +%Y%m%d%H%M%S).bak" || true
        (crontab -l 2>/dev/null; echo "@reboot /var/www/netwatch/tools/netwatchports.sh start") | crontab -
        log "Added to cron @reboot"
    fi
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
