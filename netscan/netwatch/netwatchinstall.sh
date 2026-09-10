#!/bin/bash
# maravento.com
#
################################################################################
#
# netwatch - LAN device inventory & watched ports dashboard
# https://github.com/maravento/vault
#
# log: netwatchinstall.log, next to this script (rewritten on each run)
# The daemons netwatchlan.sh / netwatchports.sh log to the shared
# /var/log/netwatch.log, rotated weekly via /etc/logrotate.d/netwatch
# (deployed by --install, removed by --uninstall).
#
################################################################################

set -uo pipefail

# PATHS
script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

# logging
log_file="$script_dir/netwatchinstall.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

touch "$log_file"
chmod 640 "$log_file"
chown root:root "$log_file"

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

web_dir="$script_dir/web"
tools_dir="$script_dir/tools"
netwatch_www="/var/www/netwatch"
netwatch_web="$netwatch_www/web"
netwatch_tools="$netwatch_www/tools"
netwatch_data="$netwatch_www/data"
# netwatch.env is read-only config (access-control CIDR etc.) and lives in
# /etc/netwatch, root-owned, so the web process can never write it. The
# mutable, web-writable ports_mode.conf stays in the data dir (still outside
# the DocumentRoot) -- /etc should hold root-writable config only, not a file
# the web user rewrites on every mode change.
netwatch_etc="/etc/netwatch"
netwatch_env="$netwatch_etc/netwatch.env"
db_file="$netwatch_data/netwatch.db"
ports_mode_file="$netwatch_data/ports_mode.conf"
vhost_port="3126"

# REPOSITORY STRUCTURE CHECK
check_repo() {
    local missing=0
    for dir in "$web_dir" "$tools_dir"; do
        if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            missing=1
            break
        fi
    done
    if [ "$missing" -eq 1 ]; then
        log "ERROR: Repository files not found. Run:"
        log "git clone https://github.com/maravento/vault"
        exit 1
    fi
}
check_repo

# dependencies
for dep in systemd apache2 libapache2-mod-php php-cli php-sqlite3 arp-scan sqlite3 nmap iproute2 logrotate cron procps coreutils findutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed"
        exit 1
    fi
done

# INTERFACE / NETWORK SELECTION
# Virtual/loopback interfaces are never useful arp-scan targets and are
# hidden from every selector below (both the scan-interfaces prompt and the
# management-interface prompt).
virtual_iface_pattern='^(lo|docker.*|br-.*|veth.*|virbr.*|tun.*|tap.*|wg.*)$'

# validation -- one variable per thing validated; use directly with =~
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'
UH_UINT='^(0|[1-9][0-9]*)$'

candidate_names=()
candidate_addrs=()
list_candidate_interfaces() {
    candidate_names=()
    candidate_addrs=()
    local iface addr
    while read -r iface addr; do
        [ -z "$iface" ] && continue
        [[ "$iface" =~ $virtual_iface_pattern ]] && continue
        candidate_names+=("$iface")
        candidate_addrs+=("$addr")
    done < <(ip -4 addr show scope global | awk '/inet /{print $NF, $2}')
    if [ "${#candidate_names[@]}" -eq 0 ]; then
        echo "ERROR: No physical network interfaces with a global IPv4 address found (virtual/loopback interfaces are excluded)."
        exit 1
    fi
}

print_candidate_interfaces() {
    local i
    for i in "${!candidate_names[@]}"; do
        printf " %2d) %-12s %s\n" "$((i + 1))" "${candidate_names[$i]}" "${candidate_addrs[$i]}"
    done
}

