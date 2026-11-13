#!/bin/bash
# maravento.com
#
################################################################################
#
# nwatchbk -- configuration backup for nwatch
# FILE: tools/nwatchbk.sh
#
# USAGE:
# sudo bash nwatchbk.sh            Create a backup now
# sudo bash nwatchbk.sh --install    Register the @monthly cron entry
# sudo bash nwatchbk.sh --uninstall  Remove the cron entry (keeps archives)
#
# LOG: /var/log/nwatch.log
#
################################################################################

set -euo pipefail

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
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies
for dep_pkg in python3 zip coreutils findutils util-linux cron; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null)" != *"ok installed"* ]]; then
        log "ERROR: dependency '$dep_pkg' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

nwatch_env="/etc/nwatch/nwatch.env"
installed_path="/var/www/nwatch/tools/$(basename "$0")"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Monthly is the floor, not a recommendation: it exists so an untouched
# system still has a recent copy. Run it by hand before any change.
# CRON_D
# Replace one task; retain other project tasks and serialize writers.
cron_d_set() (
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/nwatch"
    local cron_tmp cron_status

    [ -n "$match" ] || return 1
    [ ! -L "$cron_file" ] || return 1
    [ ! -e "$cron_file" ] || [ -f "$cron_file" ] || return 1
    [ ! -L "${cron_file}.lock" ] || return 1
    (umask 077; : >> "${cron_file}.lock") || return 1
    exec 201>"${cron_file}.lock" || return 1
    flock -x 201 || return 1
    if [ -e "${cron_file}.update-disabled" ] && [ "${UPDATE_CRON_OWNER:-}" != "$$" ]; then
        return 1
    fi

    cron_tmp=$(mktemp "${cron_file}.XXXXXX") || return 1
    trap 'rm -f -- "$cron_tmp"' EXIT
    if [ -f "$cron_file" ]; then
        grep -vF -- "$match" "$cron_file" > "$cron_tmp" || {
            cron_status=$?
            [ "$cron_status" -eq 1 ] || return 1
        }
    fi
    if [ -n "$line" ]; then
        printf '%s\n' "$line" >> "$cron_tmp" || return 1
    fi
    if [ -s "$cron_tmp" ]; then
        chmod 644 "$cron_tmp" && chown root:root "$cron_tmp" || return 1
        mv -fT -- "$cron_tmp" "$cron_file" || return 1
    else
        rm -f -- "$cron_file" || return 1
    fi
)

register_cron() {
    # Deploy self first: the cron entry must point at a path that exists,
    # whether this ran from the repo or from its final location.
    local script_path
    script_path="$(readlink -f "$0")"
    if [ "$script_path" != "$installed_path" ]; then
        if ! mkdir -p "$(dirname "$installed_path")"; then
            log "ERROR: cannot create $(dirname "$installed_path") -abort"
            exit 1
        fi
        install -m 644 -o root -g root "$(dirname "$script_path")/nwatchenv.sh" "$(dirname "$installed_path")/nwatchenv.sh" \
            || { log "ERROR: cannot deploy nwatchenv.sh -abort"; exit 1; }
        cmp -s -- "$(dirname "$script_path")/nwatchenv.sh" "$(dirname "$installed_path")/nwatchenv.sh" \
            || { log "ERROR: src and dst do not match: nwatchenv.sh -abort"; exit 1; }
        install -m 750 -o root -g root "$script_path" "$installed_path" \
            || { log "ERROR: cannot deploy $(basename "$installed_path") -abort"; exit 1; }
        cmp -s -- "$script_path" "$installed_path" \
            || { log "ERROR: src and dst do not match: $(basename "$installed_path") -abort"; exit 1; }
        log "INFO: deployed to $installed_path"
    fi

    cron_d_set "$installed_path" "@monthly root $installed_path" || { log "ERROR: cannot write project cron -abort"; return 1; }
    log "INFO: nwatchbk backup cron registered, runs @monthly"
}

deregister_cron() {
    cron_d_set "$installed_path" "" || { log "ERROR: cannot write project cron -abort"; return 1; }
    log "INFO: nwatchbk backup cron removed, archives kept"
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

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
if ! source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/nwatchenv.sh" 2>/dev/null; then
    log "ERROR: cannot load nwatchenv.sh -abort"
    exit 1
fi
env_keys='BACKUP_DIR'
# LOAD
load_nwatch_env "$nwatch_env" "$env_keys" || { log "ERROR: cannot load nwatch.env -abort"; exit 1; }

backup_dir="/etc/bak/nwatch"
if [[ "${BACKUP_DIR:-}" != "$backup_dir" ]] \
   || [[ "$(readlink -m -- "$backup_dir")" != "$backup_dir" ]]; then
    log "ERROR: BACKUP_DIR must be $backup_dir -abort"
    exit 1
fi
backup_zip="${backup_dir}/nwatchbk_$(date +%Y%m%d_%H%M%S).zip"

# Start
case "${1:-}" in
    --install)
        log "INFO: nwatchbk start..."
        register_cron || exit 1
        log "INFO: nwatchbk done"
        exit 0
        ;;
    --uninstall)
        log "INFO: nwatchbk start..."
        deregister_cron || exit 1
        log "INFO: nwatchbk done"
        exit 0
        ;;
    "")
        log "INFO: nwatchbk start..."
        ;;
    *)
        log "ERROR: invalid option -abort"
        echo "Usage: $(basename "$0") [--install|--uninstall]"
        echo "Without arguments: create a backup"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------------------------

