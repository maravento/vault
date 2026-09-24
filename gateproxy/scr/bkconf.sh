#!/bin/bash
# maravento.com
#
################################################################################
#
# Backup System Files
#
################################################################################

set -uo pipefail

# logging
log_file="/var/log/bkconf.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
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
for dep_pkg in zip coreutils util-linux findutils; do
    if ! dpkg -s "$dep_pkg" &>/dev/null; then
        log "ERROR: '$dep_pkg' is not installed -- abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# project backup path
bkconfig="/etc/bak/gateproxy"
mkdir -p "$bkconfig" >/dev/null 2>&1
chmod 700 "$bkconfig"

log "bkconf start..."

# ------------------------------------------------------------------------------
# BACKUP
# ------------------------------------------------------------------------------

zipbk="backup_$(date +%Y%m%d_%H%M).zip"
# Build pathbk as array, skipping non-existent paths
pathbk=()
for p in \
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
    if [ -e "$p" ]; then
        pathbk+=("$p")
    else
        log "WARNING: $p not found -- skip"
    fi
done
case "${1:-}" in
'start')
    log "INFO: Start Backup Config Files..."
    if zip -r "$bkconfig/$zipbk" "${pathbk[@]}" >/dev/null; then
        log "INFO: Backup Config: $bkconfig/$zipbk"
        old_backups=("$bkconfig"/backup_*.zip)
        if (( ${#old_backups[@]} > 3 )); then
            printf '%s\n' "${old_backups[@]}" | sort | head -n -3 | xargs -r rm -f
        fi
    else
        log "ERROR: backup failed -- abort"
        exit 1
    fi
    ;;
'stop') ;;
*)
    log "INFO: Usage: $0 { start | stop }"
    ;;
esac

log "bkconf done at: $(date '+%Y-%m-%d %H:%M:%S')"
