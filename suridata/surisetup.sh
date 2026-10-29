#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata Installer
# FILE: surisetup.sh
#
# USAGE:
# sudo bash surisetup.sh --install
# sudo bash surisetup.sh --update
# sudo bash surisetup.sh --uninstall
# sudo bash surisetup.sh --status
#
# LOG: surisetup.log, beside this script
#
################################################################################

set -Euo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# error handling
report_failure() {
    local failure_text="$failure_message"
    failure_text+=" -abort"
    if declare -F err >/dev/null; then
        err "$failure_text"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $failure_text" >&2
    fi
}

failure_message="cannot initialize Suridata"
trap 'report_failure; exit 1' ERR

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
failure_message="cannot open the installer lock"
exec 200>"$script_lock"

if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

failure_message="cannot find the installer directory"
script_dir="$(cd "$(dirname "$(realpath "$0")")" && pwd)"

# Every repository path below is relative to the script, not to wherever the
# administrator happened to be standing when running it
cd "$script_dir" || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot enter $(basename "$script_dir") -abort" >&2; exit 1; }

log_file="${script_dir}/surisetup.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then echo "$msg" >&2; else echo "$msg"; fi
}
info() { log "INFO: $*"; }
warn() { log "WARNING: $*"; }
err()  { log "ERROR: $*"; }
abort() { err "$*"; exit 1; }

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# validation -- one variable per thing validated; use directly with =~
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'
UH_UINT='^(0|[1-9][0-9]*)$'

data_dir="$script_dir/data"
install_dir="$script_dir/install"
conf_dir="/etc/suricata"
conf_data_dir="$conf_dir/data"
suridata_env="$conf_data_dir/suridata.env"
out_file="$conf_data_dir/suridata.txt"
state_dir="/var/lib/suricata"
log_dir="/var/log/suricata"
project_log="/var/log/suridata.log"
ulog_dir="/var/log/ulog"
cron_file="/etc/cron.d/suridata"
rotate_file="/etc/logrotate.d/suridata"
backup_dir="/etc/bak/suridata"
suricata_yaml="$conf_dir/suricata.yaml"
suricata_service="/usr/lib/systemd/system/suricata.service"
evebox_dir="/etc/evebox"
evebox_keyring="/etc/apt/keyrings/evebox.asc"
evebox_list="/etc/apt/sources.list.d/evebox.list"
evebox_service="/etc/systemd/system/evebox.service"
evebox_key_url="https://evebox.org/files/GPG-KEY-evebox"
evebox_repo="https://evebox.org/files/debian stable main"

# the files this project owns, copied as a block
project_scripts=(suridataenv.sh suridata.sh suricataupdate.sh suricataclean.sh suribk.sh)
project_data=(drop.conf disable.conf suridata.txt)
project_evebox=(evebox.yaml evebox.service)

# apt packages this project needs; ulogd2 serves the NFLOG rule
project_packages=(suricata suricata-update jq ipset iptables ulogd2 python3 curl ca-certificates zip logrotate cron iproute2 grep coreutils findutils util-linux sed libc-bin)

# answers collected by ask_settings, written to suridata.env
wan_iface=""
lan_iface=""
serv_subnet=""
lan_netmask_answer=""

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
    local unit state
    for unit in "${update_services[@]}"; do
        systemctl start "$unit" || update_error "cannot start service: $unit"
        state=$(systemctl show -p ActiveState --value "$unit") || update_error "cannot inspect started: $unit"
        [ "$state" = active ] || {
            log "ERROR: $unit state: $state"
            update_error "$unit did not start"
        }
    done
}

update_finish() {
    update_resume
    rm -f -- "${update_cron_file}.update-disabled" || update_error "cannot finish cron update: $(basename "$update_cron_file")"
    trap - EXIT
    unset UPDATE_CRON_OWNER
}

update_cleanup() {
    local status="$1" unit
    trap - EXIT
    if (( update_copying == 0 )); then
        for unit in "${update_services[@]}"; do
            systemctl start "$unit" || warn "cannot resume $unit -alert"
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
    fi
    (( status != 0 )) || status=1
    exit "$status"
}

