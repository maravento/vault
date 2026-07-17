#!/bin/bash
# maravento.com
#
################################################################################
#
# Backup System Files
#
################################################################################

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

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    log "ERROR: Cannot determine a valid local user"
    exit 1
fi

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
case "$1" in
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
