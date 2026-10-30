#!/bin/bash
# maravento.com
#
################################################################################
#
# bkconf -- configuration backup for gateproxy
# FILE: scr/bkconf.sh
#
# USAGE:
# sudo bash bkconf.sh            Create a backup now
# sudo bash bkconf.sh --install    Register the @monthly cron entry
# sudo bash bkconf.sh --uninstall  Remove the cron entry (keeps archives)
#
# LOG: /var/log/bkconf.log
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
log_file="/var/log/bkconf.log"
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
for dep_pkg in zip coreutils findutils util-linux cron; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null)" != *"ok installed"* ]]; then
        log "ERROR: dependency '$dep_pkg' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

gateproxy_env="/etc/gateproxy/gateproxy.env"
installed_path="/etc/scr/$(basename "$0")"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Monthly is the floor, not a recommendation: it exists so an untouched
# system still has a recent copy. Run it by hand before any change.
# CRON_D
# Add or replace one line in the project's single cron.d file
cron_d_set() {
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/gateproxy"
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
        install -m 755 -o root -g root "$script_path" "$installed_path"
        log "INFO: deployed to $installed_path"
    fi

    cron_d_set "$installed_path" "@monthly root $installed_path"
    log "INFO: bkconf backup cron registered, runs @monthly"
}

deregister_cron() {
    cron_d_set "$installed_path" ""
    log "INFO: bkconf backup cron removed, archives kept"
}

# ------------------------------------------------------------------------------
# ENV
# ------------------------------------------------------------------------------

# PERMS
# Owner and mode of every .env this script reads
env_specs=("$gateproxy_env root:root 640")
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
load_gateproxy_env() {
    local conf_file="$1" conf_keys="$2" env_key env_value env_line env_count=0
    while IFS= read -r env_line || [[ -n "$env_line" ]]; do
        env_count=$((env_count + 1))
        [[ "$env_line" =~ ^[[:space:]]*[#] ]] && continue
        [[ "$env_line" =~ ^[[:space:]]*$ ]] && continue
        env_key="${env_line%%=*}"
        env_value="${env_line#*=}"
        if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
           || [[ "$env_value" == [[:space:]\"\']* ]] \
           || [[ "$env_value" == *[[:space:]\"\'] ]]; then
            if [[ ! "$env_line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                log "ERROR: $(basename "$conf_file"):$env_count not key=value -abort"
            else
                log "ERROR: $(basename "$conf_file"):$env_count space or quote in value -abort"
            fi
            exit 1
        fi
        case " $conf_keys " in
            *" $env_key "*)
                printf -v "$env_key" '%s' "$env_value"
                ;;
        esac
    done < "$conf_file"
}

# LOAD
load_gateproxy_env "$gateproxy_env" 'BACKUP_DIR' || {
    log "ERROR: cannot load gateproxy.env -abort"
    exit 1
}

# KEY CHECK
key_errors=()
if ! grep -q '^BACKUP_DIR=' "$gateproxy_env"; then
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
    log "ERROR: ${#key_errors[@]} key(s) invalid in gateproxy.env -abort"
    exit 1
fi
unset key_errors key_error

# ------------------------------------------------------------------------------
# OWN VALUES
# ------------------------------------------------------------------------------

backup_dir="$BACKUP_DIR"
backup_zip="${backup_dir}/bkconf_$(date +%Y%m%d_%H%M%S).zip"

# Start
case "${1:-}" in
    --install)
        log "EVENT: bkconf start..."
        register_cron
        log "EVENT: bkconf done"
        exit 0
        ;;
    --uninstall)
        log "EVENT: bkconf start..."
        deregister_cron
        log "EVENT: bkconf done"
        exit 0
        ;;
    "")
        log "EVENT: bkconf start..."
        ;;
    *)
        log "ERROR: '$1' invalid; --install/--uninstall or none -abort"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------------------------

if ! install -d -m 700 -o root -g root "$backup_dir"; then
    log "ERROR: cannot create $backup_dir -abort"
    exit 1
fi

# Project files and relevant system configuration are listed explicitly
# so the project state can be restored.
backup_list=()
for backup_item in \
    /etc/gateproxy \
    /etc/squid \
    /etc/acl \
    /etc/apache2 \
    /var/www \
    /etc/hosts \
    /etc/scr \
    /etc/fstab \
    /etc/samba \
    /etc/network/interfaces \
    /etc/netplan \
    /etc/apt/sources.list \
    /etc/cron.d/gateproxy \
    /etc/logrotate.d/rsyslog \
    /etc/unbound \
    /etc/suricata \
    /etc/sarg
do
    if [ -e "$backup_item" ]; then
        backup_list+=("$backup_item")
    else
        log "INFO: $backup_item not present -skip"
    fi
done

if (( ${#backup_list[@]} == 0 )); then
    log "ERROR: none of expected paths exist"
    log "ERROR: is gateproxy installed? -abort"
    exit 1
fi

# Build under a .part name so zip always starts from nothing, and so a failed
# run can only ever delete its own work. The archive takes its final name once
# zip has succeeded, which also keeps the retention glob from seeing a partial.
backup_part="${backup_zip}.part"
find "$backup_dir" -mindepth 1 -maxdepth 1 ! -name 'bkconf_*.zip' -exec rm -rf {} +
if (umask 077; zip -r -q -y "$backup_part" "${backup_list[@]}"); then
    chmod 600 "$backup_part"
    if ! mv -f "$backup_part" "$backup_zip"; then
        rm -f "$backup_part"
        log "ERROR: rename $(basename "$backup_zip"). check chmod -abort"
        exit 1
    fi
    log "INFO: backup written to $(basename "$backup_zip")"

    # keep only the last 3
    old_backups=("$backup_dir"/bkconf_*.zip)
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

log "EVENT: bkconf done"
