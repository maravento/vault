#!/bin/bash
# maravento.com
#
################################################################################
#
# Services Watchdog
#
# NOTE on logging:
# - Writes to /var/log/serviceswatch.log (own log, not shared).
#
################################################################################

set -uo pipefail

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/serviceswatch.log"
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
for dep in procps systemd apache2 squid-openssl rsyslog util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -- abort"
        exit 1
    fi
done

# dependencies (external repo)
for dep in webmin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -- abort"
        exit 1
    fi
done

# Start
log "serviceswatch start..."

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

sleep_time="5"

# ------------------------------------------------------------------------------
# SERVICES
# ------------------------------------------------------------------------------

# Webmin service
if pgrep -x miniserv.pl > /dev/null; then
    log "INFO: Webmin ONLINE"
else
    for pid in $(ps -ef | grep "[m]iniserv.pl" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    /etc/webmin/restart-by-force-kill
    log "FIX: Webmin restarted"
fi

# Apache2 service
if pgrep -x apache2 > /dev/null; then
    log "INFO: apache2 ONLINE"
else
    for pid in $(ps -ef | grep "[a]pache2" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    systemctl start apache2.service
    log "FIX: apache2 restarted"
fi

# Squid Service
if pgrep -x squid > /dev/null; then
    log "INFO: squid ONLINE"
else
    for pid in $(ps -ef | grep "[s]quid" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
        rm -f /run/squid.pid &>/dev/null
    done
    sleep "${sleep_time}"
    systemctl start squid.service
    log "FIX: squid restarted"
fi

# rsyslog
if pgrep -x rsyslogd > /dev/null; then
    log "INFO: rsyslog ONLINE"
else
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start syslog.socket rsyslog.service
    log "FIX: rsyslog restarted"
fi

# End
log "serviceswatch done at: $(date '+%Y-%m-%d %H:%M:%S')"
