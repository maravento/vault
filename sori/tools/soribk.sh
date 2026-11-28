#!/bin/bash
# maravento.com
#
################################################################################
#
# soribk -- database and configuration backup for sori
# FILE: tools/soribk.sh
#
# USAGE:
# COMMAND                          ACTION
# sudo bash soribk.sh              Create a backup now
# sudo bash soribk.sh --install    Register the @monthly cron entry
# sudo bash soribk.sh --uninstall  Remove the cron entry (keeps archives)
#
# LOG: /var/log/sori.log
#
################################################################################

set -euo pipefail

# root check
if [ "$(command -p id -u)" != "0" ]; then
    echo "$(command -p date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/sori.log"
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
for dep_pkg in zip coreutils findutils util-linux cron diffutils grep mariadb-client; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null)" != *"ok installed"* ]]; then
        log "ERROR: dependency '$dep_pkg' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

sori_env="/etc/sori/sori.env"
installed_path="/var/www/sori/tools/$(basename "$0")"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Monthly is the floor, not a recommendation: it exists so an untouched
# system still has a recent copy. Run it by hand before any change.
# CRON_D
# Replace one task; retain other project tasks and serialize writers.
cron_d_set() (
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/sori"
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
        install -m 644 -o root -g root "$(dirname "$script_path")/sorienv.sh" "$(dirname "$installed_path")/sorienv.sh" \
            || { log "ERROR: cannot deploy sorienv.sh -abort"; exit 1; }
        cmp -s -- "$(dirname "$script_path")/sorienv.sh" "$(dirname "$installed_path")/sorienv.sh" \
            || { log "ERROR: src and dst do not match: sorienv.sh -abort"; exit 1; }
        install -m 750 -o root -g root "$script_path" "$installed_path" \
            || { log "ERROR: cannot deploy $(basename "$installed_path") -abort"; exit 1; }
        cmp -s -- "$script_path" "$installed_path" \
            || { log "ERROR: src and dst do not match: $(basename "$installed_path") -abort"; exit 1; }
        log "INFO: deployed to $installed_path"
    fi

    cron_d_set "$installed_path" "@monthly root $installed_path" || { log "ERROR: cannot write project cron -abort"; return 1; }
    log "INFO: soribk backup cron registered, runs @monthly"
}

deregister_cron() {
    cron_d_set "$installed_path" "" || { log "ERROR: cannot write project cron -abort"; return 1; }
    log "INFO: soribk backup cron removed, archives kept"
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
env_specs=("$sori_env root:www-data 640")
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
if ! source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/sorienv.sh" 2>/dev/null; then
    log "ERROR: cannot load sorienv.sh -abort"
    exit 1
fi
env_keys='BACKUP_DIR'
# LOAD
load_sori_env "$sori_env" "$env_keys" || { log "ERROR: cannot load sori.env -abort"; exit 1; }

backup_dir="/etc/bak/sori"
if [[ "${BACKUP_DIR:-}" != "$backup_dir" ]] \
   || [[ "$(readlink -m -- "$backup_dir")" != "$backup_dir" ]]; then
    log "ERROR: BACKUP_DIR must be $backup_dir -abort"
    exit 1
fi
backup_zip="${backup_dir}/soribk_$(date +%Y%m%d_%H%M%S).zip"

# Start
case "${1:-}" in
    --install)
        log "INFO: soribk start..."
        register_cron || exit 1
        log "INFO: soribk done"
        exit 0
        ;;
    --uninstall)
        log "INFO: soribk start..."
        deregister_cron || exit 1
        log "INFO: soribk done"
        exit 0
        ;;
    "")
        log "INFO: soribk start..."
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
    log "ERROR: cannot create BACKUP_DIR from $(basename "$sori_env") -abort"
    exit 1
fi

# Project files and relevant system configuration are listed explicitly
# so the project state can be restored. The databases go in as SQL dumps.
backup_list=()
for backup_item in \
    /etc/sori \
    /etc/cron.d/sori \
    /etc/apache2/sites-available/sori.conf \
    /etc/apache2/sites-enabled/sori.conf \
    /var/www/sori
do
    if [ -e "$backup_item" ]; then
        backup_list+=("$backup_item")
    else
        log "INFO: $(basename "$backup_item") not present"
    fi
done

if (( ${#backup_list[@]} == 0 )); then
    log "ERROR: cannot find SORI installation paths -abort"
    exit 1
fi

# Dump the control database and every client database. The dumps wait in a
# temporary folder that is removed on every exit path.
dump_dir="$(mktemp -d /var/tmp/soribk.XXXXXX)" || {
    log "ERROR: cannot create the dump folder -abort"
    exit 1
}
trap 'rm -rf -- "$dump_dir"' EXIT
mapfile -t db_list < <(mariadb -N -e "SHOW DATABASES" 2>/dev/null \
    | grep -E '^sori(_[a-z][a-z0-9]{1,29})?$')
if (( ${#db_list[@]} == 0 )); then
    log "ERROR: cannot find SORI databases -abort"
    exit 1
fi
for db_name in "${db_list[@]}"; do
    if ! (umask 077; mariadb-dump --single-transaction --routines --triggers \
            --events --default-character-set=utf8mb4 --databases "$db_name" \
            > "${dump_dir}/${db_name}.sql") 2>/dev/null; then
        log "ERROR: cannot dump database $db_name -abort"
        exit 1
    fi
done
log "INFO: ${#db_list[@]} databases dumped"
backup_list+=("$dump_dir")

# Build under a .part name so zip always starts from nothing, and so a failed
# run can only ever delete its own work. The archive takes its final name once
# zip has succeeded, which also keeps the retention glob from seeing a partial.
backup_part="${backup_zip}.part"
trap 'rm -f -- "$backup_part"; rm -rf -- "$dump_dir"; log "ERROR: backup interrupted -abort"; exit 130' INT
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
        zip -r -q -y "$backup_part" "${backup_list[@]}" >"$zip_output" 2>&1
    else
        zip -r -q -y "$backup_part" "${backup_list[@]}"
    fi
); then
    trap - INT
    chmod 600 "$backup_part"
    if ! mv -fT -- "$backup_part" "$backup_zip"; then
        rm -f "$backup_part"
        log "ERROR: cannot rename to $(basename "$backup_zip") -abort"
        exit 1
    fi
    log "INFO: backup written to $(basename "$backup_zip")"

    if [[ "$(readlink -m -- "$backup_dir")" != "$backup_dir" ]]; then
        log "ERROR: BACKUP_DIR must be $backup_dir -abort"
        exit 1
    fi
    # keep only the last 3
    backup_pattern=".*/soribk_[0-9]{8}_[0-9]{6}[.]zip"
    retention_ok=1
    find "$backup_dir" -mindepth 1 -maxdepth 1 -regextype posix-extended \
        \( ! -type f -o ! -regex "$backup_pattern" \) -exec rm -rf -- {} + || retention_ok=0
    find "$backup_dir" -mindepth 1 -maxdepth 1 -regextype posix-extended \
        -type f -regex "$backup_pattern" -print0 |
        sort -z | head -z -n -3 | xargs -0 -r rm -f -- || retention_ok=0
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

log "INFO: soribk done"
