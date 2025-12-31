#!/bin/bash
LOG="/var/log/suricata/suricata-update.log"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

echo "$NOW - Suricata Update..." | tee -a "$LOG"
suricata-update --disable-conf=/etc/suricata/disable.conf --quiet >> "$LOG" 2>&1

if [ $? -eq 0 ]; then
    RULES_FILE="/var/lib/suricata/rules/suricata.rules"
    
    # Reload Suricata with new rules
    if systemctl reload suricata; then
        sleep 2 
        ACTIVE_RULES=$(grep -c '^alert' "$RULES_FILE" 2>/dev/null || echo "N/A")
        echo "$NOW - ✓ Suricata reloaded - Active rules: $ACTIVE_RULES" | tee -a "$LOG"
    else
        echo "$NOW - ✗ Failed to reload Suricata" | tee -a "$LOG"
        exit 1
    fi
    
    # Delete evebox database (optional) - AFTER Suricata reload
    #systemctl stop evebox
    #rm -f /var/lib/evebox/events.sqlite /var/lib/evebox/events.sqlite-wal /var/lib/evebox/events.sqlite-shm
    #systemctl start evebox
    # Check with
    #lsof -c evebox | grep -E '\.(db|sqlite)'
    
    # Restart EveBox
    if systemctl restart evebox; then
        echo "$NOW - ✓ EveBox restarted" | tee -a "$LOG"
    else
        echo "$NOW - ⚠ Warning: Failed to restart EveBox" | tee -a "$LOG"
    fi
else
    echo "$NOW - ✗ Error suricata-update" | tee -a "$LOG"
    exit 1
fi
