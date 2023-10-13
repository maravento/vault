#!/usr/bin/env bash
# by maravento.com

# Gateproxy OPT

echo "Gateproxy OPT Start. Wait..."
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

# checking dependencies (optional)
pkg='nala curl software-properties-common apt-transport-https aptitude net-tools mlocate plocate expect tcl-expect libnotify-bin'
if apt-get -qq install $pkg; then
    true
else
    echo "Error installing $pkg. Abort"
    exit
fi

ffunction cleanupgrade() {
    nala upgrade --purge -y
    aptitude safe-upgrade -y
    fc-cache
    sync
    updatedb
}

function fixbroken() {
    dpkg --configure -a
    nala install --fix-broken -y
}

### VARIABLES
gp=$(pwd)/gateproxy
scr=/etc/scr
if [ ! -d $scr ]; then mkdir -p $scr; fi &>/dev/null

### OPTIONAL PACKAGES ###
clear
# dns (not recommended)
function dns_setup() {
    # DNS Privacy stub resolver
    nala install -y stubby
    # Fix DNS
    service systemd-resolved stop
    cp -f /etc/systemd/resolved.conf{,.bak} &>/dev/null
    cp -f $gp/opt/pkg/resolved.conf /etc/systemd/resolved.conf
    cp -f /etc/resolv.conf{,.bak} &>/dev/null
    rm /etc/resolv.conf
    ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf
    systemctl restart systemd-resolved
    fixbroken
}

# ssh (optional)
function ssh_setup() {
    nala install -y ssh
    tee -a /etc/ssh/sshd_config >/dev/null <<EOT
PasswordAuthentication yes
PermitRootLogin no
Port 8282
EOT
    systemctl restart ssh
    # /lib/systemd/systemd-sysv-install enable ssh # optional to enable service
    echo "SSH Access: ssh -p 8282 SERVERIP or localhost"
}

echo -e "\n"
while true; do
    read -p "Do you want to Install Gateproxy Optional Packages OPT? (y/n)" answer
    case $answer in
    [Yy]*)
        # execute command yes
        # boot-repair
        apt-add-repository -y ppa:yannubuntu/boot-repair &>/dev/null
        nala install -y boot-repair
        # pc tools
        nala install -y thunar isomaster tasksel fd-find colordiff bat
        # browsers
        nala install -y lynx
        # hardware info
        nala install -y inxi hardinfo cpufrequtils cpuid i7z dmidecode
        # disk
        nala install -y qdirstat meld ncdu gnome-disk-utility testdisk gdisk kpartx guymager bindfs fdupes udisks2-btrfs
        # usb
        nala install -y usb-creator-gtk
        # kvm
        nala install -y barrier
        # edit
        nala install -y gnome-text-editor vim
        # terminal
        nala install -y tilix
        fixbroken
        # manage share connections
        nala install -y gigolo
        # sensors
        nala install -y lm-sensors psensor
        # fonts
        nala install -y fonts-lato
        echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
        nala install -y ttf-mscorefonts-installer fontconfig
        fc-cache -f
        fc-match Ariel
        fixbroken
        # bleachbit
        lastbleachbit=$(wget --quiet -O - https://www.bleachbit.org/download/linux | grep -Po '(?<=file=).*(?=">)' | grep ubuntu2004 | sort -u)
        echo $lastbleachbit
        wget -q --show-progress -c "https://download.bleachbit.org/${lastbleachbit}" -O bleachbit.deb
        dpkg -i bleachbit.deb
        fixbroken
        # mintstick
        nala install -y python3-parted python-parted-doc gir1.2-udisks-2.0 xapp exfatprogs
        lastmintstick=$(wget -O - http://packages.linuxmint.com/pool/main/m/mintstick/ | grep -Po 'href=".*?"' | sed -r 's:href\="(.*)":\1:' | grep ".deb" | sort | tail -1)
        echo $lastmintstick
        wget -q --show-progress -c http://packages.linuxmint.com/pool/main/m/mintstick/"$lastmintstick" -O mintstick.deb
        nala install -y genisoimage python3-gnupg gir1.2-xapp-1.0
        dpkg -i mintstick.deb
        fixbroken
        # cryptomator
        add-apt-repository -y ppa:sebastian-stenzel/cryptomator &>/dev/null
        nala install -y cryptomator
        # monitors
        nala install -y vnstat vnstati iftop nload nethogs bmon cbm iperf3 hwinfo powertop libiperf0 calamaris sysstat bpytop iptraf-ng
        # htop + HTML-Code
        nala install -y aha htop
        echo "run: echo q | htop | aha --black --line-fix > htop.html"
        fixbroken
        curl -s https://packagecloud.io/install/repositories/netdata/netdata/script.deb.sh | bash
        nala install -y netdata
        if [ ! -d /var/log/netdata ]; then
            mkdir -p /var/log/netdata &>/dev/null
            touch /var/log/netdata/{access,error,debug}.log
            chown -R root:root /var/log/netdata
        fi
        chmod +x $gp/opt/pkg/netdata.sh
        $gp/opt/pkg/netdata.sh >>/etc/scr/servicesload.sh
        echo "Netdata Access: http://localhost:19999/"
        # net tools
        nala install -y ndiff arp-scan ncat cutter ethtool fping hping3 nast netdiscover putty traceroute mtr-tiny dirb wavemon netcat masscan nikto grepcidr
        echo "masscan --ports 0-65535 192.168.0.0/16"
        fixbroken
        # security
        nala install -y dnsutils dsniff wireshark wireshark-common tshark tcpdump netsniff-ng
        nala install -y lynis chkrootkit arpon
        nala install -y --no-install-recommends rkhunter
        fixbroken
        crontab -l | {
            cat
            echo "#@reboot /etc/scr/arponscan.sh"
        } | crontab -
        cp -f /etc/logrotate.d/arpon{,.bak} &>/dev/null
        cp -f $gp/opt/pkg/arpon /etc/logrotate.d/arpon
        cp -f /etc/rkhunter.conf{,.bak} &>/dev/null
        cp -f $gp/opt/pkg/rkhunter.conf /etc/rkhunter.conf
        chmod -x /etc/rkhunter.conf
        crontab -l | {
            cat
            echo "@weekly /usr/bin/rkhunter --update --quiet"
        } | crontab -
        echo "Check ArpON log: /var/log/arpon/arpon.log"
        echo "Chkrootkit Run: chkrootkit -q"
        echo "Lynis Run: lynis -c -Q and log: /var/log/lynis.log"
        echo "Rkhunter Run: rkhunter --check and Log: /var/log/rkhunter.log"
        # sandbox (source: https://geekland.eu/firejail-sandbox-para-linux/)
        nala install -y firejail firetools
        fixbroken
        cleanupgrade
        #dns_setup # (not recommended)
        #ssh_setup # Optional
        break
        ;;
    [Nn]*)
        # execute command no
        echo NO
        break
        ;;
    *)
        echo
        echo "Answer: YES (y) or NO (n)"
        ;;
    esac
done
echo "Done"