# ACL PREPARATION
# Canonical block -- copied byte for byte into every script that creates a
# directory or a list under /etc/acl. Prepare /etc/acl first, then only the
# subdirectory and the lists this script needs. Never recursive.
# Usage: acl_prepare <dir> <dir_mode> <file_mode> [file ...]
acl_prepare() {
    local acl_dir="$1" dir_mode="$2" file_mode="$3" acl_file
    shift 3

    # mkdir without -p fails when the directory already exists, so a success
    # means this run created it and no concurrent run did.
    if mkdir -m "$dir_mode" -- "$acl_dir" 2>/dev/null; then
        if ! chown root:root -- "$acl_dir"; then
            log "ERROR: cannot set owner of $acl_dir -abort"
            exit 1
        fi
        log "WARNING: created ACL directory $acl_dir -alert"
    elif [ -d "$acl_dir" ] && [ ! -L "$acl_dir" ]; then
        acl_fix_perms "$acl_dir" "$dir_mode"
    else
        log "ERROR: $acl_dir is not a regular directory -abort"
        exit 1
    fi

    for acl_file in "$@"; do
        # Checked before the redirection: noclobber only protects regular
        # files, and opening a FIFO for writing blocks until a reader shows up.
        if [ -L "$acl_file" ] || { [ -e "$acl_file" ] && [ ! -f "$acl_file" ]; }; then
            log "ERROR: $(basename "$acl_file") is not a regular file -abort"
            exit 1
        fi
        # noclobber makes the redirection fail when the file already exists,
        # and umask 077 keeps the new file closed until chmod sets its mode.
        if (set -C; umask 077; : > "$acl_file") 2>/dev/null; then
            if ! { chmod "$file_mode" -- "$acl_file" \
                && chown root:root -- "$acl_file"; }; then
                log "ERROR: cannot set perms of $(basename "$acl_file") -abort"
                exit 1
            fi
            log "WARNING: created empty $(basename "$acl_file") -alert"
        elif [ -f "$acl_file" ] && [ ! -L "$acl_file" ]; then
            acl_fix_perms "$acl_file" "$file_mode"
        else
            log "ERROR: $(basename "$acl_file") is not a regular file -abort"
            exit 1
        fi
    done
}

# Repairs mode and owner of an existing ACL object, per Autorreparación
acl_fix_perms() {
    local acl_path="$1" want_mode="$2" cur_mode cur_owner
    cur_mode=$(stat -c '%a' -- "$acl_path" 2>/dev/null) || {
        log "ERROR: cannot stat $acl_path -abort"; exit 1; }
    cur_owner=$(stat -c '%U:%G' -- "$acl_path" 2>/dev/null) || {
        log "ERROR: cannot stat $acl_path -abort"; exit 1; }
    [[ "$cur_mode" == "$want_mode" && "$cur_owner" == "root:root" ]] && return 0
    if ! { chmod "$want_mode" -- "$acl_path" \
        && chown root:root -- "$acl_path"; }; then
        log "ERROR: cannot fix $(basename "$acl_path") perms -abort"
        exit 1
    fi
    log "INFO: $acl_path perms fixed -fixed"
}

read_env_value() {
    local env_name="$1"
    load_suridata_env "$suridata_env" "$env_name" || return 1
    printf '%s\n' "${!env_name:-}"
}

