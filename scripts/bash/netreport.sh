#!/bin/bash
# maravento.com
#
# Net Report

echo "Net Report Starting. Wait..."
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
pkgs='nmap xsltproc arp-scan'
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

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

### NETREPORT
# Option 1: Intensive | Deep
nmap -v -sSUV --version-light -r -T4 -Pn -O -F --script smb-os-discovery.nse 192.168.0.0/24 -oX netreport.xml
xsltproc netreport.xml -o netreport.html
chown $local_user:$local_user netreport.html
sudo -u $local_user bash -c 'firefox netreport.html' &

# Option 2: Intensive | Deep
#wget https://raw.githubusercontent.com/honze-net/nmap-bootstrap-xsl/master/nmap-bootstrap.xsl
#nmap -sS -T4 -A -sC -oA scanme --stylesheet nmap-bootstrap.xsl 192.168.0.0/24
#xsltproc -o scanme.html nmap-bootstrap.xsl scanme.xml
#chown $myuser:$myuser scanme.html
#sudo -u $myuser bash -c 'firefox nscanme.html' &

# Option 3: Light
#range=192.168.1
#for i in {1..254}; do
#echo -n -e "$i      \r"
#timeout --preserve-status .2  ping -c1 -q $range.$i &> /dev/null
#[ $? -eq 0 ] && echo $range.$i
#done

# Option 4: Light
#arp-scan --localnet

# Option 5: Fast
# nmap -sn 192.168.1.0/24
echo "Done"
