#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Update
# FILE: suricata/suricataupdate.sh
#
# USAGE:
# sudo ./suricataupdate.sh
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
for dep in suricata suricata-update systemd; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# dependencies (external repo)
for dep in evebox; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -abort"
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

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "suricataupdate start..."

if ! check_internet; then
    log "ERROR: no internet connection -abort"
    exit 1
fi

if suricata-update --disable-conf=/etc/suricata/disable.conf \
                  --drop-conf=/etc/suricata/drop.conf \
                  --quiet >> "$log_file" 2>&1; then
    rules_file="/var/lib/suricata/rules/suricata.rules"

    if systemctl restart suricata; then
        sleep 3
        if ! systemctl is-active --quiet suricata; then
            log "ERROR: Suricata not active after reload -abort"
            exit 1
        fi
        active_rules=$(grep -c '^alert' "$rules_file" 2>/dev/null); [ -z "$active_rules" ] && active_rules="N/A"
        log "INFO: Suricata reloaded, active rules: $active_rules"
        if systemctl restart evebox; then
            log "INFO: EveBox restarted"
        else
            log "WARNING: EveBox failed to restart -alert"
        fi
    else
        log "ERROR: failed to reload Suricata -abort"
        exit 1
    fi
else
    log "ERROR: suricata-update failed -abort"
    exit 1
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "suricataupdate done at: $(date '+%Y-%m-%d %H:%M:%S')"
