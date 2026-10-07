#!/bin/bash
# maravento.com
#
################################################################################
#
# bkconf -- configuration backup for gateproxy
#
# DESCRIPTION:
# Creates one compressed archive with the gateproxy installation and its
# system configuration. Requires root.
#
# USAGE:
# sudo bash bkconf.sh            Create a backup now
# sudo bash bkconf.sh install    Register the @monthly cron entry
# sudo bash bkconf.sh uninstall  Remove the cron entry (keeps archives)
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

# logging
log_file="/var/log/bkconf.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep_pkg in zip coreutils util-linux cron; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: missing dependency '$dep_pkg' -- abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

backup_dir="/etc/bak/gateproxy"
backup_zip="${backup_dir}/bkconf_$(date +%Y%m%d_%H%M%S).zip"
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

    cron_tmp=$(mktemp)
    [ -f "$cron_file" ] && { grep -vF "$match" "$cron_file" > "$cron_tmp" || true; }
    [ -n "$line" ] && printf '%s\n' "$line" >> "$cron_tmp"
    if [ -s "$cron_tmp" ]; then
        install -m 644 -o root -g root "$cron_tmp" "$cron_file"
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
            log "ERROR: cannot create $(dirname "$installed_path") -- abort"
            exit 1
        fi
        install -m 755 -o root -g root "$script_path" "$installed_path"
        log "INFO: deployed to $installed_path"
    fi

    cron_d_set "$installed_path" "@monthly root $installed_path"
    log "INFO: cron entry registered, runs @monthly"
    log "INFO: $installed_path"
}

deregister_cron() {
    cron_d_set "$installed_path" ""
    log "INFO: cron entry removed, archives kept"
}

case "${1:-}" in
    install)
        register_cron
        exit 0
        ;;
    uninstall)
        deregister_cron
        exit 0
        ;;
    "")
        ;;
    *)
        log "ERROR: use no argument, 'install' or 'uninstall'"
        log "ERROR: unknown action '$1' -- abort"
        exit 1
        ;;
esac

# Start
log "bkconf start..."

# ------------------------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------------------------

if ! mkdir -p "$backup_dir"; then
    log "ERROR: cannot create $backup_dir -- abort"
    exit 1
fi

# Project files and relevant system configuration are listed explicitly
# so the project state can be restored.
backup_list=()
for backup_item in \
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
        log "INFO: $backup_item not present -- skip"
    fi
done

if (( ${#backup_list[@]} == 0 )); then
    log "ERROR: none of the expected paths exist"
    log "ERROR: is gateproxy installed? -- abort"
    exit 1
fi

# Build under a .part name so zip always starts from nothing, and so a failed
# run can only ever delete its own work. The archive takes its final name once
# zip has succeeded, which also keeps the retention glob from seeing a partial.
backup_part="${backup_zip}.part"
rm -f "$backup_part"
if (umask 077; zip -r -q -y "$backup_part" "${backup_list[@]}"); then
    chmod 600 "$backup_part"
    if ! mv -f "$backup_part" "$backup_zip"; then
        rm -f "$backup_part"
        log "ERROR: cannot name archive $(basename "$backup_zip")"
        log "ERROR: check free space and permissions -- abort"
        exit 1
    fi
    log "INFO: backup written to $(basename "$backup_zip")"

    # keep only the last 3
    old_backups=("$backup_dir"/bkconf_*.zip)
    if (( ${#old_backups[@]} > 3 )); then
        printf '%s\n' "${old_backups[@]}" | sort | head -n -3 | xargs -r rm -f
    fi
else
    rm -f "$backup_part"
    log "ERROR: cannot write archive $(basename "$backup_zip")"
    log "ERROR: check free space and permissions -- abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "bkconf done at: $(date '+%Y-%m-%d %H:%M:%S')"
