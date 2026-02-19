#!/bin/bash
LOG="/var/log/suricata/suricata-cron.log"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"
echo "$NOW - Suricata Update..." | tee -a "$LOG"
suricata-update --disable-conf=/etc/suricata/disable.conf --quiet >> "$LOG" 2>&1
if [ $? -eq 0 ]; then
    RULES_FILE="/var/lib/suricata/rules/suricata.rules"
    
    # not-suspicious rules
    #sed -i '/classtype:not-suspicious;/d' "$RULES_FILE"
    
    if systemctl reload suricata; then
        ACTIVE_RULES=$(grep -c '^alert' "$RULES_FILE" 2>/dev/null || echo "N/A")
        echo "$NOW - ✓ Suricata reloaded - Active rules: $ACTIVE_RULES" | tee -a "$LOG"

        if systemctl restart evebox; then
            echo "$NOW - ✓ EveBox restarted" | tee -a "$LOG"
        else
            echo "$NOW - ⚠ Warning: Failed to restart EveBox" | tee -a "$LOG"
        fi
    else
        echo "$NOW - ✗ Failed to reload Suricata" | tee -a "$LOG"
        exit 1
    fi
else
    echo "$NOW - ✗ Error suricata-update" | tee -a "$LOG"
    exit 1
fi
