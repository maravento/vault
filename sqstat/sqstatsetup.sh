#!/usr/bin/env bash
# by maravento.com

# Sqstat Install

# Note: &>/dev/nul is an abbreviation for >/dev/null 2>&1

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
pkg='wget git tar apache2 squid subversion libnotify-bin php php-cli libapache2-mod-php'
if apt-get -qq install $pkg; then
    echo "OK"
else
    echo "Error installing $pkg. Abort"
    exit
fi

# download
svn export "https://github.com/maravento/vault/trunk/sqstat" >/dev/null 2>&1
cd sqstat

# install
tar -xf sqstat-1.20.tar.gz
mkdir -p /var/www/sqstat
cp -f -R sqstat-1.20/* /var/www/sqstat/
chmod -R 775 /var/www/sqstat/
chown -R www-data:www-data /var/www/sqstat
cp -f sqstat.conf /etc/apache2/conf-available/sqstat.conf
a2enconf -q sqstat
systemctl restart apache2.service

# End
echo Done
notify-send "Sqstat Done" "$(date)" -i checkbox
