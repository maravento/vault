#!/bin/bash
# maravento.com
#
################################################################################
#
# netwatch - LAN device inventory & watched ports dashboard
# https://github.com/maravento/vault
#
# Log file:
# /var/log/netwatch.log -- shared by all three netwatch scripts (this
# installer plus netwatchlan.sh / netwatchports.sh). Rotated weekly via
# /etc/logrotate.d/netwatch (deployed by --install, removed by --uninstall).
#
################################################################################

set -uo pipefail

### PATHS
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

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

# Enforce perms unconditionally, same as netwatchlan.sh/netwatchports.sh do
# in their own start() -- this script is always the first of the three to
# run (--install), so without this the log would be created with whatever
# the umask dictates (often 644, world-readable) until a daemon later fixes
# it, instead of the documented root:root 640 from the very first write.
touch "$log_file"
chmod 640 "$log_file"
chown root:root "$log_file"

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

WEB_DIR="$SCRIPT_DIR/web"
TOOLS_DIR="$SCRIPT_DIR/tools"
NETWATCH_WWW="/var/www/netwatch"
NETWATCH_WEB="$NETWATCH_WWW/web"
NETWATCH_TOOLS="$NETWATCH_WWW/tools"
NETWATCH_DATA="$NETWATCH_WWW/data"
# netwatch.env is read-only config (access-control CIDR etc.) and lives in
# /etc/netwatch, root-owned, so the web process can never write it. The
# mutable, web-writable ports_mode.conf stays in the data dir (still outside
# the DocumentRoot) -- /etc should hold root-writable config only, not a file
# the web user rewrites on every mode change.
NETWATCH_ETC="/etc/netwatch"
NETWATCH_ENV="$NETWATCH_ETC/netwatch.env"
DB_FILE="$NETWATCH_DATA/netwatch.db"
PORTS_MODE_FILE="$NETWATCH_DATA/ports_mode.conf"
VHOST_PORT="3126"

