#!/bin/bash
# by maravento.com

# Net Report

echo "Net Report Start. Wait..."
printf "\n"

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
pkgs='nmap xsltproc arp-scan'
if apt-get install -qq $pkgs; then
    echo "OK"
else
    echo "Error installing $pkgs. Abort"
    exit
fi

# LOCAL USER
local_user=${SUDO_USER:-$(whoami)}

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
echo Done
