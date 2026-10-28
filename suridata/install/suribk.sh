#!/bin/bash
# maravento.com
#
################################################################################
#
# Suridata Backup
# FILE: suribk.sh
#
# USAGE:
# sudo bash suribk.sh
# sudo bash suribk.sh --install
# sudo bash suribk.sh --uninstall
#
# LOG: /var/log/suridata.log
#
################################################################################

set -uo pipefail

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
log_file="/var/log/suridata.log"
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
    log "ERROR: cannot open $(basename "$script_lock") -abort"
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies
for dep_pkg in zip coreutils findutils util-linux cron grep; do
    if ! dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null | grep -q 'ok installed'; then
        log "ERROR: dependency '$dep_pkg' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

suridata_env="/etc/suricata/data/suridata.env"
installed_path="/etc/suricata/$(basename "$0")"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Monthly is the floor, not a recommendation: it exists so an untouched
# system still has a recent copy. Run it by hand before any change.
# CRON_D
# Replace one task; retain other project tasks and serialize writers.
cron_d_set() (
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/suridata"
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
        install -m 750 -o root -g root "$script_path" "$installed_path" \
            || { log "ERROR: cannot replace file: $(basename "$installed_path") -abort"; exit 1; }
        cmp -s -- "$script_path" "$installed_path" \
            || { log "ERROR: src and dst do not match: $(basename "$installed_path") -abort"; exit 1; }
        log "INFO: deployed to $installed_path"
    fi

    cron_d_set "$installed_path" "@monthly root $installed_path" || { log "ERROR: cannot write project cron -abort"; return 1; }
    log "INFO: suribk backup cron registered, runs @monthly"
}

deregister_cron() {
    cron_d_set "$installed_path" "" || { log "ERROR: cannot write project cron -abort"; return 1; }
    log "INFO: suribk backup cron removed, archives kept"
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
env_specs=("$suridata_env root:root 640")
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
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/suridataenv.sh" || {
    log "ERROR: cannot load suridataenv.sh -abort"
    exit 1
}
env_keys="BACKUP_DIR"

# LOAD
load_suridata_env "$suridata_env" "$env_keys" || true

# KEY CHECK
# Collect every failure first, then decide -- a single abort reports them all
key_errors=()
if ! grep -q "^BACKUP_DIR=" "$suridata_env"; then
    key_errors+=("BACKUP_DIR missing line")
elif [[ -z "${BACKUP_DIR:-}" ]]; then
    key_errors+=("BACKUP_DIR not set")
elif [[ "$BACKUP_DIR" != /* ]]; then
    key_errors+=("BACKUP_DIR invalid absolute path")
fi
if (( ${#key_errors[@]} > 0 )); then
    for key_error in "${key_errors[@]}"; do
        log "WARNING: $key_error -alert"
    done
    log "ERROR: ${#key_errors[@]} key(s) invalid in $(basename "$suridata_env") -abort"
    exit 1
fi
unset key_errors key_error

backup_dir="$BACKUP_DIR"
backup_zip="${backup_dir}/suribk_$(date +%Y%m%d_%H%M%S).zip"

# Start
case "${1:-}" in
    --install)
        log "EVENT: suribk start..."
        register_cron || exit 1
        log "EVENT: suribk done"
        exit 0
        ;;
    --uninstall)
        log "EVENT: suribk start..."
        deregister_cron || exit 1
        log "EVENT: suribk done"
        exit 0
        ;;
    "")
        log "EVENT: suribk start..."
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
    log "ERROR: cannot create BACKUP_DIR from $(basename "$suridata_env") -abort"
    exit 1
fi

# Project files and relevant system configuration are listed explicitly
# so the project state can be restored. The rule set under /var/lib/suricata
# is left out on purpose: suricata-update downloads it again.
backup_list=()
for backup_item in \
    /etc/suricata \
    /etc/evebox \
    /etc/systemd/system/evebox.service \
    /etc/apt/sources.list.d/evebox.list \
    /etc/logrotate.d/suridata \
    /etc/cron.d/suridata \
    /var/lib/suricata/suridata.offset \
    /var/lib/suricata/suridata.sids
do
    if [ -e "$backup_item" ]; then
        backup_list+=("$backup_item")
    else
        log "INFO: $backup_item not present -skip"
    fi
done

if (( ${#backup_list[@]} == 0 )); then
    log "ERROR: cannot find Suridata installation paths -abort"
    exit 1
fi

# Build under a .part name so zip always starts from nothing, and so a failed
# run can only ever delete its own work. The archive takes its final name once
# zip has succeeded, which also keeps the retention glob from seeing a partial.
backup_part="${backup_zip}.part"
find "$backup_dir" -mindepth 1 -maxdepth 1 ! -name 'suribk_*.zip' -exec rm -rf {} +
if (umask 077; zip -r -q -y "$backup_part" "${backup_list[@]}"); then
    chmod 600 "$backup_part"
    if ! mv -f "$backup_part" "$backup_zip"; then
        rm -f "$backup_part"
        log "ERROR: rename $(basename "$backup_zip"). check chmod -abort"
        exit 1
    fi
    log "INFO: backup written to $(basename "$backup_zip")"

    # keep only the last 3
    old_backups=("$backup_dir"/suribk_*.zip)
    if (( ${#old_backups[@]} > 3 )); then
        printf '%s\0' "${old_backups[@]}" | sort -z | head -z -n -3 | xargs -0 -r rm -f --
    fi
else
    rm -f "$backup_part"
    log "ERROR: $(basename "$backup_zip"). check space/chmod -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: suribk done"