### REPOSITORY STRUCTURE CHECK
check_repo() {
    local missing=0
    for dir in "$WEB_DIR" "$TOOLS_DIR"; do
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

# LOCAL USER detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

### INTERFACE / NETWORK SELECTION
# Virtual/loopback interfaces are never useful arp-scan targets and are
# hidden from every selector below (both the scan-interfaces prompt and the
# management-interface prompt).
VIRTUAL_IFACE_PATTERN='^(lo|docker.*|br-.*|veth.*|virbr.*|tun.*|tap.*|wg.*)$'

CAND_NAMES=()
CAND_ADDRS=()
list_candidate_interfaces() {
    CAND_NAMES=()
    CAND_ADDRS=()
    local iface addr
    while read -r iface addr; do
        [ -z "$iface" ] && continue
        [[ "$iface" =~ $VIRTUAL_IFACE_PATTERN ]] && continue
        CAND_NAMES+=("$iface")
        CAND_ADDRS+=("$addr")
    done < <(ip -4 addr show scope global | awk '/inet /{print $NF, $2}')
    if [ "${#CAND_NAMES[@]}" -eq 0 ]; then
        echo "ERROR: No physical network interfaces with a global IPv4 address found (virtual/loopback interfaces are excluded)."
        exit 1
    fi
}

print_candidate_interfaces() {
    local i
    for i in "${!CAND_NAMES[@]}"; do
        printf " %2d) %-12s %s\n" "$((i + 1))" "${CAND_NAMES[$i]}" "${CAND_ADDRS[$i]}"
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
    while true; do
        read -rp "Select interface(s) to scan -- comma-separated numbers (e.g. 1,2): " sel
        sel="${sel//[[:space:]]/}"
        if [ -z "$sel" ]; then
            echo "ERROR: No interfaces specified. Try again."
            continue
        fi
        local idxs chosen idx ok
        IFS=',' read -ra idxs <<< "$sel"
        chosen=()
        ok=1
        for idx in "${idxs[@]}"; do
            if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#CAND_NAMES[@]}" ]; then
                echo "ERROR: Invalid selection '$idx'. Try again."
                ok=0
                break
            fi
            chosen+=("${CAND_NAMES[$((idx - 1))]}")
        done
        [ "$ok" -eq 1 ] || continue
        LAN_IFACES=$(printf '%s\n' "${chosen[@]}" | awk '!seen[$0]++' | paste -sd, -)
        break
    done
    echo "Scanning interfaces: $LAN_IFACES"
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
        read -rp "Select management interface number (e.g. 1): " idx
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#CAND_NAMES[@]}" ]; then
            echo "ERROR: Invalid selection. Try again."
            continue
        fi
        MGMT_IFACE="${CAND_NAMES[$((idx - 1))]}"
        break
    done
    NET_CIDR=$(ip -4 addr show dev "$MGMT_IFACE" scope global | sed -n 's/.*inet \([0-9.]\{1,\}\/[0-9]\{1,\}\).*/\1/p' | head -n1)
    SERVER_IP=$(ip -4 addr show dev "$MGMT_IFACE" scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    echo "Management interface : $MGMT_IFACE"
    echo "Network : $NET_CIDR"
    echo "Server IP : $SERVER_IP"
}

### INITIALIZE DB SCHEMA
init_schema() {
    sqlite3 "$DB_FILE" >/dev/null <<'SQL'
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

### INSTALL
### CHECK ALREADY INSTALLED
check_already_installed() {
    local installed=0
    local reasons=""

    if [ -f "$NETWATCH_ENV" ]; then
        installed=1
        reasons+=" - netwatch.env already exists: $NETWATCH_ENV\n"
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

do_install() {
    log "netwatchinstall start (install)..."

    check_already_installed

    if ! local_user=$(detect_local_user); then
        log "ERROR: No valid local user found. Create one with sudo access."
        exit 1
    fi
    log "Using local user: $local_user"

    # dependency checks
    if systemctl is-active --quiet nginx; then
        log "ERROR: nginx is running. Disable it first: systemctl stop nginx"
        exit 1
    fi

    for cmd in apache2 a2ensite a2dissite a2enmod php; do
        if ! command -v "$cmd" &>/dev/null; then
            log "ERROR: $cmd not found. Run first:"
            log "apt-get install -y apache2 libapache2-mod-php"
            exit 1
        fi
    done

    if ! systemctl is-active --quiet apache2; then
        log "ERROR: apache2 is not running. Start it first: systemctl start apache2"
        exit 1
    fi

    # The vhost relies on mod_php (SetHandler application/x-httpd-php) to
    # execute .php files, not PHP-FPM -- the `php` CLI check above only
    # confirms the interpreter exists, not that Apache can hand requests to
    # it. Without this module loaded, install would "succeed" but every
    # .php file would be served as plain text/downloaded instead of run.
    if ! apache2ctl -M 2>/dev/null | grep -qi 'php_module'; then
        log "ERROR: Apache mod_php is not loaded. Run first:"
        log "apt-get install -y libapache2-mod-php"
        log "a2enmod php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)"
        log "systemctl restart apache2"
        exit 1
    fi

    for pkg in arp-scan sqlite3 nmap ss; do
        if ! command -v "$pkg" &>/dev/null; then
            log "ERROR: $pkg not found. Run first: apt-get install -y arp-scan sqlite3 php-sqlite3 nmap iproute2"
            exit 1
        fi
    done

    if ! php -m 2>/dev/null | grep -qi '^sqlite3$'; then
        log "ERROR: PHP sqlite3 extension not found. Run first: apt-get install -y php-sqlite3"
        exit 1
    fi

    if ! command -v logrotate &>/dev/null; then
        log "ERROR: logrotate not found. Install it first: apt-get install -y logrotate"
        exit 1
    fi

    a2enmod -q headers

    select_scan_interfaces
    select_management_interface

    mkdir -p "$NETWATCH_WEB" "$NETWATCH_TOOLS" "$NETWATCH_DATA" "$NETWATCH_ETC"

    cp -f "$WEB_DIR"/*.php "$WEB_DIR"/*.html "$NETWATCH_WEB/"
    chmod -R 755 "$NETWATCH_WEB"
    chown -R www-data:www-data "$NETWATCH_WEB"

    cp -f "$TOOLS_DIR"/*.sh "$NETWATCH_TOOLS/"
    chmod +x "$NETWATCH_TOOLS"/*.sh

    init_schema
    chown -R www-data:www-data "$NETWATCH_DATA"
    chmod 664 "$DB_FILE"
    chmod 775 "$NETWATCH_DATA"

    # Config dir /etc/netwatch: same model as proxymon's /etc/proxymon --
    # root:www-data 750, holds only read-only config (netwatch.env). The
    # web process must never be the writer of anything under /etc.
    chown root:www-data "$NETWATCH_ETC"
    chmod 750 "$NETWATCH_ETC"

    # ports_mode.conf: mutable, web-writable state (active watch mode +
    # target IP) -- stays in the data dir, www-data:www-data, same as any
    # other web-writable file in this project (never under /etc).
    cat > "$PORTS_MODE_FILE" <<'PMODE'
PORTS_MODE="server"
PORTS_TARGET_IP=""
PMODE
    chown www-data:www-data "$PORTS_MODE_FILE"
    chmod 664 "$PORTS_MODE_FILE"

    # apache vhost
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    sed -i "/^Listen .*:${VHOST_PORT}\$/d" /etc/apache2/ports.conf
    echo "Listen 0.0.0.0:${VHOST_PORT}" | tee -a /etc/apache2/ports.conf
    cp -f "$WEB_DIR/netwatch.conf" /etc/apache2/sites-available/netwatch.conf
    a2ensite -q netwatch.conf

    systemctl daemon-reload
    systemctl restart apache2

    # narrow Listen down to LAN IP + loopback now that SERVER_IP is known
    if [ -n "$SERVER_IP" ]; then
        sed -i "s|^Listen 0.0.0.0:${VHOST_PORT}\$|Listen ${SERVER_IP}:${VHOST_PORT}\nListen 127.0.0.1:${VHOST_PORT}|" /etc/apache2/ports.conf
        systemctl restart apache2
    else
        log "WARNING: Could not detect server IP. Web panel keeps listening on all interfaces (0.0.0.0:${VHOST_PORT})."
    fi

    # save install config; poll intervals are left unset here and get their
    # defaults/first-run prompt from the daemons themselves (see LAN_POLL_INTERVAL,
    # LAN_OFFLINE_GRACE, PORT_POLL_INTERVAL, PORT_CONNECT_TIMEOUT).
    cat > "$NETWATCH_ENV" <<ENV
LOCAL_USER="$local_user"
LAN_IFACES="$LAN_IFACES"
MGMT_IFACE="$MGMT_IFACE"
NET_CIDR="$NET_CIDR"
SERVER_IP="$SERVER_IP"
ENV
    chown root:www-data "$NETWATCH_ENV"
    chmod 640 "$NETWATCH_ENV"

    # logrotate: the shared log has no size cap otherwise (installer +
    # both daemons write to it indefinitely).
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
    "$NETWATCH_TOOLS/netwatchlan.sh" start
    "$NETWATCH_TOOLS/netwatchports.sh" start

    echo ""
    echo "LAN tab : http://localhost:${VHOST_PORT}/?tab=lan"
    echo "Ports tab : http://localhost:${VHOST_PORT}/?tab=ports"
    echo "Env file : $NETWATCH_ENV"
    echo "Database : $DB_FILE"
    echo "Tools dir : $NETWATCH_TOOLS"
    echo ""

    log "netwatchinstall done at: $(date)"
}

### UPDATE
do_update() {
    log "netwatchinstall start (update)..."

    # One-time migration: installs from before netwatch.env moved to
    # /etc/netwatch (it used to live at $NETWATCH_WWW/netwatch.env) would
    # otherwise hit a dead end here -- --update thinks it's not installed
    # while --install thinks it already is (the vhost is still there).
    # Detect and migrate automatically instead of forcing a manual fix.
    local legacy_env="$NETWATCH_WWW/netwatch.env"
    if [ ! -f "$NETWATCH_ENV" ] && [ -f "$legacy_env" ]; then
        log "Migrating netwatch.env from $legacy_env to $NETWATCH_ENV"
        mkdir -p "$NETWATCH_ETC"
        chown root:www-data "$NETWATCH_ETC"
        chmod 750 "$NETWATCH_ETC"
        mv -f "$legacy_env" "$NETWATCH_ENV"
        chown root:www-data "$NETWATCH_ENV"
        chmod 640 "$NETWATCH_ENV"
    fi

    if [ ! -f "$NETWATCH_ENV" ]; then
        log "ERROR: netwatch is not installed."
        exit 1
    fi

    # One-time migration: installs from before UDP support had
    # UNIQUE(source, host, port) on port_scan_state, which would collide
    # tcp/80 and udp/80 into a single row. Recreate the table with proto
    # added to the constraint, preserving existing data.
    if [ -f "$DB_FILE" ]; then
        local current_schema
        current_schema=$(sqlite3 "$DB_FILE" "SELECT sql FROM sqlite_master WHERE type='table' AND name='port_scan_state';" 2>/dev/null)
        if [ -n "$current_schema" ] && ! printf '%s' "$current_schema" | grep -q "UNIQUE(source, host, port, proto)"; then
            log "Migrating port_scan_state UNIQUE constraint to include proto"
            sqlite3 "$DB_FILE" >/dev/null <<'SQL'
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
    fi

    "$NETWATCH_TOOLS/netwatchlan.sh" stop 2>/dev/null || true
    "$NETWATCH_TOOLS/netwatchports.sh" stop 2>/dev/null || true

    # web files (application code only -- netwatch.conf is never overwritten,
    # it may contain manual edits after install)
    mkdir -p "$NETWATCH_WWW/backups"
    for src in "$WEB_DIR"/*.php "$WEB_DIR"/*.html; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        dst="$NETWATCH_WEB/$fname"
        [ -f "$dst" ] && cp -f "$dst" "$NETWATCH_WWW/backups/$fname.bak" &>/dev/null
        cp -f "$src" "$dst"
        log "Updated: $fname"
    done
    chown -R www-data:www-data "$NETWATCH_WEB"

    for f in "$TOOLS_DIR"/*.sh; do
        [ -f "$f" ] || continue
        fname="$(basename "$f")"
        [ -f "$NETWATCH_TOOLS/$fname" ] && cp -f "$NETWATCH_TOOLS/$fname" "$NETWATCH_WWW/backups/$fname.bak" &>/dev/null
        cp -f "$f" "$NETWATCH_TOOLS/$fname"
        chmod +x "$NETWATCH_TOOLS/$fname"
        log "Updated: $fname"
    done

    "$NETWATCH_TOOLS/netwatchlan.sh" start
    "$NETWATCH_TOOLS/netwatchports.sh" start

    systemctl restart apache2

    log "netwatchinstall done at: $(date)"
}

### UNINSTALL
do_uninstall() {
    log "netwatchinstall start (uninstall)..."

    "$NETWATCH_TOOLS/netwatchlan.sh" stop 2>/dev/null || true
    "$NETWATCH_TOOLS/netwatchports.sh" stop 2>/dev/null || true

    a2dissite -q netwatch.conf &>/dev/null
    sed -i "/^Listen .*:${VHOST_PORT}\$/d" /etc/apache2/ports.conf
    rm -f /etc/apache2/sites-available/netwatch.conf

    rm -rf "$NETWATCH_WWW"
    rm -rf "$NETWATCH_ETC"

    rm -f /etc/logrotate.d/netwatch /etc/logrotate.d/netwatch.bak

    # cron entries -- anchored to the exact lines the daemons add (full
    # command/path), not bare substrings, so unrelated user cron jobs
    # aren't swept away too.
    crontab -l 2>/dev/null > "/root/crontab-uninstall-$(date +%Y%m%d%H%M%S).bak" || true
    cron_tmp=$(mktemp)
    crontab -l 2>/dev/null > "$cron_tmp" || true
    grep -vF "$NETWATCH_TOOLS/netwatchlan.sh start" "$cron_tmp" > "${cron_tmp}.next" || true
    mv "${cron_tmp}.next" "$cron_tmp"
    grep -vF "$NETWATCH_TOOLS/netwatchports.sh start" "$cron_tmp" > "${cron_tmp}.next" || true
    mv "${cron_tmp}.next" "$cron_tmp"
    crontab "$cron_tmp"
    rm -f "$cron_tmp"

    systemctl daemon-reload
    systemctl restart apache2

    log "netwatchinstall done at: $(date)"
}

### STATUS
do_status() {
    log "netwatchinstall start (status)..."

    echo "=== netwatch Daemons ==="
    for name in netwatchlan netwatchports; do
        pidfile="/var/run/${name}.pid"
        if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
            echo "$name: RUNNING (PID $(cat "$pidfile"))"
        else
            echo "$name: STOPPED"
        fi
    done

    echo ""
    echo "=== Apache Port ==="
    if ss -tlnp 2>/dev/null | grep -qE ":${VHOST_PORT}[[:space:]]"; then
        echo ":${VHOST_PORT} OPEN"
    else
        echo ":${VHOST_PORT} CLOSED"
    fi

    echo ""
    echo "=== Log ==="
    echo "$log_file (last 10):"
    [ -f "$log_file" ] && tail -10 "$log_file" | sed 's/^/ /' || echo " (not found)"

    echo ""
    echo "=== Config ==="
    if [ -f "$NETWATCH_ENV" ]; then
        echo "Scan interfaces : $(grep '^LAN_IFACES=' "$NETWATCH_ENV" | cut -d= -f2- | tr -d '"')"
        echo "Management iface : $(grep '^MGMT_IFACE=' "$NETWATCH_ENV" | cut -d= -f2- | tr -d '"')"
    else
        echo "$NETWATCH_ENV not found"
    fi
    if [ -f "$PORTS_MODE_FILE" ]; then
        echo "Ports mode : $(grep '^PORTS_MODE=' "$PORTS_MODE_FILE" | cut -d= -f2- | tr -d '"')"
        echo "Ports target : $(grep '^PORTS_TARGET_IP=' "$PORTS_MODE_FILE" | cut -d= -f2- | tr -d '"')"
    fi

    echo ""
    echo "=== Database ==="
    if [ -f "$DB_FILE" ]; then
        echo "Devices:"
        sqlite3 "$DB_FILE" "SELECT status, COUNT(*) FROM devices GROUP BY status;" 2>/dev/null | sed 's/^/ /'
        echo "Ports (active mode):"
        sqlite3 "$DB_FILE" "SELECT status, COUNT(*) FROM port_scan_state GROUP BY status;" 2>/dev/null | sed 's/^/ /'
    else
        echo "$DB_FILE not found"
    fi

    log "netwatchinstall done at: $(date)"
}

### MENU
show_menu() {
    echo ""
    echo "netwatch installer"
    echo "-------------------"
    echo "1) Install"
    echo "2) Update"
    echo "3) Uninstall"
    echo "4) Status"
    echo "5) Exit"
    echo ""
    read -p "Select option: " opt
    case "$opt" in
        1) do_install ;;
        2) do_update ;;
        3) do_uninstall ;;
        4) do_status ;;
        5) exit 0 ;;
        *) echo "Invalid option"; show_menu ;;
    esac
}

### ARGUMENT HANDLING
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
