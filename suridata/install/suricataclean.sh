#!/bin/bash
# maravento.com
#
################################################################################
#
# Suricata Clean
# FILE: suricataclean.sh
#
# USAGE:
# sudo bash suricataclean.sh
#
# LOG: /var/log/suridata.log
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
log_file="/var/log/suridata.log"
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
    log "ERROR: cannot open $(basename "$script_lock") -abort"
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# suridata offset lock
# suridata.sh reads eve.json by saved offset. Truncating the file while it
# runs lets it write the old offset back afterwards, so its lock is taken
# here too and held until this script ends.
suridata_lock="/var/lock/suridata.lock"
(umask 077; : >> "$suridata_lock") || {
    log "ERROR: cannot open $(basename "$suridata_lock") -abort"
    exit 1
}
exec 201>"$suridata_lock"
if ! flock -w 600 201; then
    log "ERROR: suridata.sh still running after 600s -abort"
    exit 1
fi

# maintenance lock
maintenance_lock="/var/lock/suricata-maintenance.lock"
(umask 077; : >> "$maintenance_lock") || { log "ERROR: cannot open maintenance lock -abort"; exit 1; }
exec 202>"$maintenance_lock" || { log "ERROR: cannot open maintenance lock -abort"; exit 1; }
if ! flock -w 600 202; then
    log "ERROR: another maintenance task is still running -abort"
    exit 1
fi

# dependencies
for dep in suricata systemd coreutils findutils util-linux grep; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q 'ok installed'; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# dependencies (external repo)
for dep in evebox; do
    if ! dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep -q 'ok installed'; then
        log "ERROR: missing dependency '$dep' -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

log "EVENT: suricataclean start..."

for service in suricata evebox; do
    if ! systemctl stop "$service"; then
        log "ERROR: cannot stop $service -abort"
        exit 1
    fi
    service_state=$(systemctl show "$service" --property=ActiveState --value) || {
        log "ERROR: cannot check $service state -abort"
        exit 1
    }
    case "$service_state" in
        inactive|failed) ;;
        *) log "ERROR: $service is not stopped -abort"; exit 1 ;;
    esac
done

logs_cleared=1
truncate -s 0 /var/log/suricata/eve.json || {
    log "WARNING: cannot clear eve.json -alert"
    logs_cleared=0
}
rm -f /var/lib/suricata/suridata.offset || {
    log "WARNING: cannot remove suridata.offset -alert"
    logs_cleared=0
}
truncate -s 0 /var/log/suricata/fast.log || {
    log "WARNING: cannot clear fast.log -alert"
    logs_cleared=0
}
truncate -s 0 /var/log/suricata/stats.log || {
    log "WARNING: cannot clear stats.log -alert"
    logs_cleared=0
}
find /var/log/suricata/ -name "*.gz" -delete || {
    log "WARNING: cannot remove compressed Suricata logs -alert"
    logs_cleared=0
}
if (( logs_cleared )); then
    log "INFO: Suricata logs cleared"
fi
evebox_cleared=1
rm -f /var/lib/evebox/events.sqlite /var/lib/evebox/events.sqlite-wal /var/lib/evebox/events.sqlite-shm || {
    log "WARNING: cannot remove EveBox event database files -alert"
    evebox_cleared=0
}
rm -f /var/lib/evebox/*.bookmark || {
    log "WARNING: cannot remove EveBox bookmark files -alert"
    evebox_cleared=0
}
if (( evebox_cleared )); then
    log "INFO: EveBox database cleared"
fi

for service in suricata evebox; do
    if systemctl start "$service"; then
        if ! systemctl is-active --quiet "$service"; then
            log "ERROR: $service not active after start -abort"
            exit 1
        fi
        log "INFO: $service started"
    else
        log "ERROR: $service failed to start -abort"
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "EVENT: suricataclean done"