if ! install -d -m 700 -o root -g root "$backup_dir"; then
    log "ERROR: cannot create BACKUP_DIR from $(basename "$nwatch_env") -abort"
    exit 1
fi

# The live database is copied with the SQLite backup API, so a write in
# progress cannot leave a torn copy in the archive.
backup_stage=$(mktemp -d "$backup_dir/nwatchbk-stage.XXXXXX")
trap 'rm -rf -- "$backup_stage"' EXIT
if [ -f /var/www/nwatch/data/nwatch.db ]; then
    if ! python3 - "$backup_stage" <<'SQLITE_BACKUP'
import os, sqlite3, stat, sys
stage = sys.argv[1]
target = os.path.join(stage, 'var/www/nwatch/data/nwatch.db')
os.makedirs(os.path.dirname(target), exist_ok=True)
with sqlite3.connect('file:/var/www/nwatch/data/nwatch.db?mode=ro', uri=True, timeout=30) as source:
    with sqlite3.connect(target) as destination:
        source.backup(destination)
original = os.stat('/var/www/nwatch/data/nwatch.db')
os.chmod(target, stat.S_IMODE(original.st_mode))
os.chown(target, original.st_uid, original.st_gid)
SQLITE_BACKUP
    then
        log "ERROR: cannot snapshot nwatch.db -abort"
        exit 1
    fi
fi

# Project files and relevant system configuration are listed explicitly
# so the project state can be restored.
backup_list=()
for backup_item in \
    /etc/nwatch \
    /var/www/nwatch \
    /etc/apache2/sites-available/nwatch.conf \
    /etc/apache2/ports.conf \
    /etc/logrotate.d/nwatch \
    /etc/cron.d/nwatch
do
    if [ -e "$backup_item" ]; then
        backup_list+=("$backup_item")
    else
        log "INFO: $(basename "$backup_item") not present"
    fi
done

if (( ${#backup_list[@]} == 0 )); then
    log "ERROR: cannot find Nwatch installation paths -abort"
    exit 1
fi

# Build under a .part name so zip always starts from nothing, and so a failed
# run can only ever delete its own work. The archive takes its final name once
# zip has succeeded, which also keeps the retention glob from seeing a partial.
backup_part="${backup_zip}.part"
trap 'rm -f -- "$backup_part"; log "ERROR: backup interrupted -abort"; exit 130' INT
if (
    umask 077
    if [[ -t 2 ]] && zip_output=$(mktemp); then
        printf 'Compressing' >&2
        while sleep 1; do printf '.' >&2; done &
        progress_pid=$!
        trap '
            kill "$progress_pid" 2>/dev/null || true
            wait "$progress_pid" 2>/dev/null || true
            printf "\n" >&2
            cat -- "$zip_output" >&2
            rm -f -- "$zip_output"
        ' EXIT
        zip -r -q -y "$backup_part" "${backup_list[@]}" -x '*/nwatch.db' '*/nwatch.db-wal' '*/nwatch.db-shm' >"$zip_output" 2>&1
    else
        zip -r -q -y "$backup_part" "${backup_list[@]}" -x '*/nwatch.db' '*/nwatch.db-wal' '*/nwatch.db-shm'
    fi
); then
    trap - INT
    if [ -f "$backup_stage/var/www/nwatch/data/nwatch.db" ] \
       && ! (cd "$backup_stage" && zip -q "$backup_part" var/www/nwatch/data/nwatch.db); then
        rm -f -- "$backup_part"
        log "ERROR: cannot archive nwatch.db snapshot -abort"
        exit 1
    fi
    chmod 600 "$backup_part"
    if ! mv -fT -- "$backup_part" "$backup_zip"; then
        rm -f "$backup_part"
        log "ERROR: rename $(basename "$backup_zip"). check chmod -abort"
        exit 1
    fi
    log "INFO: backup written to $(basename "$backup_zip")"

    if [[ "$(readlink -m -- "$backup_dir")" != "$backup_dir" ]]; then
        log "ERROR: BACKUP_DIR must be $backup_dir -abort"
        exit 1
    fi
    # keep only the last 3
    retention_ok=1
    find "$backup_dir" -mindepth 1 -maxdepth 1 ! -name 'nwatchbk_*.zip' -exec rm -rf {} + \
        || retention_ok=0
    old_backups=("$backup_dir"/nwatchbk_*.zip)
    if (( ${#old_backups[@]} > 3 )); then
        printf '%s\0' "${old_backups[@]}" | sort -z | head -z -n -3 | xargs -0 -r rm -f -- \
            || retention_ok=0
    fi
    (( retention_ok )) || log "WARNING: backup retention incomplete -alert"
else
    zip_status=$?
    trap - INT
    rm -f "$backup_part"
    log "ERROR: zip failed ($zip_status): $(basename "$backup_zip") -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "INFO: nwatchbk done"
