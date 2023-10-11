#!/bin/bash
# by maravento.com

# BandwidthD install

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

# check dependencies
pkg='wget git tar apache2 ipset subversion libnotify-bin libcgi-session-perl libgd-gd2-perl'
if apt-get -qq install $pkg; then
  true
else
  echo "Error installing $pkg. Abort"
  exit
fi

echo "BandwidthD install..."

# download
svn export "https://github.com/maravento/vault/trunk/bandwidthd" >/dev/null 2>&1
cd bandwidthd || exit

# install
apt -y purge bandwidthd* &>/dev/null
rm -rf /usr/sbin/bandwidthd /etc/bandwidthd /var/lib/bandwidthd /etc/init.d/bandwidthd /var/run/bandwidthd* &>/dev/null
if [ ! -d /etc/bandwidthd ]; then mkdir -p /etc/bandwidthd; fi &>/dev/null
cp -f bandwidthd.conf /etc/bandwidthd/bandwidthd.conf
DEBIAN_FRONTEND=noninteractive apt install -y bandwidthd
cp -f /etc/bandwidthd/bandwidthd.conf{,.bak} &>/dev/null

# localnet
echo
read -p "Enter IP/MASK of your LAN (default: 169.254.0.0/16): " IP_CIDR
sed -i "s:169.254.0.0/16:$IP_CIDR:g" /etc/bandwidthd/bandwidthd.conf
echo
read -p "Enter IP/MASK of your WAN (default: 192.168.0.0/24): " IP_CIDR
sed -i "s:192.168.0.0/24:$IP_CIDR:g" /etc/bandwidthd/bandwidthd.conf

# bandata
range_to_replace=$(echo "$IP_CIDR" | cut -d'/' -f1 | cut -d'.' -f1-3)
sed -i "s/169.254.0/$range_to_replace/g" bwbandata.sh
# change net interface
echo "Your net interfaces are:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
read -p "Enter LAN Net Interface. E.g: enpXsX): " LAN
sed -i "s/eth1/$LAN/g" bwbandata.sh
cp -f bw_bandata.sh /etc/init.d/bwbandata.sh
chmod +x /etc/init.d/bwbandata.sh

# apache port
sed -i '/Listen 80/a Listen 41000' /etc/apache2/ports.conf

# virtualhost
cp -f bandwidthdaudit.conf /etc/apache2/sites-available/bandwidthdaudit.conf
mkdir -p /var/www/bandwidthd
chmod -R 775 /var/www/bandwidthd/
chown -R www-data:www-data /var/www/bandwidthd
ln -s /var/lib/bandwidthd/htdocs/* /var/www/bandwidthd/
a2ensite -q bandwidthdaudit.conf
systemctl restart apache2.service

# crontab
crontab -l | {
  cat
  echo '0 0 * * * /bin/kill -HUP $(cat /var/run/bandwidthd.pid) && sleep 5 && /etc/init.d/bandwidthd restart'
} | crontab -
crontab -l | {
  cat
  echo '#@daily find "/var/lib/bandwidthd" -type f -name "log.1.*.cdf" -not -name "log.1.0.cdf" -delete && /etc/init.d/bandwidthd restart'
} | crontab -
crontab -l | {
  cat
  echo '*/15 * * * * /etc/init.d/bwbandata.sh'
} | crontab -

# End
echo "Bandwidthd Access: http://localhost/bandwidthd or http://localhost:41000/bandwidthd"
echo "done"
notify-send "Bandwidthd Done" "$(date)" -i checkbox
