#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Clean
#
################################################################################

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/suricata/suricatacron.log"
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

log "suricataclean start.."

# Clean: Suricata Logs (stop first to avoid descriptor conflicts)
systemctl stop suricata &>/dev/null
sleep 2
truncate -s 0 /var/log/suricata/eve.json
truncate -s 0 /var/log/suricata/fast.log
truncate -s 0 /var/log/suricata/stats.log
find /var/log/suricata/ -name "*.gz" -delete
log "Suricata logs cleared"
if systemctl start suricata; then
    log "Suricata started"
else
    log "Warning: Failed to start Suricata"
fi
# Clean: EveBox DB (use sqlite3 to avoid WAL/SHM corruption)
systemctl stop evebox &>/dev/null
if command -v sqlite3 &>/dev/null; then
    sqlite3 /var/lib/evebox/events.sqlite "DELETE FROM events; VACUUM;" 2>/dev/null || \
        truncate -s 0 /var/lib/evebox/events.sqlite
    sqlite3 /var/lib/evebox/config.sqlite "VACUUM;" 2>/dev/null || \
        truncate -s 0 /var/lib/evebox/config.sqlite
else
    truncate -s 0 /var/lib/evebox/events.sqlite
    truncate -s 0 /var/lib/evebox/config.sqlite
fi
log "EveBox database cleared"
if systemctl start evebox; then
    log "EveBox started"
else
    log "Warning: Failed to start EveBox"
fi

log "suricataclean done at: $(date)"
