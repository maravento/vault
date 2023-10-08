#!/bin/bash
# by maravento.com

# Check Services

echo "Check Services Start. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

### VARIABLES
sleep_time="5"

### CHECK SERVICES
# Webmin service
if [[ $(ps -A | grep miniserv.pl) != "" ]]; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "miniserv.pl" | awk '{print $2}'); do kill -9 $pid &>/dev/null; done
    sleep ${sleep_time}
    systemctl start webmin.service
    echo "Webmin start: $(date)" | tee -a /var/log/syslog
fi
# DHCP service
if [[ $(ps -A | grep dhcpd) != "" ]]; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    /etc/scr/leases.sh
    echo "DHCP start: $(date)" | tee -a /var/log/syslog
fi
# Apache2 service
if [[ $(ps -A | grep apache2) != "" ]]; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "apache2" | awk '{print $2}'); do kill -9 $pid &>/dev/null; done
    sleep ${sleep_time}
    systemctl start apache2.service
    echo "Apache2 start: $(date)" | tee -a /var/log/syslog
fi
# Squid Service
if [[ $(ps -A | grep squid) != "" ]]; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "squid" | awk '{print $2}'); do kill -9 $pid &>/dev/null; done
    sleep ${sleep_time}
    /etc/init.d/squid start
    echo "Squid start: $(date)" | tee -a /var/log/syslog
fi
# rsyslog
if [[ $(ps -A | grep rsyslogd) != "" ]]; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl stop syslog.socket rsyslog.service &>/dev/null
    sleep ${sleep_time}
    systemctl start rsyslog.service
    echo "Rsyslog start: $(date)" | tee -a /var/log/syslog
fi
echo "Done"
