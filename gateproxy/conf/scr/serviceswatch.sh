#!/bin/bash
# maravento.com

# Services Watchdog

echo "Check Services Start. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Prevent overlapping runs
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

# PyDHCP service
if pgrep -f "pydhcpd" > /dev/null; then
    echo -e "\nONLINE"
else
    echo -e "\n"
    systemctl start pydhcpd.service
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
        rm -f /run/squid.pid &>/dev/null
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
# Samba Service (smbd)
if [[ `ps -A | grep smbd` != "" ]];then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "smbd" | awk '{print $2}'); do kill -9 $pid &> /dev/null; done
    sleep ${sleep_time}
    systemctl start smbd.service
    # alternative:
    #/etc/init.d/smbd start
    echo "Samba (smbd) start: $(date)" | tee -a /var/log/syslog
fi
# Samba Service (winbind)
if [[ `ps -A | grep winbindd` != "" ]];then
    echo -e "\nONLINE"
else
    echo -e "\n"
    for pid in $(ps -ef | grep "winbindd" | awk '{print $2}'); do kill -9 $pid &> /dev/null; done
    sleep ${sleep_time}
    systemctl start winbind.service
    # alternative:
    #/etc/init.d/winbind start
    echo "Samba (winbind) start: $(date)" | tee -a /var/log/syslog
fi

# UOS Server Watchdog
if systemctl is-active --quiet uosserver.service; then

    pid=$(pgrep -f "uosserver-service")

    if [ -z "$pid" ]; then
        echo -e "\nBROKEN_NO_PROCESS"
        systemctl restart uosserver.service
        echo "UOS FIX (no process): $(date)" | tee -a /var/log/syslog
        exit
    fi

    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo -e "\nBROKEN_DEAD_PID"
        systemctl restart uosserver.service
        echo "UOS FIX (dead pid): $(date)" | tee -a /var/log/syslog
        exit
    fi

    # 3. check Mongo (dependencia real)
    if ! ss -lnt | grep -q ":27017"; then
        echo -e "\nBROKEN_MONGO"
        systemctl restart mongod.service 2>/dev/null
        systemctl restart uosserver.service
        echo "UOS FIX (mongo): $(date)" | tee -a /var/log/syslog
        exit
    fi

    echo -e "\nONLINE"

else
    echo -e "\nOFFLINE"
    systemctl start uosserver.service
    echo "UOS START: $(date)" | tee -a /var/log/syslog
fi
