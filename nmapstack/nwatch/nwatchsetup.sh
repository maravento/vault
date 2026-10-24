#!/bin/bash
# maravento.com
#
################################################################################
#
# nwatch - LAN device inventory & watched ports dashboard
# FILE: nwatch/nwatchsetup.sh
#
# USAGE:
# sudo bash nwatchsetup.sh --install
# sudo bash nwatchsetup.sh --update
# sudo bash nwatchsetup.sh --uninstall
# sudo bash nwatchsetup.sh --status
#
# LOG: nwatchsetup.log, next to this script (rewritten on each run)
#      The daemons nwatchlan.sh / nwatchports.sh log to the shared
#      /var/log/nwatch.log, rotated daily via /etc/logrotate.d/nwatch
#      (deployed by --install, removed by --uninstall).
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# logging
script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
log_file="$script_dir/nwatchsetup.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then echo "$msg" >&2; else echo "$msg"; fi
}
touch "$log_file"
chmod 640 "$log_file"
chown root:root "$log_file"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# conflicting packages
check_conflicts() {
    local role="$1"; shift
    local found=()
    for dep_pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null | grep -q "ok installed"; then
            found+=("$dep_pkg")
        fi
    done
    if [ "${#found[@]}" -gt 0 ]; then
        for dep_pkg in "${found[@]}"; do
            log "WARNING: conflicting $role: $dep_pkg -alert"
        done
        log "ERROR: remove them with apt purge -abort"
        exit 1
    fi
}

