#!/bin/bash
# maravento.com
#
################################################################################
#
# Services Watchdog
# FILE: scr/serviceswatch.sh
#
# USAGE:
# ./serviceswatch.sh
#
# LOG: /var/log/serviceswatch.log, its own log, not shared
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
log_file="/var/log/serviceswatch.log"
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
for dep in procps systemd apache2 squid-openssl rsyslog util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# dependencies (external repo)
for dep in webmin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: missing dependency '$dep' -abort"
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
    pkill -9 -x miniserv.pl &>/dev/null || true
    sleep "${sleep_time}"
    /etc/webmin/restart-by-force-kill
    log "INFO: Webmin restarted -fixed"
fi

# Apache2 service
if pgrep -x apache2 > /dev/null; then
    log "INFO: apache2 ONLINE"
else
    pkill -9 -x apache2 &>/dev/null || true
    sleep "${sleep_time}"
    systemctl start apache2.service
    log "INFO: apache2 restarted -fixed"
fi

# Squid Service
if pgrep -x squid > /dev/null; then
    log "INFO: squid ONLINE"
else
    pkill -9 -x squid &>/dev/null || true
    rm -f /run/squid.pid &>/dev/null
    sleep "${sleep_time}"
    systemctl start squid.service
    log "INFO: squid restarted -fixed"
fi

# rsyslog
if pgrep -x rsyslogd > /dev/null; then
    log "INFO: rsyslog ONLINE"
else
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start syslog.socket rsyslog.service
    log "INFO: rsyslog restarted -fixed"
fi

# End
log "serviceswatch done at: $(date '+%Y-%m-%d %H:%M:%S')"
