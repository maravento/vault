#!/bin/bash
# maravento.com

# Check Services

echo "Check Services Start. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

## VARIABLES
sleep_time="5"

### CHECK SERVICES

# Webmin service
if pgrep -f "miniserv.pl" > /dev/null; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "[m]iniserv.pl" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    /etc/webmin/restart-by-force-kill
    echo "Webmin start: $(date)" | tee -a /var/log/syslog
fi

# DHCP service
if pgrep -f "dhcpd" > /dev/null; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    /etc/scr/leases.sh
    echo "DHCP start: $(date)" | tee -a /var/log/syslog
fi

# Apache2 service
if pgrep -f "apache2" > /dev/null; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "[a]pache2" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    systemctl start apache2.service
    echo "Apache2 start: $(date)" | tee -a /var/log/syslog
fi

# Squid Service
if pgrep -f "squid" > /dev/null; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "[s]quid" | awk '{print $2}'); do
        kill -9 "$pid" &>/dev/null
    done
    sleep "${sleep_time}"
    systemctl start squid.service
    echo "Squid start: $(date)" | tee -a /var/log/syslog
fi

# rsyslog
if pgrep -f "rsyslogd" > /dev/null; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep "${sleep_time}"
    systemctl start syslog.socket rsyslog.service
    echo "Rsyslog start: $(date)" | tee -a /var/log/syslog
fi
