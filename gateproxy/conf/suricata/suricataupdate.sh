#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Update
#
################################################################################

set -uo pipefail

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/suricata/suricatacron.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep in suricata suricata-update systemd; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -- abort"
        exit 1
    fi
done

# dependencies (external repo)
for dep in evebox; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -- abort"
        exit 1
    fi
done

# check internet
check_internet() {
    local max_attempts="${1:-24}" attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            log "INFO: internet is available"
            return 0
        fi
        log "INFO: waiting for internet ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 5
    done

    return 1
}

log "suricataupdate start..."

if ! check_internet; then
    log "ERROR: no internet connection -- abort"
    exit 1
fi

if suricata-update --disable-conf=/etc/suricata/disable.conf \
                  --drop-conf=/etc/suricata/drop.conf \
                  --quiet >> "$log_file" 2>&1; then
    rules_file="/var/lib/suricata/rules/suricata.rules"

    # not-suspicious rules
    #sed -i '/classtype:not-suspicious;/d' "$rules_file"

    if systemctl restart suricata; then
        sleep 3
        if ! systemctl is-active --quiet suricata; then
            log "ERROR: Suricata not active after reload -- abort"
            exit 1
        fi
        active_rules=$(grep -c '^alert' "$rules_file" 2>/dev/null); [ -z "$active_rules" ] && active_rules="N/A"
        log "INFO: Suricata reloaded, active rules: $active_rules"
        if systemctl restart evebox; then
            log "INFO: EveBox restarted"
        else
            log "WARNING: EveBox failed to restart -- alert"
        fi
    else
        log "ERROR: failed to reload Suricata -- abort"
        exit 1
    fi
else
    log "ERROR: suricata-update failed -- abort"
    exit 1
fi

log "suricataupdate done at: $(date '+%Y-%m-%d %H:%M:%S')"
