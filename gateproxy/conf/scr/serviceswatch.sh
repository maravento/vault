#!/bin/bash
# maravento.com
#
################################################################################
#
# Services Watchdog
#
################################################################################

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

log "serviceswatch start.."

## VARIABLES
sleep_time="5"

### CHECK SERVICES

# Webmin service
if pgrep -f "miniserv.pl" > /dev/null; then
    log "ONLINE: Webmin"
else
    for pid in $(ps -ef | grep "[m]iniserv.pl" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    /etc/webmin/restart-by-force-kill
    log "Webmin start"
fi

# PyDHCP service
if pgrep -f "pydhcpd" > /dev/null; then
    log "ONLINE: PyDHCP"
else
    systemctl start pydhcpd.service
    log "PyDHCP start"
fi

# Apache2 service
if pgrep -f "apache2" > /dev/null; then
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
if pgrep -f "squid" > /dev/null; then
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
if pgrep -f "rsyslogd" > /dev/null; then
    log "ONLINE: rsyslog"
else
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start syslog.socket rsyslog.service
    log "Rsyslog start"
fi
# Samba Service (smbd)
if pgrep -x smbd > /dev/null; then
    log "ONLINE: smbd"
else
    for pid in $(pgrep smbd); do kill -9 "$pid" &>/dev/null; done
    sleep "${sleep_time}"
    systemctl start smbd.service
    # alternative:
    #/etc/init.d/smbd start
    log "Samba (smbd) start"
fi
# Samba Service (winbind)
if pgrep -x winbindd > /dev/null; then
    log "ONLINE: winbind"
else
    for pid in $(pgrep winbindd); do kill -9 "$pid" &>/dev/null; done
    sleep "${sleep_time}"
    systemctl start winbind.service
    # alternative:
    #/etc/init.d/winbind start
    log "Samba (winbind) start"
fi

log "serviceswatch done at: $(date)"