# Multiple interfaces (e.g. a LAN NIC and a WAN NIC) can be scanned at once --
# netwatchlan.sh arp-scans every one of them each poll cycle.
select_scan_interfaces() {
    list_candidate_interfaces
    echo ""
    echo "Available network interfaces (virtual/loopback interfaces are hidden):"
    print_candidate_interfaces
    echo ""
    local all_idxs
    all_idxs=$(seq -s, 1 "${#candidate_names[@]}")
    while true; do
        read -rp "Select interface(s) to scan -- comma-separated numbers (default: $all_idxs): " sel
        sel="${sel//[[:space:]]/}"
        sel="${sel:-$all_idxs}"
        local idxs chosen idx ok
        IFS=',' read -ra idxs <<< "$sel"
        chosen=()
        ok=1
        for idx in "${idxs[@]}"; do
            if ! [[ "$idx" =~ $UH_UINT ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#candidate_names[@]}" ]; then
                echo "ERROR: Invalid selection '$idx'. Try again."
                ok=0
                break
            fi
            chosen+=("${candidate_names[$((idx - 1))]}")
        done
        [ "$ok" -eq 1 ] || continue
        ifaces_answer=$(printf '%s\n' "${chosen[@]}" | awk '!seen[$0]++' | paste -sd, -)
        break
    done
    echo "Scanning interfaces: $ifaces_answer"
}

# Computes the actual network address for an "ip/prefix" pair (e.g.
# 192.168.0.24/24 -> 192.168.0.0/24) by zeroing the host bits -- `ip addr
# show` reports the interface's own host address with its prefix length,
# not the network address, and NET_CIDR (used as the Apache "Require ip"
# argument and stored in netwatch.env) is supposed to be the latter.
compute_network_cidr() {
    local ip_prefix="$1"
    local ip="${ip_prefix%/*}" prefix="${ip_prefix#*/}"
    local i1 i2 i3 i4
    IFS=. read -r i1 i2 i3 i4 <<< "$ip"
    local ip_int=$(( (i1<<24) + (i2<<16) + (i3<<8) + i4 ))
    local mask_int
    if [ "$prefix" -eq 0 ]; then mask_int=0; else mask_int=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF )); fi
    local net_int=$(( ip_int & mask_int ))
    printf '%d.%d.%d.%d/%s' $(( (net_int>>24)&255 )) $(( (net_int>>16)&255 )) $(( (net_int>>8)&255 )) $(( net_int&255 )) "$prefix"
}

