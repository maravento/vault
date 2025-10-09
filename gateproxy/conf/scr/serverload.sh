#!/bin/bash
# maravento.com

# Server Start

echo "Server Start. Wait..."
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

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

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
