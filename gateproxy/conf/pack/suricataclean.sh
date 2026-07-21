#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Clean
#
################################################################################

set -uo pipefail

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
# Clean: EveBox DB. Deleting the files outright (instead of DELETE FROM
# events; VACUUM;) also clears EveBox's eve.json read bookmark. The bookmark
# itself lives in a separate *.bookmark file (not in the sqlite databases),
# named after a hash of the eve.json path -- it must be removed too, or it
# survives pointing past the size of the freshly truncated eve.json above,
# and EveBox gets stuck ("Invalid bookmark found: current file size less
# than bookmark") and stops ingesting new events. EveBox is already stopped
# below, and it recreates the schema/indexes/bookmark on next start.
systemctl stop evebox &>/dev/null
rm -f /var/lib/evebox/events.sqlite /var/lib/evebox/events.sqlite-wal /var/lib/evebox/events.sqlite-shm
rm -f /var/lib/evebox/config.sqlite /var/lib/evebox/config.sqlite-wal /var/lib/evebox/config.sqlite-shm
rm -f /var/lib/evebox/*.bookmark
log "EveBox database cleared"
if systemctl start evebox; then
    log "EveBox started"
else
    log "Warning: Failed to start EveBox"
fi

log "suricataclean done at: $(date)"
