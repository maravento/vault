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

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

LOG="/var/log/suricata/suricata-cron.log"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"
echo "$NOW - Cleaning Suricata logs and EveBox database..." | tee -a "$LOG"
# Clean: Suricata Logs (stop first to avoid descriptor conflicts)
systemctl stop suricata &>/dev/null
sleep 2
truncate -s 0 /var/log/suricata/eve.json
truncate -s 0 /var/log/suricata/fast.log
truncate -s 0 /var/log/suricata/stats.log
find /var/log/suricata/ -name "*.gz" -delete
echo "$NOW - ✓ Suricata logs cleared" | tee -a "$LOG"
if systemctl start suricata; then
    echo "$NOW - ✓ Suricata started" | tee -a "$LOG"
else
    echo "$NOW - ⚠ Warning: Failed to start Suricata" | tee -a "$LOG"
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
echo "$NOW - ✓ EveBox database cleared" | tee -a "$LOG"
if systemctl start evebox; then
    echo "$NOW - ✓ EveBox started" | tee -a "$LOG"
else
    echo "$NOW - ⚠ Warning: Failed to start EveBox" | tee -a "$LOG"
fi
