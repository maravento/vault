#!/bin/bash
# maravento.com
#
################################################################################
#
# Services Watchdog
#
# NOTE on logging:
# - Writes to /var/log/serviceswatch.log (shared with conf/scr/serviceswatch.sh).
#
################################################################################

set -uo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# logging
log_file="/var/log/serviceswatch.log"
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

# Start
log "serviceswatch start..."

## VARIABLES
sleep_time="5"

### CHECK SERVICES

# Webmin service
if pgrep -x miniserv.pl > /dev/null; then
    log "ONLINE: Webmin"
else
    for pid in $(ps -ef | grep "[m]iniserv.pl" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    /etc/webmin/restart-by-force-kill
    log "Webmin start"
fi

# Apache2 service
if pgrep -x apache2 > /dev/null; then
    log "ONLINE: apache2"
else
    for pid in $(ps -ef | grep "[a]pache2" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    systemctl start apache2.service
    log "Apache2 start"
fi

# Squid Service
if pgrep -x squid > /dev/null; then
    log "ONLINE: squid"
else
    for pid in $(ps -ef | grep "[s]quid" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
        rm -f /run/squid.pid &>/dev/null
    done
    sleep "${sleep_time}"
    systemctl start squid.service
    log "Squid start"
fi

# rsyslog
if pgrep -x rsyslogd > /dev/null; then
    log "ONLINE: rsyslog"
else
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start syslog.socket rsyslog.service
    log "Rsyslog start"
fi

# End
log "serviceswatch done at: $(date)"
