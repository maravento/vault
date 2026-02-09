#!/bin/bash
# maravento.com

# Server Start

echo "Server Start. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
# Fallback
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi

sleep_time="5"

### SERVERS
echo "DHCP & Iptables..."
eval "sudo "/etc/scr/{leases,iptables}.sh";"
echo "Squid Reload..."
systemctl reload squid.service
echo "Apache2 Restart..."
systemctl restart apache2.service
echo "Samba Restart..."
systemctl restart smbd.service
echo "Netbios Restart..."
systemctl restart nmbd.service
echo "Winbind Reload..."
systemctl restart winbind.service
echo "Rsyslog Reload..."
systemctl restart syslog.socket rsyslog.service
echo "Server Load: $(date)" | tee -a /var/log/syslog
sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus notify-send "Server Load" "$(date)" -i checkbox
echo "Done"
