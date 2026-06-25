#!/bin/bash
# maravento.com

# Server Boot Load

echo "Server Start. Wait..."
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

### SERVERS
echo "DHCP..."
systemctl reload pydhcpd.service
echo "Squid Reload..."
systemctl reload squid.service
echo "Apache2 Restart..."
systemctl restart apache2.service
echo "Samba Restart..."
systemctl restart smbd.service
echo "Winbind Reload..."
systemctl restart winbind.service
echo "Rsyslog Reload..."
systemctl restart syslog.socket rsyslog.service
echo "Server Load: $(date)" | tee -a /var/log/syslog
echo "Done"