# The web panel's IP allowlist (netwatchapi.php) is tied to a single
# management interface, kept separate from the (possibly multiple) scan
# interfaces so the panel is never accidentally exposed over a WAN NIC.
select_management_interface() {
    echo ""
    echo "Select the management interface the web panel will trust for access control."
    echo "This should be your LAN/admin interface -- never select a WAN interface here."
    print_candidate_interfaces
    echo ""
    while true; do
        read -rp "Select management interface number (default: 1): " idx
        idx="${idx:-1}"
        if ! [[ "$idx" =~ $UH_UINT ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#candidate_names[@]}" ]; then
            echo "ERROR: Invalid selection. Try again."
            continue
        fi
        mgmt_answer="${candidate_names[$((idx - 1))]}"
        break
    done
    local ip_with_prefix
    ip_with_prefix=$(ip -4 addr show dev "$mgmt_answer" scope global | sed -n 's/.*inet \([0-9.]\{1,\}\/[0-9]\{1,\}\).*/\1/p' | head -n1)
    if ! [[ "$ip_with_prefix" =~ $UH_CIDR ]]; then
        log "ERROR: no valid IPv4/CIDR on '$mgmt_answer' -- abort"
        exit 1
    fi
    net_cidr_value=$(compute_network_cidr "$ip_with_prefix")
    detected_ip=$(ip -4 addr show dev "$mgmt_answer" scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    echo "Management interface : $mgmt_answer"
    echo "Network : $net_cidr_value"
    echo "Server IP : $detected_ip"
}

# INITIALIZE DB SCHEMA
init_schema() {
    sqlite3 "$db_file" >/dev/null <<'SQL'
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS devices (
    mac TEXT PRIMARY KEY,
    ip TEXT NOT NULL,
    iface TEXT,
    vendor TEXT,
    hostname TEXT,
    status TEXT NOT NULL CHECK(status IN ('online','offline')),
    first_seen TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    miss_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen);

CREATE TABLE IF NOT EXISTS device_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT NOT NULL,
    ip TEXT,
    event_type TEXT NOT NULL CHECK(event_type IN ('new_device','online','offline')),
    event_time TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_device_events_time ON device_events(event_time);
CREATE INDEX IF NOT EXISTS idx_device_events_mac ON device_events(mac);

-- Current state of every port ever seen, either on the server itself
-- (source='server', read live from listening sockets via `ss`) or on a
-- user-chosen external target (source='target', read live via a fast nmap
-- scan). Only one source is actively polled at a time (see ports_mode.conf)
-- to avoid mixing self-audit and target-audit traffic/noise, but rows from
-- a previous target are kept as history, not deleted on mode switch.
CREATE TABLE IF NOT EXISTS port_scan_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL CHECK(source IN ('server','target')),
    host TEXT NOT NULL,
    port INTEGER NOT NULL CHECK(port BETWEEN 1 AND 65535),
    proto TEXT NOT NULL DEFAULT 'tcp',
    service TEXT,
    status TEXT NOT NULL CHECK(status IN ('open','closed')),
    last_checked TEXT NOT NULL,
    last_changed TEXT NOT NULL,
    UNIQUE(source, host, port, proto)
);
CREATE INDEX IF NOT EXISTS idx_port_scan_state_source ON port_scan_state(source);
CREATE INDEX IF NOT EXISTS idx_port_scan_state_status ON port_scan_state(status);

CREATE TABLE IF NOT EXISTS port_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    host TEXT NOT NULL,
    port INTEGER NOT NULL,
    event_type TEXT NOT NULL CHECK(event_type IN ('opened','closed')),
    event_time TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_port_events_time ON port_events(event_time);
CREATE INDEX IF NOT EXISTS idx_port_events_hostport ON port_events(source, host, port);
SQL
}

# INSTALL
# CHECK ALREADY INSTALLED
check_already_installed() {
    local installed=0
    local reasons=""

    if [ -f "$netwatch_env" ]; then
        installed=1
        reasons+=" - netwatch.env already exists: $netwatch_env\n"
    fi

    if [ -f "/etc/apache2/sites-available/netwatch.conf" ]; then
        installed=1
        reasons+=" - vhost already configured: /etc/apache2/sites-available/netwatch.conf\n"
    fi

    if [ "$installed" -eq 1 ]; then
        log "ERROR: netwatch is already installed. Aborting."
        echo ""
        printf "%b" "$reasons"
        echo ""
        log "To update, run: sudo bash netwatchinstall.sh --update"
        exit 1
    fi
}

# crontab backup
backup_crontab() {
    local cron_user="$1"
    local backup_dir="/etc/bak/crontab"
    local crontab_tmp

    [ -n "$cron_user" ] || return 1
    mkdir -p "$backup_dir" || return 1

    crontab_tmp=$(mktemp)
    if crontab -u "$cron_user" -l > "$crontab_tmp" 2>/dev/null && [ -s "$crontab_tmp" ]; then
        mv -f "$crontab_tmp" "$backup_dir/${cron_user}.bak"
    else
        rm -f "$crontab_tmp"
    fi
}

# add one @reboot cron entry per daemon, so a failure in one never keeps
# the other from starting
add_reboot_cron() {
    if ! crontab -l 2>/dev/null | grep -qF "$netwatch_tools/netwatchlan.sh start"; then
        backup_crontab root
        (crontab -l 2>/dev/null; echo "@reboot $netwatch_tools/netwatchlan.sh start"; echo "@reboot $netwatch_tools/netwatchports.sh start") | crontab -
        log "INFO: added to cron @reboot"
    fi
}

do_install() {
    log "netwatchinstall start (install)..."

    check_already_installed

    # dependency checks
    if systemctl is-active --quiet nginx; then
        log "ERROR: nginx is running -- abort"
        log "Disable it first: systemctl stop nginx"
        exit 1
    fi

    if ! systemctl is-active --quiet apache2; then
        log "ERROR: apache2 is not running -- abort"
        log "Start it first: systemctl start apache2"
        exit 1
    fi

    # The vhost needs mod_php (SetHandler application/x-httpd-php), not PHP-FPM.
    if ! apache2ctl -M 2>/dev/null | grep -qi 'php_module'; then
        log "ERROR: Apache mod_php is not loaded -- abort"
        log "Run first:"
        log "apt-get install -y libapache2-mod-php"
        log "a2enmod php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"
        log "systemctl restart apache2"
        exit 1
    fi

    a2enmod -q headers

    select_scan_interfaces
    select_management_interface

    mkdir -p "$netwatch_web" "$netwatch_tools" "$netwatch_data" "$netwatch_etc"

    cp -f "$web_dir"/*.php "$web_dir"/*.html "$netwatch_web/"
    chmod -R 755 "$netwatch_web"
    chown -R www-data:www-data "$netwatch_web"

    cp -f "$tools_dir"/*.sh "$netwatch_tools/"
    chmod +x "$netwatch_tools"/*.sh

    init_schema
    chown -R www-data:www-data "$netwatch_data"
    chmod 775 "$netwatch_data"
    # netwatch.db: root:www-data 640 -- daemons (root) read/write, web reads only.
    chown root:www-data "$db_file"
    chmod 640 "$db_file"

    # Config dir /etc/netwatch: same model as proxymon's /etc/proxymon --
    # root:www-data 750, holds only read-only config (netwatch.env). The
    # web process must never be the writer of anything under /etc.
    chown root:www-data "$netwatch_etc"
    chmod 750 "$netwatch_etc"

    # ports_mode.conf: mutable, web-writable state (active watch mode +
    # target IP) -- stays in the data dir, www-data:www-data, same as any
    # other web-writable file in this project (never under /etc).
    cat > "$ports_mode_file" <<'PMODE'
PORTS_MODE="server"
PORTS_TARGET_IP=""
PMODE
    chown www-data:www-data "$ports_mode_file"
    chmod 664 "$ports_mode_file"

    # apache vhost
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    sed -i "/^Listen .*:${vhost_port}\$/d" /etc/apache2/ports.conf
    printf 'Listen %s:%s\nListen 127.0.0.1:%s\n' "$detected_ip" "$vhost_port" "$vhost_port" | tee -a /etc/apache2/ports.conf
    sed "s|192.168.0.0/24|${net_cidr_value}|" "$web_dir/netwatch.conf" > /etc/apache2/sites-available/netwatch.conf
    a2ensite -q netwatch.conf

    systemctl daemon-reload
    systemctl restart apache2

    # save install config; poll intervals are left unset here and get their
    # defaults from the daemons themselves (see LAN_POLL_INTERVAL,
    # LAN_OFFLINE_GRACE, PORT_POLL_INTERVAL, PURGE_CLOSED_AFTER_HOURS).
    cat > "$netwatch_env" <<ENV
LAN_IFACES="$ifaces_answer"
MGMT_IFACE="$mgmt_answer"
NET_CIDR="$net_cidr_value"
SERVER_IP="$detected_ip"
ENV
    chown root:www-data "$netwatch_env"
    chmod 640 "$netwatch_env"

    # logrotate: the shared log has no size cap otherwise (both daemons
    # write to it indefinitely).
    cp -f /etc/logrotate.d/netwatch{,.bak} &>/dev/null
    cat > /etc/logrotate.d/netwatch <<'EOF'
/var/log/netwatch.log {
    weekly
    missingok
    rotate 7
    create 0640 root root
    compress
    notifempty
}
EOF

    # start daemons -- they are netwatch's core, not an optional extra, so
    # they auto-start right after install.
    "$netwatch_tools/netwatchlan.sh" start
    "$netwatch_tools/netwatchports.sh" start
    add_reboot_cron

    echo ""
    echo "LAN tab : http://localhost:${vhost_port}/?tab=lan"
    echo "Ports tab : http://localhost:${vhost_port}/?tab=ports"
    echo "Env file : $netwatch_env"
    echo "Database : $db_file"
    echo "Tools dir : $netwatch_tools"
    echo ""

    log "netwatchinstall done at: $(date)"
}

# UPDATE
do_update() {
    log "netwatchinstall start (update)..."

    # Migration: netwatch.env from $netwatch_www to /etc/netwatch
    local legacy_env="$netwatch_www/netwatch.env"
    if [ ! -f "$netwatch_env" ] && [ -f "$legacy_env" ]; then
        log "INFO: migrating netwatch.env to $netwatch_env"
        mkdir -p "$netwatch_etc"
        chown root:www-data "$netwatch_etc"
        chmod 750 "$netwatch_etc"
        mv -f "$legacy_env" "$netwatch_env"
        chown root:www-data "$netwatch_env"
        chmod 640 "$netwatch_env"
    fi

    if [ ! -f "$netwatch_env" ]; then
        log "ERROR: netwatch is not installed."
        exit 1
    fi

    # Migration: add proto to the port_scan_state UNIQUE constraint
    if [ -f "$db_file" ]; then
        local current_schema
        current_schema=$(sqlite3 "$db_file" "SELECT sql FROM sqlite_master WHERE type='table' AND name='port_scan_state';" 2>/dev/null)
        if [ -n "$current_schema" ] && ! printf '%s' "$current_schema" | grep -q "UNIQUE(source, host, port, proto)"; then
            log "INFO: migrating port_scan_state constraint"
            sqlite3 "$db_file" >/dev/null <<'SQL'
BEGIN TRANSACTION;
CREATE TABLE port_scan_state_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL CHECK(source IN ('server','target')),
    host TEXT NOT NULL,
    port INTEGER NOT NULL CHECK(port BETWEEN 1 AND 65535),
    proto TEXT NOT NULL DEFAULT 'tcp',
    service TEXT,
    status TEXT NOT NULL CHECK(status IN ('open','closed')),
    last_checked TEXT NOT NULL,
    last_changed TEXT NOT NULL,
    UNIQUE(source, host, port, proto)
);
INSERT INTO port_scan_state_new (id, source, host, port, proto, service, status, last_checked, last_changed)
    SELECT id, source, host, port, proto, service, status, last_checked, last_changed FROM port_scan_state;
DROP TABLE port_scan_state;
ALTER TABLE port_scan_state_new RENAME TO port_scan_state;
CREATE INDEX IF NOT EXISTS idx_port_scan_state_source ON port_scan_state(source);
CREATE INDEX IF NOT EXISTS idx_port_scan_state_status ON port_scan_state(status);
COMMIT;
SQL
        fi

        chown root:www-data "$db_file"
        chmod 640 "$db_file"
    fi

    "$netwatch_tools/netwatchlan.sh" stop 2>/dev/null || true
    "$netwatch_tools/netwatchports.sh" stop 2>/dev/null || true

    # web files (application code only -- netwatch.conf is never overwritten,
    # it may contain manual edits after install)
    mkdir -p "$netwatch_www/backups"
    for src in "$web_dir"/*.php "$web_dir"/*.html; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        dst="$netwatch_web/$fname"
        [ -f "$dst" ] && cp -f "$dst" "$netwatch_www/backups/$fname.bak" &>/dev/null
        cp -f "$src" "$dst"
        log "INFO: updated $fname"
    done
    chown -R www-data:www-data "$netwatch_web"

    for f in "$tools_dir"/*.sh; do
        [ -f "$f" ] || continue
        fname="$(basename "$f")"
        [ -f "$netwatch_tools/$fname" ] && cp -f "$netwatch_tools/$fname" "$netwatch_www/backups/$fname.bak" &>/dev/null
        cp -f "$f" "$netwatch_tools/$fname"
        chmod +x "$netwatch_tools/$fname"
        log "INFO: updated $fname"
    done

    "$netwatch_tools/netwatchlan.sh" start
    "$netwatch_tools/netwatchports.sh" start
    add_reboot_cron

    systemctl restart apache2

    log "netwatchinstall done at: $(date)"
}

# UNINSTALL
do_uninstall() {
    # Confirm before the rm -rf below (interactive runs only)
    if [ -t 0 ]; then
        local confirm
        read -r -p "This will permanently remove NetWatch and its data (LAN/port history). Continue? (y/N): " confirm
        case "$confirm" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi

    log "netwatchinstall start (uninstall)..."

    "$netwatch_tools/netwatchlan.sh" stop 2>/dev/null || true
    "$netwatch_tools/netwatchports.sh" stop 2>/dev/null || true

    a2dissite -q netwatch.conf &>/dev/null
    sed -i "/^Listen .*:${vhost_port}\$/d" /etc/apache2/ports.conf
    rm -f /etc/apache2/sites-available/netwatch.conf

    rm -rf "$netwatch_www"
    rm -rf "$netwatch_etc"

    rm -f /etc/logrotate.d/netwatch /etc/logrotate.d/netwatch.bak

    # cron entries -- matched by full command/path, not bare substrings
    backup_crontab root
    cron_tmp=$(mktemp)
    crontab -l 2>/dev/null > "$cron_tmp" || true
    grep -vF "$netwatch_tools/netwatchlan.sh start" "$cron_tmp" > "${cron_tmp}.next" || true
    mv "${cron_tmp}.next" "$cron_tmp"
    grep -vF "$netwatch_tools/netwatchports.sh start" "$cron_tmp" > "${cron_tmp}.next" || true
    mv "${cron_tmp}.next" "$cron_tmp"
    crontab "$cron_tmp"
    rm -f "$cron_tmp"

    systemctl daemon-reload
    systemctl restart apache2

    log "netwatchinstall done at: $(date)"
}

# STATUS
do_status() {
    log "netwatchinstall start (status)..."

    echo "=== netwatch Daemons ==="
    for name in netwatchlan netwatchports; do
        pidfile="/run/${name}.pid"
        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            echo "$name: RUNNING (PID $(cat "$pidfile"))"
        else
            echo "$name: STOPPED"
        fi
    done

    echo ""
    echo "=== Apache Port ==="
    if ss -tlnp 2>/dev/null | grep -qE ":${vhost_port}[[:space:]]"; then
        echo ":${vhost_port} OPEN"
    else
        echo ":${vhost_port} CLOSED"
    fi

    echo ""
    echo "=== Log ==="
    echo "$log_file (last 10):"
    [ -f "$log_file" ] && tail -10 "$log_file" | sed 's/^/ /' || echo " (not found)"

    echo ""
    echo "=== Config ==="
    if [ -f "$netwatch_env" ]; then
        echo "Scan interfaces : $(grep '^LAN_IFACES=' "$netwatch_env" | cut -d= -f2- | tr -d '"')"
        echo "Management iface : $(grep '^MGMT_IFACE=' "$netwatch_env" | cut -d= -f2- | tr -d '"')"
    else
        echo "$netwatch_env not found"
    fi
    if [ -f "$ports_mode_file" ]; then
        echo "Ports mode : $(grep '^PORTS_MODE=' "$ports_mode_file" | cut -d= -f2- | tr -d '"')"
        echo "Ports target : $(grep '^PORTS_TARGET_IP=' "$ports_mode_file" | cut -d= -f2- | tr -d '"')"
    fi

    echo ""
    echo "=== Database ==="
    if [ -f "$db_file" ]; then
        echo "Devices:"
        sqlite3 "$db_file" "SELECT status, COUNT(*) FROM devices GROUP BY status;" 2>/dev/null | sed 's/^/ /'
        echo "Ports (active mode):"
        sqlite3 "$db_file" "SELECT status, COUNT(*) FROM port_scan_state GROUP BY status;" 2>/dev/null | sed 's/^/ /'
    else
        echo "$db_file not found"
    fi

    log "netwatchinstall done at: $(date)"
}

# MENU
show_menu() {
    while true; do
        echo ""
        echo "netwatch installer"
        echo "-------------------"
        echo "1) Install"
        echo "2) Update"
        echo "3) Uninstall"
        echo "4) Status"
        echo "5) Exit"
        echo ""
        read -p "Select option (default: 5): " opt
        opt="${opt:-5}"
        case "$opt" in
            1) do_install; break ;;
            2) do_update; break ;;
            3) do_uninstall; break ;;
            4) do_status; break ;;
            5) exit 0 ;;
            *) echo "ERROR: Invalid option" ;;
        esac
    done
}

# ACTIONS
case "${1:-}" in
    --install) do_install ;;
    --update) do_update ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    *)
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac
