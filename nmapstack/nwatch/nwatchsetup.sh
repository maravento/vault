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
info() { log "INFO: $*"; }
warn() { log "WARNING: $*"; }
err()  { log "ERROR: $*"; }
touch "$log_file"
chmod 640 "$log_file"
chown root:root "$log_file"

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
for dep in systemd apache2 libapache2-mod-php php-cli php-sqlite3 arp-scan sqlite3 nmap iproute2 logrotate cron procps coreutils findutils util-linux python3 zip; do
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
# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# UPDATE CHECKS
update_error() {
    if declare -F err >/dev/null; then
        err "$* -abort"
    else
        log "ERROR: $* -abort"
    fi
    exit 1
}

update_reset() {
    update_cron_file="$1"
    update_files=()
    update_jobs=()
    update_services=()
    update_stopped_services=()
    update_daemons=()
    update_copying=0
    update_cron_paused=0
    update_cron_existed=0
    update_cron_already_paused=0
}

update_file() {
    update_files+=("$1" "$2" "$3" "$4")
    case "$2" in *.sh|*.py|*.pl) update_jobs+=("$2") ;; esac
}

update_target() {
    update_files+=("" "$1" "${2:-644}" "${3:-root:root}")
}

update_preflight() {
    command -v python3 >/dev/null 2>&1 || update_error "python3 is required for update checks"
    local check_message
    if check_message=$(python3 - "${update_files[@]}" <<'UPDATE_PY'
import array, errno, fcntl, os, stat, sys, tempfile
items = [sys.argv[i:i + 4] for i in range(1, len(sys.argv), 4)]
space, probes = {}, set()
def fail(message):
    print(message)
    raise SystemExit(1)
def flags(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
        try:
            value = array.array('L', [0])
            try:
                fcntl.ioctl(fd, 0x80086601, value, True)
            except OSError as exc:
                if exc.errno not in (errno.ENOTTY, errno.EOPNOTSUPP, errno.EINVAL):
                    raise
            else:
                if value[0] & 0x30:
                    protection = []
                    if value[0] & 0x10:
                        protection.append('immutable')
                    if value[0] & 0x20:
                        protection.append('append-only')
                    fail(os.path.basename(path) + ' is ' + ' and '.join(protection))
        finally:
            os.close(fd)
    except OSError as exc:
        fail(exc.strerror.lower() + ': ' + os.path.basename(path))
for source, target, mode, owner in items:
    if source:
        try:
            st = os.lstat(source)
            if not stat.S_ISREG(st.st_mode):
                fail('source is not a file: ' + os.path.basename(source))
            with open(source, 'rb') as stream:
                stream.read(1)
        except OSError as exc:
            fail('cannot read source: ' + os.path.basename(source))
for source, target, mode, owner in items:
    target = os.path.abspath(target)
    directory = mode.startswith('d')
    try:
        parent = target if directory else os.path.dirname(target)
        if os.path.lexists(target):
            st = os.lstat(target)
            if (directory and not stat.S_ISDIR(st.st_mode)) or (not directory and not stat.S_ISREG(st.st_mode)):
                fail(('dst is not a folder: ' if directory else 'dst is not a file: ') + os.path.basename(target))
            flags(target)
            if not directory:
                fd = os.open(target, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                finally:
                    os.close(fd)
        while not os.path.exists(parent):
            if os.path.lexists(parent):
                fail('folder is a symbolic link: ' + parent)
            parent = os.path.dirname(parent)
        if not os.path.isdir(parent):
            fail('not a folder: ' + parent)
        current = parent
        while current != '/':
            if os.path.islink(current):
                fail('folder is a symbolic link: ' + current)
            flags(current)
            current = os.path.dirname(current)
        fs = os.statvfs(parent)
        if fs.f_flag & os.ST_RDONLY:
            fail('filesystem is read-only: ' + parent)
        if parent not in probes:
            fd, probe = tempfile.mkstemp(prefix='update-check-', dir=parent)
            try:
                os.write(fd, b'update check\n')
                os.fsync(fd)
            finally:
                os.close(fd)
                os.unlink(probe)
            probes.add(parent)
        device = os.stat(parent).st_dev
        required = os.stat(source).st_size if source else 4096
        needed, available, label = space.get(device, (0, fs.f_bavail * fs.f_frsize, parent))
        space[device] = (needed + required + 4096, available, label)
        if fs.f_favail == 0:
            fail('no free inodes for dst: ' + os.path.basename(target))
    except OSError as exc:
        fail('cannot write dst: ' + os.path.basename(target))
for needed, available, label in space.values():
    if available < needed:
        fail('not enough space to update: ' + label)
UPDATE_PY
    ); then
        :
    else
        update_error "$check_message"
    fi
}

update_backup() {
    [ -f "$1" ] && [ -r "$1" ] || update_error "backup script not readable: $(basename "$1")"
    bash "$1" || update_error "backup failed: $(basename "$1")"
}

update_begin() {
    export UPDATE_CRON_OWNER="$$"
    trap 'update_cleanup "$?"' EXIT
    local disabled="${update_cron_file}.update-disabled"
    [ ! -L "${update_cron_file}.lock" ] || update_error "invalid cron lock: $update_cron_file"
    (umask 077; : >> "${update_cron_file}.lock") || update_error "cannot open cron lock: $update_cron_file"
    exec 203>"${update_cron_file}.lock" || update_error "cannot open cron lock: $update_cron_file"
    flock -n 203 || update_error "cron file is being changed: $(basename "$update_cron_file")"
    if [ -e "$disabled" ] || [ -L "$disabled" ]; then
        [ -f "$disabled" ] && [ ! -L "$disabled" ] || update_error "invalid paused cron: $(basename "$disabled")"
        [ ! -e "$update_cron_file" ] || update_error "both active and paused cron exist: $(basename "$update_cron_file")"
        update_cron_already_paused=1
        update_cron_paused=1
    elif [ -e "$update_cron_file" ]; then
        mv -T -- "$update_cron_file" "$disabled" || update_error "cannot pause cron: $update_cron_file"
        update_cron_existed=1
        update_cron_paused=1
    else
        (umask 077; set -C; : > "$disabled") || update_error "cannot pause cron: $update_cron_file"
        update_cron_paused=1
    fi
    exec 203>&-
}

update_pids() {
    python3 - "$1" <<'UPDATE_PIDS'
import os, sys
wanted = os.path.realpath(sys.argv[1])
for entry in os.scandir('/proc'):
    if not entry.name.isdigit() or int(entry.name) == os.getpid():
        continue
    try:
        with open(entry.path + '/cmdline', 'rb') as stream:
            args = [os.fsdecode(value) for value in stream.read().split(b'\0') if value]
        if args and any(os.path.realpath(value) == wanted for value in args if value.startswith('/')):
            print(entry.name)
    except (OSError, ValueError):
        continue
UPDATE_PIDS
}

update_wait() {
    local script="$1" pids attempt
    for attempt in {1..30}; do
        pids=$(update_pids "$script") || update_error "cannot inspect processes: $(basename "$script")"
        [ -z "$pids" ] && return 0
        sleep 1
    done
    update_error "process still running: $(basename "$script")"
}

update_stop_daemon() {
    local script="$1" pids
    pids=$(update_pids "$script") || update_error "cannot inspect processes: $script"
    if [ -n "$pids" ]; then
        update_daemons+=("$script")
        bash "$script" --stop || update_error "cannot stop daemon: $script"
        update_wait "$script"
    fi
}

update_stop_service() {
    local unit="$1" state load_state
    load_state=$(systemctl show -p LoadState --value "$unit") || update_error "cannot inspect service: $unit"
    [ "$load_state" != not-found ] || return 0
    state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect service: $unit"
    case "$state" in
        active|reloading|activating|deactivating) update_services+=("$unit") ;;
        inactive|failed) ;;
        *) update_error "unexpected service state: $unit ($state)" ;;
    esac
    update_stopped_services+=("$unit")
    systemctl stop "$unit" || update_error "cannot stop service: $unit"
    state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect stopped: $unit"
    [ "$state" = inactive ] || {
        log "ERROR: $unit state: $state"
        update_error "$unit did not stop"
    }
}

update_wait_jobs() {
    local script unit state
    for script in "${update_jobs[@]}"; do
        update_wait "$script"
    done
    for unit in "${update_stopped_services[@]}"; do
        state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect stopped: $unit"
        [ "$state" = inactive ] || update_error "service restarted in update: $unit"
    done
}

update_apply() {
    update_preflight
    update_copying=1
    local i source target mode owner
    for ((i=0; i<${#update_files[@]}; i+=4)); do
        source="${update_files[i]}"
        target="${update_files[i+1]}"
        mode="${update_files[i+2]}"
        owner="${update_files[i+3]}"
        if [[ "$mode" == d* ]]; then
            install -d -m "${mode#d}" -o "${owner%:*}" -g "${owner#*:}" -- "$target" \
                || update_error "cannot prepare directory: $target"
            continue
        fi
        if [ -z "$source" ]; then
            if [ ! -d "$(dirname "$target")" ]; then
                install -d -m 755 -o root -g root -- "$(dirname "$target")" \
                    || update_error "cannot prepare destination parent: $(basename "$target")"
            fi
            continue
        fi
        install -D -m "$mode" -o "${owner%:*}" -g "${owner#*:}" -- "$source" "$target" \
            || update_error "cannot replace file: $(basename "$target")"
        cmp -s -- "$source" "$target" || {
            local compared_file
            compared_file=$(basename "$target")
            if (( ${#compared_file} <= 19 )); then
                update_error "src and dst do not match: $compared_file"
            fi
            log "ERROR: src and dst: $compared_file"
            update_error "src and dst do not match"
        }
        info "updated $(basename "$target")"
    done
}

update_resume() {
    local unit script state
    for unit in "${update_services[@]}"; do
        systemctl start "$unit" || update_error "cannot start service: $unit"
        state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect started: $unit"
        [ "$state" = active ] || {
            log "ERROR: $unit state: $state"
            update_error "$unit did not start"
        }
    done
    for script in "${update_daemons[@]}"; do
        bash "$script" --start || update_error "cannot start daemon: $script"
        [ -n "$(update_pids "$script")" ] || update_error "daemon did not start: $script"
    done
}

update_finish() {
    update_resume
    rm -f -- "${update_cron_file}.update-disabled" || update_error "cannot finish cron update: $(basename "$update_cron_file")"
    trap - EXIT
    unset UPDATE_CRON_OWNER
}

update_cleanup() {
    local status="$1" unit script
    trap - EXIT
    if (( update_copying == 0 )); then
        for unit in "${update_services[@]}"; do
            systemctl start "$unit" || warn "cannot resume $unit -alert"
        done
        for script in "${update_daemons[@]}"; do
            bash "$script" --start || warn "cannot resume $(basename "$script") -alert"
        done
        if (( update_cron_paused && ! update_cron_already_paused )); then
            if (( update_cron_existed )); then
                mv -T -- "${update_cron_file}.update-disabled" "$update_cron_file" \
                    || warn "cannot restore paused cron -alert"
            else
                rm -f -- "${update_cron_file}.update-disabled" || warn "cannot clear paused cron -alert"
            fi
        fi
    else
        if rm -f -- "$update_cron_file"; then
            warn "update failed; cron remains disabled -alert"
        else
            warn "cannot keep project cron paused -alert"
        fi
        for unit in "${update_services[@]}"; do
            systemctl stop "$unit" || warn "cannot keep $unit stopped -alert"
        done
        for script in "${update_daemons[@]}"; do
            bash "$script" --stop || warn "cannot keep $(basename "$script") stopped -alert"
        done
    fi
    (( status != 0 )) || status=1
    exit "$status"
}

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

# LAN SELECTION
# Select an existing interface and one of its configured IPv4 addresses
choose_lan_interface() {
    local preset_iface="${1:-}" excluded_iface="${2:-}"
    local iface_name iface_choice iface_index iface_addrs
    local -a lan_candidates=()
    if [ -n "$preset_iface" ]; then
        ip link show dev "$preset_iface" >/dev/null 2>&1 || {
            log "ERROR: LAN interface '$preset_iface' not found -abort"
            exit 1
        }
        [ "$preset_iface" != "$excluded_iface" ] || {
            log "ERROR: LAN and WAN must differ -abort"
            exit 1
        }
        lan_iface_answer="$preset_iface"
        return 0
    fi
    while IFS= read -r iface_name; do
        [ "$iface_name" = "$excluded_iface" ] && continue
        lan_candidates+=("$iface_name")
    done < <(ip -br link show | awk '$1 != "lo" {sub(/@.*/, "", $1); print $1}')
    (( ${#lan_candidates[@]} > 0 )) || {
        log "ERROR: no LAN interface available -abort"
        exit 1
    }
    if (( ${#lan_candidates[@]} == 1 )); then
        lan_iface_answer="${lan_candidates[0]}"
        return 0
    fi
    echo "Available LAN interfaces:"
    for iface_index in "${!lan_candidates[@]}"; do
        iface_name="${lan_candidates[$iface_index]}"
        iface_addrs=$(ip -4 -o addr show dev "$iface_name" scope global | awk '{print $4}' | paste -sd' ')
        printf ' [%d] %s (%s)\n' "$((iface_index + 1))" "$iface_name" "${iface_addrs:-no IPv4}"
    done
    while true; do
        read -r -p "Select LAN interface number: " iface_choice || {
            log "ERROR: cannot read LAN interface selection -abort"
            exit 1
        }
        if [[ "$iface_choice" =~ $UH_UINT ]] && [ "${#iface_choice}" -le 5 ] \
           && [ "$iface_choice" -ge 1 ] && [ "$iface_choice" -le "${#lan_candidates[@]}" ]; then
            lan_iface_answer="${lan_candidates[$((iface_choice - 1))]}"
            return 0
        fi
        log "INFO: invalid LAN interface selection -retry"
    done
}

read_lan_ipv4() {
    local selected_iface="$1" preset_ip="${2:-}" ipv4_choice ipv4_index candidate_cidr
    local -a lan_addresses=()
    mapfile -t lan_addresses < <(ip -4 -o addr show dev "$selected_iface" scope global | awk '{print $4}')
    (( ${#lan_addresses[@]} > 0 )) || {
        log "ERROR: LAN '$selected_iface' has no IPv4 address -abort"
        exit 1
    }
    for candidate_cidr in "${lan_addresses[@]}"; do
        [[ "$candidate_cidr" =~ $UH_CIDR ]] || {
            log "ERROR: LAN '$selected_iface' has invalid IPv4/prefix -abort"
            exit 1
        }
    done
    if [ -n "$preset_ip" ]; then
        for candidate_cidr in "${lan_addresses[@]}"; do
            if [ "${candidate_cidr%/*}" = "$preset_ip" ]; then
                lan_cidr_answer="$candidate_cidr"
                return 0
            fi
        done
        log "ERROR: requested IPv4 is not configured on LAN -abort"
        exit 1
    fi
    if (( ${#lan_addresses[@]} == 1 )); then
        lan_cidr_answer="${lan_addresses[0]}"
        return 0
    fi
    echo "IPv4 addresses on LAN '$selected_iface':"
    for ipv4_index in "${!lan_addresses[@]}"; do
        printf ' [%d] %s\n' "$((ipv4_index + 1))" "${lan_addresses[$ipv4_index]}"
    done
    while true; do
        read -r -p "Select LAN IPv4 number: " ipv4_choice || {
            log "ERROR: cannot read LAN IPv4 selection -abort"
            exit 1
        }
        if [[ "$ipv4_choice" =~ $UH_UINT ]] && [ "${#ipv4_choice}" -le 5 ] \
           && [ "$ipv4_choice" -ge 1 ] && [ "$ipv4_choice" -le "${#lan_addresses[@]}" ]; then
            lan_cidr_answer="${lan_addresses[$((ipv4_choice - 1))]}"
            return 0
        fi
        log "INFO: invalid LAN IPv4 selection -retry"
    done
}

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
    choose_lan_interface
    mgmt_answer="$lan_iface_answer"
    read_lan_ipv4 "$mgmt_answer"
    net_cidr_value=$(compute_network_cidr "$lan_cidr_answer")
    detected_ip="${lan_cidr_answer%/*}"
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

# CRON FILE
# Publish the complete project schedule after preparing it successfully.
cron_d_write() (
    local cron_file="/etc/cron.d/nwatch"
    local cron_tmp

    [ "$#" -gt 0 ] || return 1
    [ ! -L "${cron_file}.lock" ] || return 1
    (umask 077; : >> "${cron_file}.lock") || return 1
    exec 201>"${cron_file}.lock" || return 1
    flock -x 201 || return 1
    if [ -e "${cron_file}.update-disabled" ] && [ "${UPDATE_CRON_OWNER:-}" != "$$" ]; then
        return 1
    fi
    [ ! -L "$cron_file" ] || return 1
    [ ! -e "$cron_file" ] || [ -f "$cron_file" ] || return 1

    cron_tmp=$(mktemp "${cron_file}.XXXXXX") || return 1
    trap 'rm -f -- "$cron_tmp"' EXIT
    {
        printf '%s\n' '# Managed by the project installer; manual changes are replaced.'
        printf '%s\n' 'SHELL=/bin/bash' 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        printf '%s\n' "$@"
    } > "$cron_tmp" || return 1
    chmod 644 "$cron_tmp" && chown root:root "$cron_tmp" || return 1
    mv -fT -- "$cron_tmp" "$cron_file" || return 1
)

# add one @reboot cron entry per daemon, so a failure in one never keeps
# the other from starting
add_reboot_cron() {
    cron_d_write \
        "@reboot root $nwatch_tools/nwatchlan.sh --start" \
        "@reboot root $nwatch_tools/nwatchports.sh --start" \
        "@monthly root $nwatch_tools/nwatchbk.sh"
}

# APACHE LOGROTATE
# Apache keeps 14 rotations by default; the projects keep 7
set_apache_logrotate() {
    local apache_rotate="/etc/logrotate.d/apache2"
    [ -f "$apache_rotate" ] || { log "WARNING: apache2 has no logrotate file -alert"; return 0; }
    if grep -qE '^[[:space:]]*rotate[[:space:]]+7$' "$apache_rotate"; then
        log "INFO: ${apache_rotate#/etc/} already rotate 7 -skip"
        return 0
    fi
    cp -f "$apache_rotate"{,.bak} &>/dev/null || true
    sed -i -E 's/^([[:space:]]*)rotate[[:space:]]+[0-9]+$/\1rotate 7/' "$apache_rotate"
    if grep -qE '^[[:space:]]*rotate[[:space:]]+7$' "$apache_rotate"; then
        log "INFO: ${apache_rotate#/etc/} set to rotate 7 -fixed"
    else
        log "WARNING: cannot set rotate 7 in ${apache_rotate#/etc/} -alert"
    fi
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
    set_apache_logrotate
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
    cp -f "$web_dir/nwatch.conf" /etc/apache2/sites-available/nwatch.conf || {
        log "ERROR: cannot deploy nwatch.conf -abort"
        exit 1
    }
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

# Backup
BACKUP_DIR=/etc/bak/nwatch
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
    [ -f "$nwatch_env" ] || { log "ERROR: nwatch is not installed -abort"; exit 1; }
    update_reset /etc/cron.d/nwatch
    local file mode
    for file in index.php lan.html nwatchapi.php ports.html; do
        update_file "$web_dir/$file" "$nwatch_web/$file" 755 www-data:www-data
    done
    for file in nwatchenv.sh nwatchlan.sh nwatchports.sh nwatchbk.sh; do
        mode=755
        [ "$file" != nwatchenv.sh ] || mode=644
        update_file "$tools_dir/$file" "$nwatch_tools/$file" "$mode" root:root
    done
    update_target "$nwatch_data" d775 www-data:www-data
    update_target "$db_file" 640 root:www-data
    update_target /var/log/nwatch.log 640
    update_target /etc/logrotate.d/nwatch
    update_target "$update_cron_file"
    update_target "${update_cron_file}.lock" 600
    update_preflight
    update_backup "$tools_dir/nwatchbk.sh"
    update_begin
    update_stop_daemon "$nwatch_tools/nwatchlan.sh"
    update_stop_daemon "$nwatch_tools/nwatchports.sh"
    update_stop_service apache2
    update_wait_jobs
    update_apply
    if [ -f "$db_file" ]; then
        chown root:www-data "$db_file" && chmod 640 "$db_file" || update_error "cannot set database permissions"
    fi
    install_project_logrotate || update_error "cannot configure nwatch log rotation"
    add_reboot_cron || update_error "cannot regenerate nwatch cron"
    update_finish
    log "INFO: nwatch updated"
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

    if [ -x "$nwatch_tools/nwatchbk.sh" ]; then
        if "$nwatch_tools/nwatchbk.sh"; then
            log "INFO: backup taken with nwatchbk.sh"
        else
            log "ERROR: nwatchbk.sh: backup failed -abort"
            exit 1
        fi
    else
        log "ERROR: nwatchbk.sh: missing or not executable -abort"
        exit 1
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

    rm -f /etc/cron.d/nwatch /etc/cron.d/nwatch.update-disabled

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
    { mapfile -d '' -t args < "/proc/$pid/cmdline"; } 2>/dev/null || return 1
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
                log "EVENT: nwatchsetup done"
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
log "EVENT: nwatchsetup start..."
case "${1:-}" in
    --install) do_install ;;
    --update) do_update || exit 1 ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    *)
        log "ERROR: invalid option -abort"
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: nwatchsetup done"
