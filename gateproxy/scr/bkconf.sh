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
log_file="/var/log/bkconfig.log"
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
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep in zip coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -- abort"
        exit 1
    fi
done

# VARIABLES
# project backup path
bkconfig="/etc/bak/gateproxy"
mkdir -p "$bkconfig" >/dev/null 2>&1
chmod 700 "$bkconfig"

log "bkconfig start..."

# BACKUP
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
    /var/spool/cron/crontabs \
    /etc/logrotate.d/rsyslog \
    /etc/sarg
do
    if [ -e "$p" ]; then
        pathbk+=("$p")
    else
        log "WARNING: $p not found, skipping"
    fi
done
case "${1:-}" in
'start')
    log "Start Backup Config Files..."
    if zip -r "$bkconfig/$zipbk" "${pathbk[@]}" >/dev/null; then
        log "Backup Config: $bkconfig/$zipbk"
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
    log "Usage: $0 { start | stop }"
    ;;
esac

log "bkconfig done at: $(date)"