# CRON FILE
# Publish the complete project schedule after preparing it successfully.
cron_d_write() (
    local cron_file="/etc/cron.d/suridata"
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

register_project_cron() {
    cron_d_write \
        "0 2 * * * root $conf_dir/suricataupdate.sh >/dev/null 2>&1" \
        "@monthly root $conf_dir/suricataclean.sh >/dev/null 2>&1" \
        "*/5 * * * * root $conf_dir/suridata.sh >/dev/null 2>&1" \
        "@monthly root $conf_dir/suribk.sh"
}

# CONFLICTS
# Another IDS already installed means a clean install is not possible
check_conflicts() {
    local role="$1"; shift
    local dep_pkg
    local -a found=()
    for dep_pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null | grep -q "ok installed"; then
            found+=("$dep_pkg")
        fi
    done
    if [ "${#found[@]}" -gt 0 ]; then
        for dep_pkg in "${found[@]}"; do
            warn "conflicting $role: $dep_pkg -alert"
        done
        abort "remove them with apt purge -abort"
    fi
}

# RETRY_CMD
# Run a command twice before giving up, for transient apt failures
retry_cmd() {
    local attempt
    for attempt in 1 2; do
        if "$@"; then
            return 0
        fi
        warn "$1 $2 failed (attempt $attempt/2) -alert"
        sleep 3
    done
    return 1
}

# PACKAGES
# Install only what is missing, so a second run installs nothing
install_packages() {
    local failure_message="cannot verify the installed packages"
    local pkg
    local -a missing=()
    for pkg in "${project_packages[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed' || missing+=("$pkg")
    done
    if (( ${#missing[@]} == 0 )); then
        return 0
    fi
    failure_message="cannot update the package lists"
    retry_cmd apt-get update -qq || warn "cannot update package lists -alert"
    failure_message="cannot install the required packages"
    if ! retry_cmd apt-get install -y "${missing[@]}"; then
        for pkg in "${missing[@]}"; do
            warn "package in failed install: $pkg -alert"
        done
        abort "required package installation failed -abort"
    fi
    for pkg in "${missing[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed' || abort "package '$pkg' still missing -abort"
    done
}

# IFACES
# List network interfaces other than loopback
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

# IPV4 INTERFACES
# Offer only interfaces with an active link and configured global IPv4
list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

print_ifaces() {
    local i iface_state iface_addrs
    echo "Available network interfaces:" >&2
    for i in "${!ifaces[@]}"; do
        iface_state=$(ip -br link show "${ifaces[$i]}" | awk '{print $2}')
        iface_addrs=$(ip -4 -o addr show dev "${ifaces[$i]}" scope global | awk '{print $4}' | paste -sd' ')
        printf " [%d] %s (%s, %s)\n" "$((i+1))" "${ifaces[$i]}" "$iface_state" "${iface_addrs:-no IPv4}" >&2
    done
}

# ask for one interface and confirm it, rejecting the one already taken
ask_iface() {
    local prompt="$1" taken="$2" selection candidate confirm
    while true; do
        print_ifaces
        read -r -p "$prompt [1-${#ifaces[@]}]: " selection || {
            log "ERROR: cannot read interface selection -abort" >&2
            return 1
        }
        if ! [[ "$selection" =~ $UH_UINT ]] \
           || [ "${#selection}" -gt 5 ] \
           || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#ifaces[@]}" ]; then
            info "invalid selection -retry" >&2
            continue
        fi
        candidate="${ifaces[$((selection-1))]}"
        if [ -n "$taken" ] && [ "$candidate" = "$taken" ]; then
            info "interface already assigned to $taken -retry" >&2
            continue
        fi
        read -r -p "Confirm interface is '$candidate'? (y/n): " confirm || {
            log "ERROR: cannot read interface confirmation -abort" >&2
            return 1
        }
        case "$confirm" in
            [Yy]*) echo "$candidate"; return 0 ;;
            [Nn]*) continue ;;
            *) info "answer y or n -retry" >&2 ;;
        esac
    done
}

# LAN SELECTION
# Select an existing interface and one of its configured IPv4 addresses
choose_lan_interface() {
    local preset_iface="${1:-}" excluded_iface="${2:-}"
    local iface_name iface_choice iface_index iface_addrs iface_state
    local -a lan_candidates=()
    while IFS= read -r iface_name; do
        [ "$iface_name" = "$excluded_iface" ] && continue
        lan_candidates+=("$iface_name")
    done < <(list_ipv4_ifaces)
    (( ${#lan_candidates[@]} > 0 )) || {
        log "ERROR: no LAN interface available -abort"
        exit 1
    }
    if [ -n "$preset_iface" ]; then
        for iface_name in "${lan_candidates[@]}"; do
            if [ "$preset_iface" = "$iface_name" ]; then
                lan_iface_answer="$preset_iface"
                return 0
            fi
        done
        log "ERROR: LAN must be an eligible IPv4 interface -abort"
        exit 1
    fi
    echo "Available LAN interfaces:"
    for iface_index in "${!lan_candidates[@]}"; do
        iface_name="${lan_candidates[$iface_index]}"
        iface_state=$(ip -br link show "$iface_name" | awk '{print $2}')
        iface_addrs=$(ip -4 -o addr show dev "$iface_name" scope global | awk '{print $4}' | paste -sd' ')
        printf ' [%d] %s (%s, %s)\n' "$((iface_index + 1))" "$iface_name" "$iface_state" "${iface_addrs:-no IPv4}"
    done
    while true; do
        read -r -p "Select LAN Interface [1-${#lan_candidates[@]}]: " iface_choice || {
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

# WAN CHECK
# Require configured WAN IPv4 networks before installing project packages
check_wan_ipv4() {
    local selected_wan="$1" wan_cidr
    local -a wan_addresses=()
    mapfile -t wan_addresses < <(ip -4 -o addr show dev "$selected_wan" scope global 2>/dev/null | awk '{print $4}')
    (( ${#wan_addresses[@]} > 0 )) || abort "WAN '$selected_wan' has no IPv4 address -abort"
    for wan_cidr in "${wan_addresses[@]}"; do
        [[ "$wan_cidr" =~ $UH_CIDR ]] || abort "WAN '$selected_wan' has invalid IPv4/prefix -abort"
    done
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

# ANSWERS
# Unattended mode -- a caller (e.g. gpsetup.sh) sets SURIDATA_WAN_IFACE and
# SURIDATA_LAN_IFACE. SURIDATA_SERVER_IP selects an existing LAN address.
# SURIDATA_SERV_SUBNET is
# checked against the network derived from the LAN interface.
ask_settings() {
    local failure_message="cannot collect the installer answers"
    local -a ifaces=()

    wan_iface="${SURIDATA_WAN_IFACE:-}"
    lan_iface="${SURIDATA_LAN_IFACE:-}"
    mapfile -t ifaces < <(list_ipv4_ifaces)
    (( ${#ifaces[@]} > 0 )) || abort "no active interface with IPv4 -abort"
    if [ -n "$wan_iface" ]; then
        printf '%s\n' "${ifaces[@]}" | grep -qxF -- "$wan_iface" \
            || abort "WAN must be an active interface with IPv4 -abort"
    fi
    if [ -n "$lan_iface" ]; then
        printf '%s\n' "${ifaces[@]}" | grep -qxF -- "$lan_iface" \
            || abort "LAN must be an active interface with IPv4 -abort"
    fi

    if (( ${#ifaces[@]} == 1 )); then
        [ -z "$wan_iface" ] || abort "WAN requires a distinct LAN interface -abort"
        lan_iface="${ifaces[0]}"
    else
        if [ -z "$wan_iface" ]; then
            failure_message="cannot read the WAN interface choice"
            wan_iface="$(ask_iface 'Select WAN Interface' "$lan_iface")" \
                || abort "cannot read WAN interface selection -abort"
        fi
        choose_lan_interface "$lan_iface" "$wan_iface"
        lan_iface="$lan_iface_answer"
    fi

    if [ -n "$wan_iface" ] && [ "$wan_iface" = "$lan_iface" ]; then
        abort "WAN and LAN must differ -abort"
    fi
    [ -n "$wan_iface" ] && info "WAN interface: $wan_iface"
    info "LAN interface: $lan_iface"
    read_lan_ipv4 "$lan_iface" "${SURIDATA_SERVER_IP:-}"
    [ -n "$wan_iface" ] && check_wan_ipv4 "$wan_iface"
    return 0
}

# LAN NETWORK
# Calculate network settings after the required Python package is available
calculate_lan_network() {
    mapfile -t network_values < <(python3 -c '
import ipaddress, sys
net = ipaddress.IPv4Interface(sys.argv[1]).network
print(net.network_address)
print(net.netmask)
' "$lan_cidr_answer")
    [ "${#network_values[@]}" -eq 2 ] || abort "cannot calculate LAN network -abort"
    serv_subnet="${network_values[0]}"
    lan_netmask_answer="${network_values[1]}"
    if [ -n "${SURIDATA_SERV_SUBNET:-}" ] && [ "$SURIDATA_SERV_SUBNET" != "$serv_subnet" ]; then
        abort "requested subnet differs from configured LAN -abort"
    fi
    info "LAN subnet: $serv_subnet"
}

# ENV FILE
# Write network settings and backup destination to suridata.env
write_env() {
    local failure_message="cannot write $suridata_env"
    # WAN_IFACE only exists when a second candidate was selected as WAN
    local network_block="INTERFACESv4=$lan_iface"
    if [ -n "$wan_iface" ]; then
        network_block="# WAN_IFACE: external interface whose networks are excluded
WAN_IFACE=$wan_iface
$network_block"
    fi
    cat > "$suridata_env" <<ENV_END
# =============================================================================
# Suridata
# /etc/suricata/data/suridata.env
# =============================================================================

# Network
# INTERFACESv4: inspected interface, always the LAN suridata watches
# SERV_SUBNET and SERV_MASK: local IPv4 network and netmask
$network_block
SERV_SUBNET=$serv_subnet
SERV_MASK=$lan_netmask_answer

# Backup
# BACKUP_DIR: where suribk.sh writes its archives
BACKUP_DIR=$backup_dir
# =============================================================================
ENV_END
    failure_message="cannot set owner of $(basename "$suridata_env")"
    chown root:root "$suridata_env"
    failure_message="cannot set permissions on $(basename "$suridata_env")"
    chmod 640 "$suridata_env"
    info "$(basename "$suridata_env") written"
}

check_install_sources() {
    local file
    for file in "${project_scripts[@]}" "${project_evebox[@]}"; do
        [ -f "$install_dir/$file" ] && [ -r "$install_dir/$file" ] || abort "$file not readable in repository -abort"
    done
    for file in "${project_data[@]}"; do
        [ -f "$data_dir/$file" ] && [ -r "$data_dir/$file" ] || abort "$file not readable in repository -abort"
    done
}

# FILES
# Copy the project files and set their owner and mode
install_files() {
    local failure_message="cannot create $conf_dir"
    mkdir -p "$conf_dir" "$state_dir" "$log_dir" "$ulog_dir"
    acl_prepare "$conf_data_dir" 700 600

    local file
    for file in "${project_scripts[@]}"; do
        [ -f "$install_dir/$file" ] || abort "$file not found in the repository -abort"
    done
    for file in "${project_data[@]}"; do
        [ -f "$data_dir/$file" ] || abort "$file not found in the repository -abort"
    done

    failure_message="cannot copy the project scripts"
    cp -f "${project_scripts[@]/#/$install_dir/}" "$conf_dir/"
    failure_message="cannot set owner of the project scripts"
    chown root:root "${project_scripts[@]/#/$conf_dir/}"
    failure_message="cannot set permissions on the project scripts"
    chmod 750 "${project_scripts[@]/#/$conf_dir/}"
    for file in "${project_scripts[@]}"; do
        info "updated $file"
    done

    for file in "${project_data[@]}"; do
        if [ -L "$conf_data_dir/$file" ] || { [ -e "$conf_data_dir/$file" ] && [ ! -f "$conf_data_dir/$file" ]; }; then
            abort "$file is not a regular file -abort"
        fi
        if [ ! -e "$conf_data_dir/$file" ]; then
            failure_message="cannot copy $file"
            install -m 600 -o root -g root -- "$data_dir/$file" "$conf_data_dir/$file"
            cmp -s -- "$data_dir/$file" "$conf_data_dir/$file" || abort "src and dst do not match: $file -abort"
        fi
        acl_prepare "$conf_data_dir" 700 600 "$conf_data_dir/$file"
    done

    failure_message="cannot create $project_log"
    touch "$project_log"
    failure_message="cannot set owner of $project_log"
    chown root:root "$project_log"
    failure_message="cannot set permissions on $(basename "$project_log")"
    chmod 640 "$project_log"

    failure_message="cannot create the NFLOG log file"
    touch "$ulog_dir/syslogemu.log"
}

# SURICATA
# Suricata listens on the local interface, in IDS mode, and reports the
# community-id, which EveBox needs to group a flow's events
configure_suricata() {
    local failure_message="cannot edit $(basename "$suricata_yaml")"
    [ -f "$suricata_yaml" ] || abort "$suricata_yaml not found -abort"

    sed -i "s/interface: eth[0-9]/interface: $lan_iface/g" "$suricata_yaml"
    if grep -q "community-id: false" "$suricata_yaml"; then
        sed -i 's/community-id: false/community-id: true/' "$suricata_yaml"
        info "community-id enabled"
    fi
    if grep -q "detect-thread-ratio: 1.0" "$suricata_yaml"; then
        sed -i 's/detect-thread-ratio: 1.0/detect-thread-ratio: 0.5/' "$suricata_yaml"
        info "detect-thread-ratio set to 0.5"
    fi

    # IDS mode: AF-PACKET without -q, so Suricata never sits inline
    if [ -f "$suricata_service" ]; then
        if grep -q "^ExecStart=.*-q" "$suricata_service"; then
            failure_message="cannot edit the Suricata service settings"
            sed -i "s|^ExecStart=.*|ExecStart=/usr/bin/suricata -D --af-packet -c $suricata_yaml --pidfile /run/suricata.pid|" "$suricata_service"
            failure_message="cannot reload the systemd units"
            systemctl daemon-reload
            info "Suricata switched to IDS mode"
        fi
    else
        warn "$(basename "$suricata_service") not found -alert"
    fi

    # Suricata aborts without a rule file, and suricataupdate.sh only runs at
    # the end of the installation, so the first rule set is fetched here
    if [ ! -f "$state_dir/rules/suricata.rules" ]; then
        failure_message="cannot download the initial rule set"
        suricata-update --disable-conf="$conf_data_dir/disable.conf" \
                        --drop-conf="$conf_data_dir/drop.conf" \
                        --quiet >> "$log_file" 2>&1 \
            || abort "cannot download the initial rule set -abort"
        info "initial rule set downloaded"
    fi

    failure_message="cannot enable suricata.service"
    systemctl enable suricata.service &>/dev/null || abort "cannot enable suricata.service -abort"
    failure_message="cannot restart suricata.service"
    systemctl restart suricata.service || abort "cannot restart suricata.service -abort"
    systemctl is-active --quiet suricata.service || abort "suricata.service is not active -abort"
}

# LOGROTATE
# Rotates the project log. suricataclean.sh handles Suricata's own logs.
install_logrotate() {
    local failure_message="cannot write $rotate_file"
    cat > "$rotate_file" <<ROTATE_END
$project_log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
ROTATE_END
    [ "$?" -eq 0 ] || return 1
    failure_message="cannot set owner of $rotate_file"
    chown root:root "$rotate_file" || return 1
    failure_message="cannot set permissions on $(basename "$rotate_file")"
    chmod 644 "$rotate_file" || return 1
    info "logrotate set: $rotate_file"
}

# EVEBOX
# The web viewer for eve.json. It ships from its own APT repository, so the
# key and the source list come first, then the package and its settings.
install_evebox() {
    local failure_message="cannot install evebox"
    if ! dpkg-query -W -f='${Status}' evebox 2>/dev/null | grep -q 'ok installed'; then
        failure_message="cannot create the APT keyrings directory"
        mkdir -p "$(dirname "$evebox_keyring")"
        failure_message="cannot download $(basename "$evebox_key_url")"
        if ! retry_cmd curl -fsSL "$evebox_key_url" -o "$evebox_keyring"; then
            abort "cannot download the evebox key -abort"
        fi
        info "evebox key saved"
        failure_message="cannot write $(basename "$evebox_list")"
        echo "deb [signed-by=$evebox_keyring] $evebox_repo" > "$evebox_list"
        failure_message="cannot update the package lists"
        retry_cmd apt-get update -qq || warn "cannot update package lists -alert"
        failure_message="cannot install evebox"
        if ! retry_cmd apt-get install -y evebox; then
            abort "cannot install evebox -abort"
        fi
    else
        info "evebox already installed -skip"
    fi

    dpkg-query -W -f='${Status}' evebox 2>/dev/null | grep -q 'ok installed' || abort "package 'evebox' still missing -abort"

    local file
    for file in "${project_evebox[@]}"; do
        [ -f "$install_dir/$file" ] || abort "$file not found in the repository -abort"
    done

    failure_message="cannot create $evebox_dir"
    mkdir -p "$evebox_dir"
    failure_message="cannot copy evebox.yaml"
    cp -f "$install_dir/evebox.yaml" "$evebox_dir/evebox.yaml"
    failure_message="cannot set permissions on evebox.yaml"
    chown root:root "$evebox_dir/evebox.yaml"
    chmod 644 "$evebox_dir/evebox.yaml"
    failure_message="cannot copy evebox.service"
    cp -f "$install_dir/evebox.service" "$evebox_service"
    failure_message="cannot set permissions on evebox.service"
    chown root:root "$evebox_service"
    chmod 644 "$evebox_service"

    failure_message="cannot reload the systemd units"
    systemctl daemon-reload
    failure_message="cannot enable evebox.service"
    systemctl enable evebox.service &>/dev/null || abort "cannot enable evebox.service -abort"
    failure_message="cannot restart evebox.service"
    systemctl restart evebox.service || abort "cannot restart evebox.service -abort"
    systemctl is-active --quiet evebox.service || abort "evebox.service is not active -abort"
    info "EveBox: http://localhost:5636"
}

# ------------------------------------------------------------------------------
# INSTALL
# ------------------------------------------------------------------------------

check_already_installed() {
    local failure_message="cannot check the current installation"
    local already_installed=0
    local skip_reasons=""

    if [ -f "$suridata_env" ]; then
        already_installed=1
        skip_reasons+="suridata.env already exists\n"
    fi
    if dpkg-query -W -f='${Status}' suricata 2>/dev/null | grep -q 'ok installed'; then
        already_installed=1
        skip_reasons+="suricata already installed\n"
    fi
    if dpkg-query -W -f='${Status}' evebox 2>/dev/null | grep -q 'ok installed'; then
        already_installed=1
        skip_reasons+="evebox already installed\n"
    fi

    if [ "$already_installed" -eq 1 ]; then
        local reason
        while IFS= read -r reason; do
            [ -z "$reason" ] || warn "$reason -alert"
        done < <(printf "%b" "$skip_reasons")
        abort "suridata already installed; use --update -abort"
        exit 1
    fi
}

do_install() {
    local failure_message="cannot install suridata"
    check_already_installed
    failure_message="cannot check conflicting packages"
    check_conflicts "IDS" snort
    local network_command
    for network_command in ip awk; do
        command -v "$network_command" >/dev/null 2>&1 \
            || abort "network command '$network_command' missing -abort"
    done
    check_install_sources
    ask_settings
    check_internet
    install_packages
    calculate_lan_network
    install_files
    write_env
    configure_suricata
    install_evebox
    install_logrotate
    register_project_cron || abort "cannot update suridata cron -abort"

    # first run: apply drop.conf, then build the blocklist and the rules
    "$conf_dir/suricataupdate.sh" || abort "suricataupdate.sh failed -abort"
    "$conf_dir/suridata.sh" || abort "suridata.sh failed -abort"
    info "suridata installed"
}

# ------------------------------------------------------------------------------
# UPDATE
# ------------------------------------------------------------------------------

# Refreshes code, rules, permissions and cron. Keeps suridata.env and the
# blocklist, because both hold live data this installer never decides.
do_update() {
    [ -f "$suridata_env" ] || abort "suridata is not installed -abort"
    update_reset /etc/cron.d/suridata
    local file package
    for package in suricata evebox; do
        dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'ok installed' || abort "required package '$package' is not installed -abort"
    done
    for file in "${project_scripts[@]}"; do
        update_file "$install_dir/$file" "$conf_dir/$file" 750 root:root
    done
    for file in "${project_data[@]}"; do
        if [ ! -e "$conf_data_dir/$file" ]; then
            update_file "$data_dir/$file" "$conf_data_dir/$file" 600 root:root
        fi
        update_target "$conf_data_dir/$file" 600
    done
    update_target "$conf_data_dir" d700 root:root
    update_file "$install_dir/evebox.yaml" "$evebox_dir/evebox.yaml" 644 root:root
    update_file "$install_dir/evebox.service" "$evebox_service" 644 root:root
    update_target "$rotate_file"
    update_target "$project_log" 640
    update_target "$update_cron_file"
    update_target "${update_cron_file}.lock" 600
    update_preflight
    update_backup "$install_dir/suribk.sh"
    update_begin
    update_stop_service suricata.service
    update_stop_service evebox.service
    update_wait_jobs
    update_apply
    acl_prepare "$conf_data_dir" 700 600 "${project_data[@]/#/$conf_data_dir/}"
    touch "$project_log" && chown root:root "$project_log" && chmod 640 "$project_log" \
        || update_error "cannot prepare log: $project_log"
    install_logrotate || update_error "cannot configure suridata log rotation"
    systemctl daemon-reload || update_error "cannot reload systemd configuration"
    register_project_cron || update_error "cannot regenerate suridata cron"
    update_finish
    info "suridata updated"
}

# ------------------------------------------------------------------------------
# UNINSTALL
# ------------------------------------------------------------------------------

# Removes the rules, the ipset, the cron and the project files. Suricata
# itself stays installed, because this installer is not its owner.
do_uninstall() {
    local failure_message="cannot uninstall suridata"
    local confirm keep_data
    read -r -p "Remove suridata? (y/n): " confirm
    case "$confirm" in
        [Yy]*) ;;
        *) info "uninstall cancelled"; return 0 ;;
    esac

    # preventive backup before removing anything
    if [ -x "$conf_dir/suribk.sh" ]; then
        if bash "$conf_dir/suribk.sh"; then
            info "backup taken with suribk.sh"
        else
            abort "suribk.sh: backup failed -abort"
        fi
    else
        abort "suribk.sh: missing or not executable -abort"
    fi

    (umask 077; : >> "/var/lock/suricataupdate.lock") || abort "cannot open suricataupdate lock -abort"
    exec 201>"/var/lock/suricataupdate.lock" || abort "cannot open suricataupdate lock -abort"
    flock -w 600 201 || abort "suricataupdate.sh still running -abort"
    (umask 077; : >> "/var/lock/suricataclean.lock") || abort "cannot open suricataclean lock -abort"
    exec 202>"/var/lock/suricataclean.lock" || abort "cannot open suricataclean lock -abort"
    flock -w 600 202 || abort "suricataclean.sh still running -abort"
    (umask 077; : >> "/var/lock/suridata.lock") || abort "cannot open suridata lock -abort"
    exec 203>"/var/lock/suridata.lock" || abort "cannot open suridata lock -abort"
    flock -w 600 203 || abort "suridata.sh still running -abort"

    failure_message="cannot remove the iptables rules"
    local iface=""
    if [ -f "$suridata_env" ]; then
        iface=$(read_env_value INTERFACESv4)
    fi
    if [ -n "$iface" ]; then
        while iptables -t mangle -C PREROUTING -i "$iface" -m set --match-set suridata dst \
            -j NFLOG --nflog-prefix "SURIDATA DROP: " 2>/dev/null; do
            iptables -t mangle -D PREROUTING -i "$iface" -m set --match-set suridata dst \
                -j NFLOG --nflog-prefix "SURIDATA DROP: " || {
                warn "cannot remove suridata NFLOG rule -alert"
                break
            }
        done
        while iptables -t mangle -C PREROUTING -i "$iface" -m set --match-set suridata dst -j DROP 2>/dev/null; do
            iptables -t mangle -D PREROUTING -i "$iface" -m set --match-set suridata dst -j DROP || {
                warn "cannot remove suridata DROP rule -alert"
                break
            }
        done
    else
        warn "LAN interface unknown; iptables rules kept -alert"
    fi

    failure_message="cannot remove the ipset"
    if ipset list suridata &>/dev/null; then
        ipset flush suridata 2>/dev/null || warn "cannot flush ipset 'suridata' -alert"
        ipset destroy suridata 2>/dev/null || warn "cannot destroy ipset 'suridata' -alert"
    fi

    failure_message="cannot remove $cron_file"
    rm -f "$cron_file" "${cron_file}.update-disabled"
    failure_message="cannot remove $rotate_file"
    rm -f "$rotate_file"

    failure_message="cannot remove the project files"
    rm -f "${project_scripts[@]/#/$conf_dir/}"
    rm -f "$state_dir/suridata.offset" "$state_dir/suridata.sids"

    # the four protected files go only when the administrator says so
    read -r -p "Remove the protected data in $conf_data_dir too? (y/n): " keep_data
    case "$keep_data" in
        [Yy]*)
            failure_message="cannot remove the protected data"
            rm -f "${project_data[@]/#/$conf_data_dir/}" "$suridata_env"
            rmdir "$conf_data_dir" 2>/dev/null || true
            info "protected data removed"
            ;;
        *) info "protected data kept: $conf_data_dir" ;;
    esac

    # Suricata and EveBox are asked for apart: another tool may still use them
    read -r -p "Remove suricata and suricata-update too? (y/n): " confirm
    case "$confirm" in
        [Yy]*)
            failure_message="cannot remove suricata"
            systemctl disable --now suricata.service &>/dev/null || true
            apt-get purge -y suricata suricata-update &>/dev/null \
                || warn "cannot remove suricata -alert"
            ;;
        *) info "suricata kept" ;;
    esac

    read -r -p "Remove evebox too? (y/n): " confirm
    case "$confirm" in
        [Yy]*)
            failure_message="cannot remove evebox"
            systemctl disable --now evebox.service &>/dev/null || true
            apt-get purge -y evebox &>/dev/null || warn "cannot remove evebox -alert"
            rm -f "$evebox_service" "$evebox_list" "$evebox_keyring"
            rm -rf "$evebox_dir"
            systemctl daemon-reload
            ;;
        *) info "evebox kept" ;;
    esac
    info "suridata uninstalled"
}

# ------------------------------------------------------------------------------
# STATUS
# ------------------------------------------------------------------------------

do_status() {
    local failure_message="cannot report the current state"
    local file iface drop_count ip_count status_backup_dir
    echo "suridata status"
    echo "---------------"

    if [ -f "$suridata_env" ]; then
        echo "settings:   $suridata_env"
        load_suridata_env "$suridata_env" 'WAN_IFACE|INTERFACESv4|SERV_SUBNET|SERV_MASK|BACKUP_DIR'
        local env_name
        for env_name in WAN_IFACE INTERFACESv4 SERV_SUBNET SERV_MASK BACKUP_DIR; do
            printf '  %s=%s\n' "$env_name" "${!env_name:-}"
        done
    else
        echo "settings:   not installed"
    fi

    for file in "${project_scripts[@]}"; do
        if [ -f "$conf_dir/$file" ]; then
            echo "installed:  $conf_dir/$file"
        else
            echo "missing:    $conf_dir/$file"
        fi
    done

    for file in "${project_data[@]}"; do
        if [ -f "$conf_data_dir/$file" ]; then
            echo "installed:  $conf_data_dir/$file"
        else
            echo "missing:    $conf_data_dir/$file"
        fi
    done

    if [ -f "$cron_file" ]; then
        echo "cron:       $cron_file"
    else
        echo "cron:       not installed"
    fi

    if [ -f "$rotate_file" ]; then
        echo "logrotate:  $rotate_file"
    else
        echo "logrotate:  not installed"
    fi

    # the administrator may have moved BACKUP_DIR, so the env value wins
    status_backup_dir="$backup_dir"
    if [ -f "$suridata_env" ]; then
        status_backup_dir=$(read_env_value BACKUP_DIR)
        [ -n "$status_backup_dir" ] || status_backup_dir="$backup_dir"
    fi
    ip_count=0
    if [ -d "$status_backup_dir" ]; then
        ip_count=$(find "$status_backup_dir" -maxdepth 1 -name 'suribk_*.zip' | wc -l)
    fi
    echo "backups:    $ip_count archive(s) in $status_backup_dir"

    if systemctl is-active --quiet suricata.service; then
        echo "suricata:   active"
    else
        echo "suricata:   inactive"
    fi

    if ! dpkg-query -W -f='${Status}' evebox 2>/dev/null | grep -q 'ok installed'; then
        echo "evebox:     not installed"
    elif systemctl is-active --quiet evebox.service; then
        echo "evebox:     active on http://localhost:5636"
    else
        echo "evebox:     inactive"
    fi

    drop_count=$(grep -c '^drop ' "$state_dir/rules/suricata.rules" 2>/dev/null) || drop_count=0
    echo "drop rules: $drop_count"

    if [ -f "$out_file" ]; then
        ip_count=$(grep -cE '^[0-9]' "$out_file" 2>/dev/null) || ip_count=0
        echo "blocklist:  $ip_count IP(s) in $out_file"
    else
        echo "blocklist:  not installed"
    fi

    if ipset list suridata &>/dev/null; then
        ip_count=$(ipset list suridata 2>/dev/null | grep -cE '^[0-9]') || ip_count=0
        echo "ipset:      $ip_count IP(s) loaded"
    else
        echo "ipset:      not created"
    fi

    iface=""
    [ -f "$suridata_env" ] && iface=$(read_env_value INTERFACESv4)
    if [ -n "$iface" ] \
       && iptables -t mangle -C PREROUTING -i "$iface" -m set --match-set suridata dst -j DROP 2>/dev/null; then
        echo "iptables:   rules active on $iface"
    else
        echo "iptables:   rules not active"
    fi
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

show_menu() {
    local failure_message="cannot read the installer menu choice"
    local menu_option
    while true; do
        echo "suridata installer"
        echo "------------------"
        echo "1) Install"
        echo "2) Update"
        echo "3) Uninstall"
        echo "4) Status"
        echo "5) Exit"
        read -r -p "Select option [5]: " menu_option
        menu_option="${menu_option:-5}"
        case "$menu_option" in
            1) do_install; break ;;
            2) do_update; break ;;
            3) do_uninstall; break ;;
            4) do_status; break ;;
            5) break ;;
            *) info "invalid option -retry" ;;
        esac
    done
}

usage() {
    local failure_message="cannot display installer usage"
    cat <<USAGE_END
Usage: $(basename "$0") [--install|--update|--uninstall|--status]
  --install      Fresh install
  --update       Refresh code and permissions, keep live data
  --uninstall    Remove suridata, after confirmation
  --status       Report the current state
  -h, --help     Show this message
Without arguments it opens the interactive menu.
USAGE_END
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# LOAD_CONF
# Load the shared configuration reader
source "$install_dir/suridataenv.sh" || abort "cannot load suridataenv.sh -abort"

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Run the action given on the command line, or fall back to the menu
log "EVENT: surisetup start..."

case "${1:-}" in
    --install) do_install ;;
    --update) do_update ;;
    --uninstall) do_uninstall ;;
    --status) do_status ;;
    "") show_menu ;;
    -h|--help) usage ;;
    *)
        err "invalid option -abort"
        failure_message="cannot display installer usage"
        usage
        exit 1
        ;;
esac

log "EVENT: surisetup done"
