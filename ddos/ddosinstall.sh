#!/bin/bash
# maravento.com

# DDoS-Deflate
# Minor update to DDoS-Deflate, version 0.6

echo "DDoS-Deflate Starting. Wait..."
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
pkgs='dnsutils net-tools python-is-python3'
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

# Server IP
ips=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1)
# Ignore Path
ignore_file="/usr/local/ddos/ignore"

wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/ddos
mkdir -p /usr/local/ddos
chown root:root /usr/local/ddos
cp -f -R ddos/* /usr/local/ddos
rm -r ddos
chmod 0755 /usr/local/ddos/ddos.sh
(crontab -l 2>/dev/null | grep -v '/usr/local/ddos/ddos.sh'; echo "*/1 * * * * /usr/local/ddos/ddos.sh &> /dev/null") | crontab -
(crontab -l 2>/dev/null | grep -v '@monthly.*find /usr/local/ddos'; echo "@monthly find /usr/local/ddos/* -type f -exec truncate -s 0 {} \;") | crontab -
systemctl restart cron
echo "Adding Parameters..."
tee -a /etc/rsyslog.conf >/dev/null <<EOT
*.none    /usr/local/ddos/ddos.log
EOT

# Add server IP address to "ignore"
for ip in $ips; do
    grep -qxF "$ip" "$ignore_file" || echo "$ip" >> "$ignore_file"
done

echo "DDoS Deflate IPs Exclude: /usr/local/ddos/ignore"
echo "DDoS Deflate IPs Ban: /usr/local/ddos/ddos.log"
echo "DDoS Deflate Config: /usr/local/ddos/ddos.conf"

echo Done
