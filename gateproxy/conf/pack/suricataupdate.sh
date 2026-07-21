#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Update
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

log "suricataupdate start.."

if suricata-update --disable-conf=/etc/suricata/disable.conf \
                  --drop-conf=/etc/suricata/drop.conf \
                  --quiet >> "$log_file" 2>&1; then
    RULES_FILE="/var/lib/suricata/rules/suricata.rules"

    # not-suspicious rules
    #sed -i '/classtype:not-suspicious;/d' "$RULES_FILE"

    if systemctl restart suricata; then
        sleep 3
        if ! systemctl is-active --quiet suricata; then
            log "Suricata not active after reload"
            exit 1
        fi
        ACTIVE_RULES=$(grep -c '^alert' "$RULES_FILE" 2>/dev/null); [ -z "$ACTIVE_RULES" ] && ACTIVE_RULES="N/A"
        log "Suricata reloaded - Active rules: $ACTIVE_RULES"
        if systemctl restart evebox; then
            log "EveBox restarted"
        else
            log "Warning: Failed to restart EveBox"
        fi
    else
        log "Failed to reload Suricata"
        exit 1
    fi
else
    log "Error suricata-update"
    exit 1
fi

log "suricataupdate done at: $(date)"
