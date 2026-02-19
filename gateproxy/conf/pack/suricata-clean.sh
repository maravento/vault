#!/bin/bash
LOG="/var/log/suricata/suricata-cron.log"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

echo "$NOW - Cleaning Suricata logs and EveBox database..." | tee -a "$LOG"

# Clean: Suricata Logs
truncate -s 0 /var/log/suricata/eve.json
truncate -s 0 /var/log/suricata/fast.log
truncate -s 0 /var/log/suricata/stats.log
find /var/log/suricata/ -name "*.gz" -delete
echo "$NOW - ✓ Suricata logs cleared" | tee -a "$LOG"

# Clean: EveBox DB
systemctl stop evebox
truncate -s 0 /var/lib/evebox/events.sqlite
truncate -s 0 /var/lib/evebox/config.sqlite
echo "$NOW - ✓ EveBox database cleared" | tee -a "$LOG"

if systemctl start evebox; then
    echo "$NOW - ✓ EveBox started" | tee -a "$LOG"
else
    echo "$NOW - ⚠ Warning: Failed to start EveBox" | tee -a "$LOG"
fi
