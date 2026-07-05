#!/bin/bash
# maravento.com
#
################################################################################
#
# smbstack - Service Watchdog
# https://github.com/maravento/vault/smbstack
#
# NOTE on logging:
# - Writes to /var/log/smbload.log (append-only, no rotation configured by
#   this script). Set up logrotate for this file if disk usage matters.
# - To clear it manually: truncate -s 0 /var/log/smbload.log
#
################################################################################

# logging
log_file="/var/log/smbload.log"
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

# Start
log "smbload start..."

# Samba Service (smbd)
if pgrep -x smbd > /dev/null; then
    log "smbd: ONLINE"
else
    systemctl stop smbd.service &>/dev/null
    if systemctl start smbd.service; then
        log "smbd start"
    else
        log "smbd start FAILED"
    fi
fi

# Samba Service (winbind)
if pgrep -x winbindd > /dev/null; then
    log "winbind: ONLINE"
else
    systemctl stop winbind.service &>/dev/null
    if systemctl start winbind.service; then
        log "winbind start"
    else
        log "winbind start FAILED"
    fi
fi

# End
log "smbload done at: $(date)"
