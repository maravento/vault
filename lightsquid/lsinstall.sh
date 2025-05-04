#!/bin/bash
# maravento.com

# Lightsquid install

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
pkg='wget git tar squid apache2 ipset libnotify-bin nbtscan libcgi-session-perl libgd-gd2-perl python-is-python3'
if apt-get -qq install $pkg; then
  true
else
  echo "Error installing $pkg. Abort"
  exit
fi

### VARIABLES
ls=$(pwd)/lightsquid
scr=/etc/scr
if [ ! -d $scr ]; then mkdir -p $scr; fi &>/dev/null

echo "Lightsquid install..."

wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/lightsquid
cd $ls || exit
tar -xf lightsquid-1.8.1.tar.gz
mkdir -p /var/www/lightsquid
cp -f -R lightsquid-1.8.1/* /var/www/lightsquid/
cp -f lightsquid.conf /etc/apache2/conf-available/lightsquid.conf
chmod -R 775 /var/www/lightsquid/
chown -R www-data:www-data /var/www/lightsquid
chmod +x /var/www/lightsquid/*.{cgi,pl}
a2enmod cgid
a2enconf lightsquid
systemctl restart apache2.service

# bandata
read -p "Enter your LAN range for files (default: 192.168*): " LANRANGE
sed -i "s:192.168\*:$LANRANGE:g" bandata.sh
# change net interface
echo "Your net interfaces are:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
read -p "Enter LAN Net Interface. E.g: enpXsX): " LAN
sed -i "s/eth1/$LAN/g" bandata.sh
cp -f bandata.sh $scr/bandata.sh
chmod +x $scr/bandata.sh

# crontab
crontab -l | {
  cat
  echo "*/10 * * * * /var/www/lightsquid/lightparser.pl today"
} | crontab -
crontab -l | {
  cat
  echo "*/12 * * * * /etc/scr/bandata.sh"
} | crontab -

# end
echo "done"
echo "Lightsquid Access: http://localhost/lightsquid/index.cgi"
notify-send "LightSquid Done" "$(date)" -i checkbox
