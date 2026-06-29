#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Update
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
echo "$NOW - Suricata Update..." | tee -a "$LOG"
if suricata-update --disable-conf=/etc/suricata/disable.conf \
                   --drop-conf=/etc/suricata/drop.conf \
                   --quiet >> "$LOG" 2>&1; then
    RULES_FILE="/var/lib/suricata/rules/suricata.rules"

    # not-suspicious rules
    #sed -i '/classtype:not-suspicious;/d' "$RULES_FILE"

    if systemctl restart suricata; then
        sleep 3
        if ! systemctl is-active --quiet suricata; then
            echo "$NOW - ✗ Suricata not active after reload" | tee -a "$LOG"
            exit 1
        fi
        ACTIVE_RULES=$(grep -c '^alert' "$RULES_FILE" 2>/dev/null); [ -z "$ACTIVE_RULES" ] && ACTIVE_RULES="N/A"
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
