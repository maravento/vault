#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Clean
# FILE: suricata/suricataclean.sh
#
# USAGE:
# sudo ./suricataclean.sh
#
# LOG: /var/log/suricata/suricatacron.log
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
log_file="/var/log/suricata/suricatacron.log"
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
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
for dep in systemd coreutils findutils; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "suricataclean start..."

# Clean: Suricata Logs (stop first to avoid descriptor conflicts)
systemctl stop suricata &>/dev/null
sleep 2
truncate -s 0 /var/log/suricata/eve.json
truncate -s 0 /var/log/suricata/fast.log
truncate -s 0 /var/log/suricata/stats.log
find /var/log/suricata/ -name "*.gz" -delete
log "INFO: Suricata logs cleared"
if systemctl start suricata; then
    log "INFO: Suricata started"
else
    log "WARNING: Suricata failed to start -alert"
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
# Optional: config.sqlite holds EveBox's own settings (users, saved dashboards,
# filters) -- unrelated to the events/bookmark cleanup above. Deleting it resets
# the web UI to factory defaults on every cleanup run. Left commented out until
# tested in production; uncomment only if that reset is actually desired.
# rm -f /var/lib/evebox/config.sqlite /var/lib/evebox/config.sqlite-wal /var/lib/evebox/config.sqlite-shm
rm -f /var/lib/evebox/*.bookmark
log "INFO: EveBox database cleared"
if systemctl start evebox; then
    log "INFO: EveBox started"
else
    log "WARNING: EveBox failed to start -alert"
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "suricataclean done at: $(date '+%Y-%m-%d %H:%M:%S')"
