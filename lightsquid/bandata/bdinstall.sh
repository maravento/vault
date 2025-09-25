#!/bin/bash
# maravento.com

# Bandata Install
# https://www.maravento.com/2022/10/lightsquid.html
# https://www.maravento.com/2025/06/https-302.html

echo "Bandata Install. Wait..."
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

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
pkgs='ipset apache2 libnotify-bin coreutils'
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
scr=/etc/scr
mkdir -p "$scr" >/dev/null 2>&1

# bandata
wget -q https://raw.githubusercontent.com/maravento/vault/master/lightsquid/bandata/bandata.sh -O $scr/bandata.sh
chmod +x $scr/bandata.sh

# install dependencies
mkdir -p /var/www/html/warning
chown -R www-data:www-data /var/www/html/warning
tee /var/www/html/warning/warning.html >/dev/null << EOL
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Restricted Access</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  
  <style>
    body {
      background: #f2f5f8;
      font-family: "Segoe UI", Tahoma, sans-serif;
      display: flex;
      justify-content: center;
      align-items: center;
      height: 100vh;
      margin: 0;
    }

    .container {
      background: white;
      padding: 40px;
      border-radius: 10px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
      text-align: center;
      max-width: 400px;
      width: 90%;
    }

    .container img {
      width: 80px;
      margin-bottom: 20px;
    }

    h1 {
      color: #333;
      margin-bottom: 10px;
    }

    p {
      color: #666;
      margin-bottom: 30px;
    }

    .quota {
      text-align: left;
      background: #f9fafc;
      border: 1px solid #ddd;
      padding: 15px;
      border-radius: 6px;
      font-size: 14px;
    }

    .quota li {
      margin-bottom: 8px;
    }

    .footer {
      font-size: 12px;
      color: #aaa;
      margin-top: 30px;
    }
  </style>
</head>
<body>
  <p style="display: none;">Success</p>
  <div class="container">

    <svg width="80" height="80" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
      <path d="M50 10 L90 80 L10 80 Z" fill="none" stroke="#e53e3e" stroke-width="6" stroke-linejoin="round"/>
      <circle cx="50" cy="65" r="3" fill="#000"/>
      <line x1="50" y1="30" x2="50" y2="55" stroke="#000" stroke-width="6" stroke-linecap="round"/>
    </svg>

    <h1>Acceso restringido<br>
    Restricted Access</h1>
    <p>Ha superado la cuota de datos asignada<br>
    You have exceeded your allotted data quota</p>
    <div class="quota">
      <ul>
        <li><strong>Diario | Daily:</strong> 1 GB</li>
        <li><strong>Semanal | Weekly:</strong> 5 GB</li>
        <li><strong>Mensual | Monthly:</strong> 20 GB</li>
      </ul>
    </div>
    <div class="footer">
      El acceso se restaurará automáticamente cuando se renueve su cuota.<br>
      Access will be restored automatically when your quota renews.
    </div>
  </div>
</body>
</html>
EOL

tee /etc/apache2/sites-available/warning.conf >/dev/null << EOL
<VirtualHost *:18880>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/warning
    
    ServerName captive.portal
    ServerAlias *

    <Directory /var/www/html/warning>
        DirectoryIndex warning.html
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
    
    # Windows (NCSI - MSFT Connect Test)
    Alias /ncsi.txt /var/www/html/warning/warning.html
    Alias /connecttest.txt /var/www/html/warning/warning.html
    Alias /redirect /var/www/html/warning/warning.html
    Alias /msftconnecttest/redir.htm /var/www/html/warning/warning.html
    Alias /ncsi/redirect /var/www/html/warning/warning.html

    # Microsoft Edge (Chromium)
    Alias /captiveportal/generate_204 /var/www/html/warning/warning.html
    Alias /edge-captiveportal/generate_204 /var/www/html/warning/warning.html

    # Android (Google Captive Portal Check)
    Alias /generate_204 /var/www/html/warning/warning.html
    Alias /gen_204 /var/www/html/warning/warning.html
    Alias /mobile/status.php /var/www/html/warning/warning.html

    # Apple iOS - macOS
    Alias /hotspot-detect.html /var/www/html/warning/warning.html
    Alias /library/test/success.html /var/www/html/warning/warning.html
    Alias /success.txt /var/www/html/warning/warning.html
    Alias /hotspot.txt /var/www/html/warning/warning.html

    # Firefox Captive Portal
    Alias /captive-portal-success.html /var/www/html/warning/warning.html

    # GNOME / KDE (Linux)
    Alias /nmcheck.txt /var/www/html/warning/warning.html
    Alias /check_network_status.txt /var/www/html/warning/warning.html
    Alias /conncheck.html /var/www/html/warning/warning.html
    Alias /check_network.txt /var/www/html/warning/warning.html

    # Extras
    Alias /favicon.ico /var/www/html/warning/warning.html
    Alias /success.html /var/www/html/warning/warning.html
    Alias /success /var/www/html/warning/warning.html

    RewriteEngine On

    RewriteCond %{REQUEST_URI} !^/warning\.html$
    RewriteCond %{REQUEST_URI} !^/$
    RewriteRule ^.*$ /warning.html [L]

    ErrorLog ${APACHE_LOG_DIR}/warning_error.log
    CustomLog ${APACHE_LOG_DIR}/warning_access.log combined
</VirtualHost>
EOL

chmod 644 /etc/apache2/sites-available/warning.conf
touch /var/log/apache2/{warning_access,warning_error}.log
grep -qxF 'Listen 0.0.0.0:18880' /etc/apache2/ports.conf || grep -qxF 'Listen 18880' /etc/apache2/ports.conf || echo 'Listen 0.0.0.0:18880' >> /etc/apache2/ports.conf

# bandata config
read -p "Enter your Server IP for LAN (default: 192.168.0.10): " serverip
serverip=${serverip:-192.168.0.10}
sed -i "s:192.168.0.10:$serverip:g" $scr/bandata.sh

read -p "Enter your LAN PREFIX (default: 192.168.): " LANPREFIX
LANPREFIX=${LANPREFIX:-192.168*}
sed -i "s:192.168\*:$LANPREFIX:g" $scr/bandata.sh

echo "Your net interfaces are:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
read -p "Enter LAN Net Interface. E.g: enpXsX): " LAN
LAN=${LAN:-eth1}
sed -i "s/eth1/$LAN/g" $scr/bandata.sh

crontab -l | {
  cat
  echo "*/12 * * * * /etc/scr/bandata.sh"
} | crontab -

a2enmod rewrite
a2ensite -q warning.conf
systemctl daemon-reload
systemctl restart apache2
echo "Access: http://$serverip:18880 or http://localhost:18880"

# end
echo "done"
notify-send "Bandata Done" "$(date)" -i checkbox

(sleep 2 && rm -- "$SCRIPT_PATH") &
