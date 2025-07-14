#!/bin/bash
# maravento.com

# Sqstat Install

# Note: &>/dev/nul is an abbreviation for >/dev/null 2>&1

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

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
pkgs='wget git tar apache2 squid libnotify-bin php php-cli libapache2-mod-php python-is-python3'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
if [ -n "$missing" ]; then
  echo "Installing: $missing"
  apt-get -qq update
  apt-get -y install $missing || {
    echo "Error installing required packages: $missing"
    exit 1
  }
fi
echo "Dependencies OK"

### VARIABLES
sq=$(pwd)/sqstat

echo "Sqstat install..."

# download
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/sqstat
cd $sq || exit

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
