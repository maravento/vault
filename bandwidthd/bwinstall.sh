#!/bin/bash
# maravento.com

# BandwidthD install

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
pkgs='wget git tar ipset libnotify-bin libcgi-session-perl libgd-perl python-is-python3'
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
bwd=$(pwd)/bandwidthd

echo "BandwidthD install..."

# download
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/bandwidthd
cd $bwd || exit

# install
apt -y purge bandwidthd* &>/dev/null
rm -rf /usr/sbin/bandwidthd /etc/bandwidthd /var/lib/bandwidthd /etc/init.d/bandwidthd /var/run/bandwidthd* &>/dev/null
DEBIAN_FRONTEND=noninteractive apt install -y bandwidthd
cp -f /etc/bandwidthd/bandwidthd.conf{,.bak} &>/dev/null

# localnet
echo
read -p "Enter IP/CIDR of your LAN (default: 192.168.122.0/24): " IP_WAN_CIDR
sed -i "s:192.168.122.0/24:$IP_WAN_CIDR:g" bandwidthd.conf
echo
read -p "Enter IP/CIDR of your WAN (default: 192.168.1.0/24): " IP_LAN_CIDR
sed -i "s:192.168.1.0/24:$IP_LAN_CIDR:g" bandwidthd.conf

cp -f bandwidthd.conf /etc/bandwidthd/bandwidthd.conf &>/dev/null

# bandata
range_to_replace=$(echo "$IP_LAN_CIDR" | cut -d'/' -f1 | cut -d'.' -f1-3)
sed -i "s/192.168.1/$range_to_replace/g" bwbandata.sh
# change net interface
echo "Your net interfaces are:"
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
read -p "Enter LAN Net Interface. E.g: enpXsX): " LAN
sed -i "s/eth1/$LAN/g" bwbandata.sh
cp -f bwbandata.sh /etc/init.d/bwbandata.sh
chmod +x /etc/init.d/bwbandata.sh

systemctl start bandwidthd

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
echo "Bandwidthd Access: http://localhost/bandwidthd
echo "Done"
notify-send "Bandwidthd Done" "$(date)" -i checkbox
