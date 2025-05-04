#!/bin/bash
# maravento.com

# DDoS-Deflate
# Minor update to DDoS-Deflate, version 0.6

echo "DDoS-Deflate Starting. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) > /dev/null; then
  for p in $(pidof -x $(basename $0)); do
    if [ "$p" -ne $$ ]; then
      echo "Script $0 is already running..."
      exit
    fi
  done
fi

# Checking dependencies
pkgs='dnsutils net-tools python-is-python3'
if apt-get update -qq && apt-get install -y -qq $pkgs; then
    echo "Dependencies installed successfully."
else
    echo "Error installing $pkgs. Aborting."
    exit 1
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
(crontab -l 2>/dev/null | grep -v '/usr/local/ddos'; echo "*/1 * * * * /usr/local/ddos/ddos.sh &> /dev/null") | crontab -
systemctl restart cron

# Add server IP address to "ignore"
for ip in $ips; do
    grep -qxF "$ip" "$ignore_file" || echo "$ip" >> "$ignore_file"
done

echo "DDoS Deflate IPs Exclude: /usr/local/ddos/ignore"
echo "DDoS Deflate IPs Ban: /usr/local/ddos/ddos.log"
echo "DDoS Deflate Config: /usr/local/ddos/ddos.conf"

echo Done
