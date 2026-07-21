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

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    log "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
log "Using local user: $local_user"

### VARIABLES
# path to cloud
bkconfig="/home/$local_user/bkconf"
mkdir -p "$bkconfig" >/dev/null 2>&1

log "bkconfig start..."

### BACKUP
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
    else
        log "ERROR: Backup Config failed"
        exit 1
    fi
    ;;
'stop') ;;
*)
    log "Usage: $0 { start | stop }"
    ;;
esac

log "bkconfig done at: $(date)"
