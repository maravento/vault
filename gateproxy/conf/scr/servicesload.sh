#!/bin/bash
# maravento.com
#
################################################################################
#
# Check Services
#
################################################################################
echo "Check Services Start. Wait..."
printf "\n"

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

## VARIABLES
sleep_time="5"

### CHECK SERVICES
# Webmin service
if systemctl is-active --quiet webmin.service; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl stop webmin.service &>/dev/null
    sleep "${sleep_time}"
    /etc/webmin/restart-by-force-kill
    echo "Webmin start: $(date)" | tee -a /var/log/syslog
fi
# PyDHCP service
if systemctl is-active --quiet pydhcp.service; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl start pydhcp
    echo "DHCP start: $(date)" | tee -a /var/log/pydhcpd.log
fi
# Apache2 service
if systemctl is-active --quiet apache2.service; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl stop apache2.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start apache2.service
    echo "Apache2 start: $(date)" | tee -a /var/log/syslog
fi
# Squid Service
if systemctl is-active --quiet squid.service; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl stop squid.service &>/dev/null
    rm -f /run/squid.pid &>/dev/null
    sleep "${sleep_time}"
    systemctl start squid.service
    echo "Squid start: $(date)" | tee -a /var/log/syslog
fi
# rsyslog
if systemctl is-active --quiet rsyslog.service; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start syslog.socket rsyslog.service
    echo "Rsyslog start: $(date)" | tee -a /var/log/syslog
fi
