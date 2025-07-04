#!/bin/bash
# maravento.com

# Lightsquid install

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
pkgs='wget git tar squid apache2 ipset libnotify-bin nbtscan libcgi-session-perl libgd-perl python-is-python3'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "❌ Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "💡 Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    echo "🔧 Releasing APT/DKPG locks..."
    killall -q apt apt-get dpkg 2>/dev/null
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    echo "📦 Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "❌ Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi

### VARIABLES
SCRIPT_PATH="$(realpath "$0")"
ls=$(pwd)/lightsquid

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

# crontab
crontab -l | {
  cat
  echo "*/10 * * * * /var/www/lightsquid/lightparser.pl today"
} | crontab -

# end
echo "done"
echo "Lightsquid Access: http://localhost/lightsquid/index.cgi"
notify-send "LightSquid Done" "$(date)" -i checkbox

[ -d "$ls" ] && rm -rf "$ls"
(sleep 2 && rm -- "$SCRIPT_PATH") &
