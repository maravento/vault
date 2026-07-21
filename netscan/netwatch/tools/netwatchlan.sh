#!/bin/bash
# maravento.com
#
################################################################################
#
# netwatch - LAN Devices Watchdog
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
# Log file:
# /var/log/netwatch.log (root:root, 640) -- shared by all three netwatch
# scripts (installer + netwatchlan.sh + netwatchports.sh).
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
    log "ERROR: This script must be run as root"
    exit 1
fi

### PATHS
NETWATCH_ENV="/etc/netwatch/netwatch.env"
DB_FILE="/var/www/netwatch/data/netwatch.db"
PIDFILE="/var/run/netwatchlan.pid"

### CHECK DEPENDENCIES
for pkg in arp-scan sqlite3; do
    command -v "$pkg" >/dev/null 2>&1 || {
        log "ERROR: '$pkg' is missing. Run: sudo apt install $pkg"
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

### ONE SCAN CYCLE
run_scan() {
    if [ -z "${LAN_IFACES:-}" ]; then
        log "ERROR: LAN_IFACES is not set"
        return 1
    fi

    local now
    now=$(now_iso)

    local seen_macs
    seen_macs=$(mktemp)

    local ifaces iface
    IFS=',' read -ra ifaces <<< "$LAN_IFACES"
    for iface in "${ifaces[@]}"; do
        if ! ip link show "$iface" &>/dev/null; then
            log "WARNING: interface '$iface' does not exist, skipping"
            continue
        fi

        # arp-scan plain output, tab-separated: IP<TAB>MAC<TAB>Vendor.
        # -q (--quiet) is deliberately NOT used here -- it strips the vendor
        # field entirely ("Only the IP address and MAC address are
        # displayed"), which is why every row showed a blank Vendor column.
        local scan_out
        scan_out=$(arp-scan --interface="$iface" --localnet -x -g 2>>"$log_file") || true

        while IFS=$'\t' read -r ip mac vendor; do
            [ -z "$ip" ] && continue
            [ -z "$mac" ] && continue
            mac=$(echo "$mac" | tr 'A-F' 'a-f')
            echo "$mac" >> "$seen_macs"

            local hostname=""
            hostname=$(resolve_hostname "$ip")
            local hostname_esc
            hostname_esc=$(echo "$hostname" | sed "s/'/''/g")

            local existing
            existing=$(sqlite3 "$DB_FILE" "SELECT 1 FROM devices WHERE mac='${mac}';" 2>>"$log_file")

            if [ -z "$existing" ]; then
                sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" >/dev/null <<SQL
INSERT INTO devices (mac, ip, iface, vendor, hostname, status, first_seen, last_seen, miss_count)
VALUES ('${mac}', '${ip}', '${iface}', '$(echo "$vendor" | sed "s/'/''/g")', '${hostname_esc}', 'online', '${now}', '${now}', 0);
INSERT INTO device_events (mac, ip, event_type, event_time)
VALUES ('${mac}', '${ip}', 'new_device', '${now}');
SQL
                log "New device: $ip ($mac) on $iface"
            else
                local prev_status
                prev_status=$(sqlite3 "$DB_FILE" "SELECT status FROM devices WHERE mac='${mac}';" 2>>"$log_file")
                # A transient resolution failure (empty $hostname this cycle)
                # must not blank out a hostname resolved on a previous cycle.
                sqlite3 -cmd "PRAGMA busy_timeout=5000;" "$DB_FILE" >/dev/null <<SQL
UPDATE devices SET ip='${ip}', iface='${iface}', vendor='$(echo "$vendor" | sed "s/'/''/g")', hostname=CASE WHEN '${hostname_esc}' != '' THEN '${hostname_esc}' ELSE hostname END, status='online', last_seen='${now}', miss_count=0 WHERE mac='${mac}';
SQL
                if [ "$prev_status" = "offline" ]; then
                    sqlite3 "$DB_FILE" "INSERT INTO device_events (mac, ip, event_type, event_time) VALUES ('${mac}', '${ip}', 'online', '${now}');" 2>>"$log_file"
                    log "Device back online: $ip ($mac) on $iface"
                fi
            fi
        done <<< "$scan_out"
    done

    # mark devices not seen this cycle on ANY configured interface
    local known_macs
    known_macs=$(sqlite3 "$DB_FILE" "SELECT mac FROM devices WHERE status='online';" 2>>"$log_file")
    while IFS= read -r mac; do
        [ -z "$mac" ] && continue
        if ! grep -qxF "$mac" "$seen_macs" 2>/dev/null; then
            sqlite3 "$DB_FILE" "UPDATE devices SET miss_count = miss_count + 1 WHERE mac='${mac}';" 2>>"$log_file"
            local miss ip_addr
            miss=$(sqlite3 "$DB_FILE" "SELECT miss_count FROM devices WHERE mac='${mac}';" 2>>"$log_file")
            if [ "${miss:-0}" -ge "${LAN_OFFLINE_GRACE:-3}" ]; then
                ip_addr=$(sqlite3 "$DB_FILE" "SELECT ip FROM devices WHERE mac='${mac}';" 2>>"$log_file")
                sqlite3 "$DB_FILE" "UPDATE devices SET status='offline' WHERE mac='${mac}' AND status='online';" 2>>"$log_file"
                sqlite3 "$DB_FILE" "INSERT INTO device_events (mac, ip, event_type, event_time) VALUES ('${mac}', '${ip_addr}', 'offline', '${now}');" 2>>"$log_file"
                log "Device offline: $ip_addr ($mac)"
            fi
        fi
    done <<< "$known_macs"

    rm -f "$seen_macs"
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

    ### CHECK AND SET LAN_POLL_INTERVAL
    if [ -z "${LAN_POLL_INTERVAL:-}" ]; then
        LAN_POLL_INTERVAL=60
        set_env_var "LAN_POLL_INTERVAL" "$LAN_POLL_INTERVAL"
    fi

    ### CHECK AND SET LAN_OFFLINE_GRACE
    if [ -z "${LAN_OFFLINE_GRACE:-}" ]; then
        LAN_OFFLINE_GRACE=3
        set_env_var "LAN_OFFLINE_GRACE" "$LAN_OFFLINE_GRACE"
    fi

    log "Starting netwatchlan..."
    log "Interfaces : $LAN_IFACES"
    log "Interval : ${LAN_POLL_INTERVAL}s"
    log "Offline grace: ${LAN_OFFLINE_GRACE} polls"
    log "Database : $DB_FILE"
    log "Log : $log_file"

    (
        while true; do
            run_scan
            sleep "$LAN_POLL_INTERVAL"
        done
    ) &

    echo $! > "$PIDFILE"
    log "netwatchlan started with PID $(cat "$PIDFILE")"

    # add @reboot cron entry if not already present
    if ! crontab -l 2>/dev/null | grep -qF "netwatchlan.sh start"; then
        crontab -l 2>/dev/null > "/var/www/netwatch/tools/crontab-$(date +%Y%m%d%H%M%S).bak" || true
        (crontab -l 2>/dev/null; echo "@reboot /var/www/netwatch/tools/netwatchlan.sh start") | crontab -
        log "Added to cron @reboot"
    fi
}

### STOP
stop() {
    log "Stopping netwatchlan..."
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
