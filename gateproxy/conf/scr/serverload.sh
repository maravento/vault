#!/bin/bash
# by maravento.com

# Server Start

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
# checking dependencies (optional)
pkg='notify-osd libnotify-bin'
if apt-get -qq install $pkg; then
    echo "OK"
else
    echo "Error installing $pkg. Abort"
    exit
fi

# LOCAL USER
local_user=${SUDO_USER:-$(whoami)}

sleep_time="5"

echo "DHCP & Iptables..."
eval "sudo "/etc/scr/{leases,iptables}.sh";"
echo "OK"
echo "Squid Reload..."
systemctl reload-or-restart squid.service
echo "OK"
echo "Apache2 Reload..."
systemctl reload-or-restart apache2.service
echo "OK"
echo "Samba Reload..."
systemctl reload-or-restart smbd.service
echo "OK"
echo "Netbios Reload..."
systemctl reload-or-restart nmbd.service
echo "OK"
echo "Winbind Reload..."
systemctl reload-or-restart winbind.service
echo "OK"
echo "Rsyslog Reload..."
systemctl reload-or-restart rsyslog.service
echo "OK"
echo "Server Load: $(date)" | tee -a /var/log/syslog
sudo -u $local_user DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $local_user)/bus notify-send "Server Load" "$(date)" -i checkbox
echo Done