# port in use
check_port() {
    local proto="$1" port="$2" role="$3"
    if [ -n "$(ss -lnH "-${proto,,}" "sport = :$port" 2>/dev/null)" ]; then
        log "ERROR: ${proto^^} port $port in use by another $role"
        log "ERROR: stop that service before installing -abort"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

web_dir="$script_dir/web"
tools_dir="$script_dir/tools"
nwatch_www="/var/www/nwatch"
nwatch_web="$nwatch_www/web"
nwatch_tools="$nwatch_www/tools"
nwatch_data="$nwatch_www/data"
# nwatch.env is read-only config (access-control CIDR etc.) and lives in
# /etc/nwatch, root-owned, so the web process can never write it. The
# mutable, web-writable ports_mode.conf stays in the data dir (still outside
# the DocumentRoot) -- /etc should hold root-writable config only, not a file
# the web user rewrites on every mode change.
nwatch_etc="/etc/nwatch"
nwatch_env="$nwatch_etc/nwatch.env"
db_file="$nwatch_data/nwatch.db"
ports_mode_file="$nwatch_data/ports_mode.conf"
vhost_port="3126"

# REPOSITORY STRUCTURE CHECK
# Check that the required repository files are present
check_repo() {
    local missing=0
    for dir in "$web_dir" "$tools_dir"; do
        if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            missing=1
            break
        fi
    done
    if [ "$missing" -eq 1 ]; then
        log "ERROR: repository files not found"
        log "ERROR: clone it from github.com/maravento/vault -abort"
        exit 1
    fi
}
check_repo

# dependencies
for dep in systemd apache2 libapache2-mod-php php-cli php-sqlite3 arp-scan sqlite3 nmap iproute2 logrotate cron procps coreutils findutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: '$dep' is not installed -abort"
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
        log "ERROR: no physical interface has global IPv4 -abort"
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
# nwatchlan.sh arp-scans every one of them each poll cycle.
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
            if ! [[ "$idx" =~ $UH_UINT ]] || [ "${#idx}" -gt 5 ] \
               || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#candidate_names[@]}" ]; then
                log "INFO: invalid selection '$idx' -retry"
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
# not the network address, and NET_CIDR (the scan scope, stored in
# nwatch.env) is supposed to be the latter.
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

# The web panel's IP allowlist (nwatchapi.php) is tied to a single
# management interface, kept separate from the (possibly multiple) scan
# interfaces so the panel is never accidentally exposed over a WAN NIC.
select_management_interface() {
    echo ""
    echo "Select management interface web panel will trust for access control"
    echo "This should be your LAN/admin interface -- never select a WAN interface here"
    print_candidate_interfaces
    echo ""
    while true; do
        read -rp "Select management interface number (default: 1): " idx
        idx="${idx:-1}"
        if ! [[ "$idx" =~ $UH_UINT ]] || [ "${#idx}" -gt 5 ] \
           || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#candidate_names[@]}" ]; then
            log "INFO: invalid selection -retry"
            continue
        fi
        mgmt_answer="${candidate_names[$((idx - 1))]}"
        break
    done
    local ip_with_prefix
    ip_with_prefix=$(ip -4 addr show dev "$mgmt_answer" scope global | sed -n 's/.*inet \([0-9.]\{1,\}\/[0-9]\{1,\}\).*/\1/p' | head -n1)
    if ! [[ "$ip_with_prefix" =~ $UH_CIDR ]]; then
        log "ERROR: no valid IPv4/CIDR on '$mgmt_answer' -abort"
        exit 1
    fi
    net_cidr_value=$(compute_network_cidr "$ip_with_prefix")
    detected_ip=$(ip -4 addr show dev "$mgmt_answer" scope global | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    echo "Management interface : $mgmt_answer"
    echo "Network : $net_cidr_value"
    echo "Server IP : $detected_ip"
}

# INITIALIZE DB SCHEMA
# Create the database tables and indexes
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

# ------------------------------------------------------------------------------
# INSTALL
# ------------------------------------------------------------------------------

# Install the project files and configuration
# CHECK ALREADY INSTALLED
# Reject installation when project files already exist
check_already_installed() {
    local installed=0
    local reasons="" reason

    if [ -f "$nwatch_env" ]; then
        installed=1
        reasons+="nwatch.env already exists\n"
    fi

    if [ -f "/etc/apache2/sites-available/nwatch.conf" ]; then
        installed=1
        reasons+="nwatch.conf already exists\n"
    fi

    if [ "$installed" -eq 1 ]; then
        echo ""
        while IFS= read -r reason; do
            [ -n "$reason" ] && log "WARNING: nwatch: $reason -alert"
        done < <(printf "%b" "$reasons")
        echo ""
        log "ERROR: nwatch: use --update for this installation -abort"
        exit 1
    fi
}

# CRON_D
# Add or replace one line in the project's single cron.d file
cron_d_set() {
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/nwatch"
    local cron_tmp

    cron_tmp=$(mktemp) || return 1
    if [ -f "$cron_file" ]; then
        grep -vF "$match" "$cron_file" > "$cron_tmp" || {
            [ "$?" -eq 1 ] || { rm -f "$cron_tmp"; return 1; }
        }
    fi
    if [ -n "$line" ]; then
        printf '%s\n' "$line" >> "$cron_tmp" || {
            rm -f "$cron_tmp"
            return 1
        }
    fi
    if [ -s "$cron_tmp" ]; then
        if ! install -m 644 -o root -g root "$cron_tmp" "$cron_file"; then
            rm -f "$cron_tmp"
            return 1
        fi
    else
        rm -f "$cron_file"
    fi
    rm -f "$cron_tmp"
}

# add one @reboot cron entry per daemon, so a failure in one never keeps
# the other from starting
add_reboot_cron() {
    cron_d_set "$nwatch_tools/nwatchlan.sh" "@reboot root $nwatch_tools/nwatchlan.sh --start" || return 1
    cron_d_set "$nwatch_tools/nwatchports.sh" "@reboot root $nwatch_tools/nwatchports.sh --start" || return 1
}

install_project_logrotate() {
    local rotate_file="/etc/logrotate.d/nwatch"
    local project_log="/var/log/nwatch.log"
    if [ ! -f "$project_log" ]; then
        touch "$project_log" || return 1
    fi
    chown root:root "$project_log" || return 1
    chmod 640 "$project_log" || return 1
    cat > "$rotate_file" <<EOF
$project_log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOF
    [ "$?" -eq 0 ] || return 1
    chown root:root "$rotate_file" || return 1
    chmod 644 "$rotate_file" || return 1
    log "INFO: updated $rotate_file"
}

do_install() {

    check_already_installed

    # dependency checks
    check_conflicts "web server" nginx lighttpd caddy

    if ! systemctl is-active --quiet apache2; then
        log "ERROR: apache2 is not running"
        log "ERROR: start it first: systemctl start apache2 -abort"
        exit 1
    fi

    check_port tcp "$vhost_port" "web interface"

    # The vhost needs mod_php (SetHandler application/x-httpd-php), not PHP-FPM.
    if ! apache2ctl -M 2>/dev/null | grep -qi 'php_module'; then
        log "ERROR: Apache mod_php is not loaded"
        log "ERROR: run: apt-get install -y libapache2-mod-php -abort"
        exit 1
    fi

    a2enmod -q headers

    select_scan_interfaces
    select_management_interface

    mkdir -p "$nwatch_web" "$nwatch_tools" "$nwatch_data" "$nwatch_etc"

    if ! { cp -f "$web_dir"/*.php "$web_dir"/*.html "$nwatch_web/" \
        && chmod -R 755 "$nwatch_web" \
        && chown -R www-data:www-data "$nwatch_web"; }; then
        log "ERROR: cannot deploy web files -abort"
        exit 1
    fi

    if ! install -m 644 -o root -g root "$tools_dir/nwatchenv.sh" "$nwatch_tools/nwatchenv.sh"; then
        log "ERROR: cannot deploy nwatchenv.sh -abort"
        exit 1
    fi

    if ! { cp -f "$tools_dir"/*.sh "$nwatch_tools/" \
        && chmod +x "$nwatch_tools"/*.sh \
        && chmod 644 "$nwatch_tools/nwatchenv.sh"; }; then
        log "ERROR: cannot deploy tools -abort"
        exit 1
    fi

    init_schema
    if ! chown -R www-data:www-data "$nwatch_data"; then
        log "ERROR: cannot set nwatch data owner and group -abort"
        exit 1
    fi
    if ! chmod 775 "$nwatch_data"; then
        log "ERROR: cannot set nwatch data permissions -abort"
        exit 1
    fi
    # nwatch.db: root:www-data 640 -- daemons (root) read/write, web reads only.
    if ! chown root:www-data "$db_file"; then
        log "ERROR: cannot set nwatch.db owner and group -abort"
        exit 1
    fi
    if ! chmod 640 "$db_file"; then
        log "ERROR: cannot set nwatch.db permissions -abort"
        exit 1
    fi

    # Config dir /etc/nwatch: same model as proxymon's /etc/proxymon --
    # root:www-data 750, holds only read-only config (nwatch.env). The
    # web process must never be the writer of anything under /etc.
    if ! chown root:www-data "$nwatch_etc"; then
        log "ERROR: cannot set nwatch config owner and group -abort"
        exit 1
    fi
    if ! chmod 750 "$nwatch_etc"; then
        log "ERROR: cannot set nwatch config permissions -abort"
        exit 1
    fi

    # ports_mode.conf: mutable, web-writable state (active watch mode +
    # target IP) -- stays in the data dir, www-data:www-data, same as any
    # other web-writable file in this project (never under /etc).
    cat > "$ports_mode_file" <<'PMODE'
PORTS_MODE="server"
PORTS_TARGET_IP=""
PMODE
    if ! chown www-data:www-data "$ports_mode_file"; then
        log "ERROR: cannot set ports_mode.conf owner and group -abort"
        exit 1
    fi
    if ! chmod 664 "$ports_mode_file"; then
        log "ERROR: cannot set ports_mode.conf permissions -abort"
        exit 1
    fi

    # apache vhost
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    sed -i "/^Listen .*:${vhost_port}\$/d" /etc/apache2/ports.conf
    printf 'Listen 127.0.0.1:%s\n' "$vhost_port" | tee -a /etc/apache2/ports.conf
    cp -f "$web_dir/nwatch.conf" /etc/apache2/sites-available/nwatch.conf
    a2ensite -q nwatch.conf

    systemctl daemon-reload
    systemctl restart apache2 || {
        log "ERROR: cannot restart apache2 -abort"
        exit 1
    }

    # save install config. The four tuning keys are written here with their
    # defaults, not left for the daemons to create on first start: a .env is
    # written by its installer or by the administrator, never by a script in
    # normal operation.
    #
    # Values are bare, without quotes: that is the only form the shared
    # configuration reader accepts, and a bare value never needs escaping.
    cat > "$nwatch_env" <<ENV
# =============================================================================
# Nwatch
# /etc/nwatch/nwatch.env
# =============================================================================

# Network
LAN_IFACES=$ifaces_answer
MGMT_IFACE=$mgmt_answer
NET_CIDR=$net_cidr_value
SERVER_IP=$detected_ip

# LAN monitor
LAN_POLL_INTERVAL=60
LAN_OFFLINE_GRACE=3

# Port monitor
PORT_POLL_INTERVAL=30
PURGE_CLOSED_AFTER_HOURS=6

# Database
# Changing these defaults is not recommended
NWATCH_DB_TIMEOUT_MS=5000
# =============================================================================
ENV
    chown root:www-data "$nwatch_env"
    chmod 640 "$nwatch_env"

    install_project_logrotate || { log "ERROR: cannot configure nwatch log rotation -abort"; exit 1; }

    # start daemons -- they are nwatch's core, not an optional extra, so
    # they auto-start right after install.
    if ! "$nwatch_tools/nwatchlan.sh" --start; then
        log "ERROR: cannot start nwatchlan.sh -abort"
        exit 1
    fi
    if ! "$nwatch_tools/nwatchports.sh" --start; then
        log "ERROR: cannot start nwatchports.sh -abort"
        exit 1
    fi
    if ! add_reboot_cron; then
        log "ERROR: cannot write /etc/cron.d/nwatch -abort"
        exit 1
    fi

    echo ""
    echo "LAN tab : http://localhost:${vhost_port}/?tab=lan"
    echo "Ports tab : http://localhost:${vhost_port}/?tab=ports"
    echo "Env file : $nwatch_env"
    echo "Database : $db_file"
    echo "Tools dir : $nwatch_tools"
    echo ""
}

# ------------------------------------------------------------------------------
# UPDATE
# ------------------------------------------------------------------------------

# Refresh the installed application files
do_update() {
    local update_failed=0
    local -a update_failures=()

    if [ ! -f "$nwatch_env" ]; then
        log "ERROR: nwatch is not installed -abort"
        exit 1
    fi

    if [ -f "$db_file" ]; then
        if ! chown root:www-data "$db_file"; then
            log "WARNING: cannot set owner and group on $(basename "$db_file") -alert"
            update_failed=1
            update_failures+=("cannot set owner and group on $(basename "$db_file")")
        fi
        if ! chmod 640 "$db_file"; then
            log "WARNING: cannot set permissions on $(basename "$db_file") -alert"
            update_failed=1
            update_failures+=("cannot set permissions on $(basename "$db_file")")
        fi
    fi

    "$nwatch_tools/nwatchlan.sh" --stop 2>/dev/null || true
    "$nwatch_tools/nwatchports.sh" --stop 2>/dev/null || true

    # web files (application code only -- nwatch.conf is never overwritten,
    # it may contain manual edits after install)
    for src in "$web_dir"/*.php "$web_dir"/*.html; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        if cp -f "$src" "$nwatch_web/$fname" \
            && chown www-data:www-data "$nwatch_web/$fname"; then
            log "INFO: updated $fname"
        else
            log "WARNING: cannot update $fname -alert"
            update_failed=1
            update_failures+=("cannot update $fname")
        fi
    done
    if ! chown -R www-data:www-data "$nwatch_web"; then
        log "WARNING: cannot set nwatch web owner and group -alert"
        update_failed=1
        update_failures+=("cannot set nwatch web owner and group")
    fi

    if ! install -m 644 -o root -g root "$tools_dir/nwatchenv.sh" "$nwatch_tools/nwatchenv.sh"; then
        log "ERROR: cannot deploy nwatchenv.sh -abort"
        exit 1
    fi
    log "INFO: updated nwatchenv.sh"

    for f in "$tools_dir"/*.sh; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = nwatchenv.sh ] && continue
        fname="$(basename "$f")"
        if cp -f "$f" "$nwatch_tools/$fname" \
            && chmod +x "$nwatch_tools/$fname"; then
            log "INFO: updated $fname"
        else
            log "WARNING: cannot update $fname -alert"
            update_failed=1
            update_failures+=("cannot update $fname")
        fi
    done

    if ! install_project_logrotate; then
        log "WARNING: cannot configure nwatch log rotation -alert"
        update_failed=1
        update_failures+=("cannot configure nwatch log rotation")
    fi

    if ! "$nwatch_tools/nwatchlan.sh" --start; then
        log "WARNING: cannot start nwatchlan.sh -alert"
        update_failed=1
        update_failures+=("cannot start nwatchlan.sh")
    fi
    if ! "$nwatch_tools/nwatchports.sh" --start; then
        log "WARNING: cannot start nwatchports.sh -alert"
        update_failed=1
        update_failures+=("cannot start nwatchports.sh")
    fi
    if ! add_reboot_cron; then
        log "WARNING: cannot write /etc/cron.d/nwatch -alert"
        update_failed=1
        update_failures+=("cannot write /etc/cron.d/nwatch")
    fi

    if ! systemctl restart apache2; then
        log "WARNING: cannot restart apache2 -alert"
        update_failed=1
        update_failures+=("cannot restart apache2")
    fi

    if [ "$update_failed" -ne 0 ]; then
        log "ERROR: ${#update_failures[@]} update step(s) failed -abort"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# UNINSTALL
# ------------------------------------------------------------------------------

# Remove the installed project files and configuration
do_uninstall() {
    # Confirm before the rm -rf below (interactive runs only)
    if [ -t 0 ]; then
        local confirm
        read -r -p "This will permanently remove NWatch and its data (LAN/port history). Continue? (y/N): " confirm
        case "$confirm" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *) echo "Aborted."; exit 1 ;;
        esac
    fi

    "$nwatch_tools/nwatchlan.sh" --stop 2>/dev/null || true
    "$nwatch_tools/nwatchports.sh" --stop 2>/dev/null || true

    a2dissite -q nwatch.conf &>/dev/null
    sed -i "/^Listen .*:${vhost_port}\$/d" /etc/apache2/ports.conf
    rm -f /etc/apache2/sites-available/nwatch.conf

    rm -f /etc/logrotate.d/nwatch /etc/logrotate.d/nwatch.bak && {
        log "INFO: Removed /etc/logrotate.d/nwatch"
        log "INFO: Removed /etc/logrotate.d/nwatch.bak"
    }

    rm -rf "$nwatch_www"
    rm -rf "$nwatch_etc"

    rm -f /etc/cron.d/nwatch

    systemctl daemon-reload
    systemctl restart apache2 || {
        log "ERROR: cannot restart apache2 -abort"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# STATUS
# ------------------------------------------------------------------------------

# PID CHECK
# Check whether the recorded process belongs to this daemon
daemon_alive() {
    local pid="$1" self="$2" args=() i
    [ -n "$pid" ] || return 1
    mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || return 1
    case "$(basename -- "${args[0]:-}")" in
        "$self") i=0 ;;
        bash|sh) i=1 ;;
        *) return 1 ;;
    esac
    [ "$(basename -- "${args[i]:-}")" = "$self" ] || return 1
    [ "${args[i+1]:-}" = --start ]
}

# DO STATUS
# Report the current daemon or installation state
do_status() {

    echo "=== nwatch Daemons ==="
    for name in nwatchlan nwatchports; do
        pidfile="/run/${name}.pid"
        if [ -f "$pidfile" ] && daemon_alive "$(cat "$pidfile" 2>/dev/null)" "${name}.sh"; then
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
    if [ -f "$nwatch_env" ]; then
        echo "Scan interfaces : $(grep '^LAN_IFACES=' "$nwatch_env" | cut -d= -f2- | tr -d '"')"
        echo "Management iface : $(grep '^MGMT_IFACE=' "$nwatch_env" | cut -d= -f2- | tr -d '"')"
    else
        echo "$nwatch_env not found"
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
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# Display the available actions and read the selected option
show_menu() {
    while true; do
        echo ""
        echo "nwatch installer"
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
            2) do_update || exit 1; break ;;
            3) do_uninstall; break ;;
            4) do_status; break ;;
            5)
                log "nwatchsetup done at: $(date '+%Y-%m-%d %H:%M:%S')"
                exit 0
                ;;
            *) log "INFO: invalid option -retry" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Dispatch the requested command to its action
log "nwatchsetup start..."
case "${1:-}" in
    --install) do_install ;;
    --update) do_update || exit 1 ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    *)
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "nwatchsetup done at: $(date '+%Y-%m-%d %H:%M:%S')"
