#!/bin/bash
# maravento.com

# Gateproxy
# A simple proxy/firewall server

# Note: &>/dev/null is an abbreviation for >/dev/null 2>&1

clear
echo -e "\n"
echo "Gateproxy Start. Wait..."
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

### LANGUAGE EN-ES
lang_01=("Check System..." "Verificando Sistema...")
lang_02=("Aborted installation. Check the Minimum Requirements" "Instalacion Abortada. Verifique los Requisitos Mínimos")
lang_03=("Checking Bandwidth..." "Verificando Ancho de Banda...")
lang_04=("Update and Clean" "Actualización y Limpieza")
lang_05=("Fix Broken Packages" "Arreglando Paquetes Rotos")
lang_06=("Wait..." "Espere...")
lang_07=("Answer" "Responda")
lang_08=("Check Dependencies..." "Verificando Dependencias...")
lang_09=("Older NIC-Ethernet Format Detected" "Se ha detectado formato antiguo NIC-Ethernet")
lang_10=("List of Network Interfaces Detected" "Lista de Interfaces de Red Detectadas")
lang_11=("Public Network Interface (Internet)" "Interfaz de Red Publica (Internet)")
lang_12=("Local Network Interface" "Interfaz de Red Local")
lang_13=("Welcome to GateProxy" "Bienvenido a GateProxy")
lang_14=("Minimum Requirements:" "Requisitos Mínimos:")
lang_15=("Press ENTER to start or CTRL+C to abort" "Presione ENTER para iniciar o CTRL+C para abortar")
lang_16=("Server settings:" "Parametros del servidor:")
lang_17=("Enter" "Introduzca")
lang_18=("You have entered" "Ha introducido")
lang_19=("Do you want to change?" "Desea modificar?")
lang_20=("Do you want to install" "Desea instalar")
lang_21=("with SHARED folder, Recycle Bin and Audit" "con carpeta COMPARTIDA, Papelera Reciclaje y Auditoria")
lang_22=("shared" "compartida")
lang_23=("the name of samba user" "el nombre del usuario de samba")
lang_24=("Done. Press ENTER to Reboot" "Terminado. Presione ENTER para Reiniciar")
lang_25=("e.g." "e.j.")

lang=$([[ "${LANG,,}" =~ ^es ]] && echo 1 || echo 0)

### CHECK SO & DESKTOP
echo "${lang_01[$lang]}"
# Get the current desktop environment in lowercase
DESKTOP_ENV=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
# Get the Ubuntu version number (e.g., 22.04, 24.04)
UBUNTU_VERSION=$(lsb_release -rs)
# Get the distribution ID (e.g., Ubuntu)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')

# Check if the system is Ubuntu and the version is either 22.04 or 24.04
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # Uncomment the next line if you want to abort execution on unsupported systems
    # exit 1
else
    # Warn the user if the desktop environment is not MATE or Cinnamon
    if [[ "$DESKTOP_ENV" != "mate" && "$DESKTOP_ENV" != "cinnamon" ]]; then
        echo "MATE or Cinnamon desktop recommended"
    fi
fi

### VARIABLES
SCRIPT_PATH="$(realpath "$0")"
gp=$(pwd)/gateproxy
zone=/etc/zones
mkdir -p "$zone" >/dev/null 2>&1
aclroute=/etc/acl
mkdir -p "$aclroute" >/dev/null 2>&1
scr=/etc/scr
mkdir -p "$scr" >/dev/null 2>&1
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')

# ppa
file="/etc/apt/sources.list.d/ubuntu.sources"
required_components=("main" "restricted" "universe" "multiverse")
changed=0

while IFS= read -r line; do
    if [[ "$line" =~ ^Components: ]]; then
        read -ra found <<< "${line#Components: }"

        for required in "${required_components[@]}"; do
            if ! printf '%s\n' "${found[@]}" | grep -qx "$required"; then
                echo "Missing '$required' in: $line"
                sed -i "s|^$line|Components: ${required_components[*]}|" "$file"
                changed=1
                break
            fi
        done

        if [[ $changed -eq 0 ]]; then
            echo "All components present in: $line"
        fi
    fi
done < <(grep "^Components:" "$file")

if [[ $changed -eq 1 ]]; then
    echo "Updating package list. Wait..."
    apt update > /dev/null 2>&1
else
    echo "No changes made. No update needed."
fi

# check dependencies
pkgs='nala curl software-properties-common apt-transport-https aptitude net-tools plocate git git-gui gitk gist expect tcl-expect libnotify-bin gcc make perl bzip2 p7zip-full p7zip-rar rar unrar unzip zip unace cabextract arj zlib1g-dev tzdata tar python-is-python3 coreutils dconf-editor'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    echo "Missing dependencies not found in APT:"
    for u in $unavailable; do echo "   - $u"; done
    echo "Please install them manually or enable the required repositories."
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
    echo "Installing: $missing"
    apt-get -qq update
    if ! apt-get -y install $missing; then
        echo "Error installing: $missing"
        exit 1
    fi
else
    echo "✅ Dependencies OK"
fi

### BASIC
# time
apt purge -y ntp ntpdate chrony &>/dev/null
apt install -y --reinstall systemd-timesyncd &>/dev/null
hwclock -w &>/dev/null
systemctl enable --now systemd-timesyncd &>/dev/null
timedatectl set-ntp true &>/dev/null
timedatectl status | grep -E "NTP|synchroniz"
# install | remove
apt -qq install -y apt-file
apt-file update
apt -qq remove -y zsys &>/dev/null
ubuntu-drivers autoinstall &>/dev/null
# configure
pro config set apt_news=false
hdparm -W /dev/sda &>/dev/null
ifconfig lo 127.0.0.1
#systemctl disable avahi-daemon cups-browser &> /dev/null # optional
# cron
cp /etc/crontab{,.bak} &>/dev/null
crontab /etc/crontab &>/dev/null
cp /etc/apt/sources.list{,.bak} &>/dev/null
# Disable NFS (Network File System) / NIS (Network Information Service)
if systemctl list-unit-files | grep -q '^rpcbind'; then
    systemctl stop rpcbind.service rpcbind.socket &>/dev/null || true
    systemctl disable rpcbind.service rpcbind.socket &>/dev/null || true
    systemctl mask rpcbind.service rpcbind.socket &>/dev/null || true
fi

### CLEAN | UPDATE
clear
echo -e "\n"
function cleanupgrade() {
    echo "${lang_04[$lang]}. ${lang_06[$lang]}"
    nala upgrade --purge -y
    aptitude safe-upgrade -y
    sync
    updatedb
}

function fixbroken() {
    echo "${lang_05[$lang]}. ${lang_06[$lang]}"
    dpkg --configure -a
    nala install --fix-broken -y
}

cleanupgrade
fixbroken

### PACKAGES
clear
echo -e "\n"
echo "${lang_08[$lang]}"

### GATEPROXY GIT
echo -e "\n"
if [ -d $gp ]; then rm -rf $gp; fi &>/dev/null
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/gateproxy

### CONFIG
clear
echo -e "\n"
hostnamectl set-hostname "$HOSTNAME"
find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:gateproxy:$HOSTNAME:g" "{}"
# changing name user account in config files
find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:your_user:$local_user:g" "{}"

# public interface
function public_interface() {
    read -p "${lang_17[$lang]} ${lang_11[$lang]} (${lang_25[$lang]} enpXsX): " ETH0
    if [ "$ETH0" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:eth0:$ETH0:g" "{}"
    fi
}

# local interface
function local_interface() {
    read -p "${lang_17[$lang]} ${lang_12[$lang]} (${lang_25[$lang]} enpXsX): " ETH1
    if [ "$ETH1" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:eth1:$ETH1:g" "{}"
        export LAN_INTERFACE="$ETH1"
    fi
}

function is_interfaces() {
    is_interfaces=$(ifconfig | grep eth0)
    if [ "$is_interfaces" ]; then
        echo "${lang_09[$lang]}"
        echo "${lang_02[$lang]}"
        rm -rf $gp &>/dev/null
        exit
    else
        echo "Check Net Interfaces: OK"
        echo "${lang_10[$lang]}:"
        ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
        public_interface
        local_interface
        echo OK
    fi
}
is_interfaces

### START
clear
echo -e "\n"
echo "    ${lang_13[$lang]}"
echo -e "\n"
echo "    ${lang_14[$lang]}"
echo "    OS:       Ubuntu 24.04.x"
echo "    CPU:      Intel Core i5/Xeon/AMD Ryzen 5 (≥ 3.0 GHz)"
echo "    NIC:      2 (WAN & LAN)"
echo "    RAM:      4 GB for cache_mem (≥ 12 GB total RAM recommended)"
echo "    Storage:  100 GB SSD for cache_dir rock"
echo -e "\n"
echo "    ${lang_15[$lang]}"
echo -e "\n"
read RES
clear

echo -e "\n"
while true; do
    read -p "${lang_19[$lang]} Server IP 192.168.0.10? (y/n): " change_ip
    case "$change_ip" in
        [Yy]*)
            while true; do
                read -p "${lang_17[$lang]} IP (${lang_25[$lang]} 192.168.0.10): " input_ip
                serveripNEW=$(echo "$input_ip" | grep -E '^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$')
                if [ "$serveripNEW" ]; then
                    serverip="$serveripNEW"

                    find "$gp/conf" -type f -print0 | while IFS= read -r -d '' file; do
                        sed -i "s:192.168.0.10:$serveripNEW:g" "$file"
                    done

                    find "$gp/acl" -type f \( -name "mac-*" -o -name "blockdhcp*" \) -print0 | while IFS= read -r -d '' file; do
                        sed -i "s:192.168.0\.:$(echo "$serveripNEW" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" "$file"
                    done

                    echo "${lang_18[$lang]} IP $serverip :OK"
                    break
                else
                    echo "${lang_18[$lang]} IP incorrect"
                fi
            done
            break
            ;;
        [Nn]*)
            serverip="192.168.0.10"
            echo "Default IP: $serverip"
            break
            ;;
        *)
            echo "${lang_07[$lang]}: YES (y) or NO (n)"
            ;;
    esac
done

### PARAMETERS
is_ask() {
    inquiry="$1"
    iresponse="$2"
    funcion="$3"
    while true; do
        read -p "$inquiry: " answer
        case "$answer" in
        [Yy]*)
            # execute command yes
            while true; do
                answer=$($funcion)
                if [ "$answer" ]; then
                    echo "$answer"
                    break
                else
                    echo "$iresponse"
                fi
            done
            break
            ;;
        [Nn]*)
            # execute command no
            echo NO
            break
            ;;
        *)
            echo
            echo "${lang_07[$lang]}: YES (y) or NO (n)"
            ;;
        esac
    done
}

# netmask
function is_mask1() {
    read -p "${lang_17[$lang]} Netmask (${lang_25[$lang]} 255.255.255.0): " MASK1
    MASKNEW1=$(echo "$MASK1" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$MASKNEW1" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:255.255.255.0:$MASKNEW1:g" "{}"
        echo "${lang_18[$lang]} Netmask $MASK1 :OK"
    fi
}

function is_mask2() {
    read -p "${lang_17[$lang]} Subnet-Mask (${lang_25[$lang]} 24): " MASK2
    MASKNEW2=$(echo "$MASK2" | grep -E '[0-9]')
    if [ "$MASKNEW2" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:/24:/$MASKNEW2:g" "{}"
        echo "${lang_18[$lang]} Subnet-Mask $MASK2 :OK"
    fi
}

# dns primary
function is_dns1() {
    read -p "${lang_17[$lang]} DNS1 (${lang_25[$lang]} 8.8.8.8): " DNS1
    DNSNEW1=$(echo "$DNS1" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$DNSNEW1" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.8.8:$DNSNEW1:g" "{}"
        echo "${lang_18[$lang]} DNS1 $DNS1 :OK"
    fi
}

# dns secondary
function is_dns2() {
    read -p "${lang_17[$lang]} DNS2 (${lang_25[$lang]} 8.8.4.4): " DNS2
    DNSNEW2=$(echo "$DNS2" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$DNSNEW2" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.4.4:$DNSNEW2:g" "{}"
        echo "${lang_18[$lang]} DNS2 $DNS2 :OK"
    fi
}

# localnet
function is_localnet() {
    read -p "${lang_17[$lang]} Localnet (${lang_25[$lang]} 192.168.0.0): " LOCALNET
    LOCALNETNEW=$(echo "$LOCALNET" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$LOCALNETNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.0:$LOCALNETNEW:g" "{}"
        echo "${lang_18[$lang]} Localnet $LOCALNET :OK"
    fi
}

# broadcast
function is_broadcast() {
    read -p "${lang_17[$lang]} Broadcast (${lang_25[$lang]} 192.168.0.255): " BROADCAST
    BROADCASTNEW=$(echo "$BROADCAST" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$BROADCASTNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.255:$BROADCASTNEW:g" "{}"
        echo "${lang_18[$lang]} Broadcast $BROADCAST :OK"
    fi
}

# dhcp range
function is_rangeini() {
    read -p "${lang_17[$lang]} DHCP-RANGE-INI (${lang_25[$lang]} 192.168.0.100): " RANGEINI
    RANGEININEW=$(echo "$RANGEINI" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$RANGEININEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.100:$RANGEININEW:g" "{}"
        echo "${lang_18[$lang]} correct DHCP-RANGE-INI $RANGEINI :OK"
    fi
}

function is_rangeend() {
    read -p "${lang_17[$lang]} DHCP-RANGE-END (${lang_25[$lang]} 192.168.0.250): " RANGEEND
    RANGEENDNEW=$(echo "$RANGEEND" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$RANGEENDNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.250:$RANGEENDNEW:g" "{}"
        echo "${lang_18[$lang]} correct DHCP-RANGE-END $RANGEEND :OK"
    fi
}

# squid port
function is_port() {
    read -p "${lang_17[$lang]} Proxy Port (${lang_25[$lang]} 3128): " PORT
    PORTNEW=$(echo "$PORT" | grep -E '[1-9]')
    if [ "$PORTNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:3128:$PORTNEW:g" "{}"
        echo "${lang_18[$lang]} Proxy Port $PORT :OK"
    fi
}

echo -e "\n"
while true; do
    read -p "${lang_16[$lang]}
Mask 255.255.255.0, Network /24, DNS 8.8.8.8 8.8.4.4, Localnet 192.168.0.0
Broadcast 192.168.0.255, DHCP Range ini-100 end-250, Proxy Port 3128
    ${lang_19[$lang]} (y/n)" answer
    case $answer in
    [Yy]*)
        # execute command yes
        is_ask "${lang_19[$lang]} Mask 255.255.255.0? (y/n)" "${lang_18[$lang]} Mask incorrect" is_mask1
        is_ask "${lang_19[$lang]} Sub-Mask /24? (y/n)" "${lang_18[$lang]} Sub-Mask incorrect" is_mask2
        is_ask "${lang_19[$lang]} DNS1 8.8.8.8? (y/n)" "${lang_18[$lang]} DNS1 incorrect" is_dns1
        is_ask "${lang_19[$lang]} DNS2 8.8.4.4? (y/n)" "${lang_18[$lang]} DNS2 incorrect" is_dns2
        is_ask "${lang_19[$lang]} Localnet 192.168.0.0? (y/n)" "${lang_18[$lang]} Localnet incorrect" is_localnet
        is_ask "${lang_19[$lang]} Broadcast 192.168.0.255? (y/n)" "${lang_18[$lang]} Broadcast incorrect" is_broadcast
        is_ask "${lang_19[$lang]} DHCP-RANGE-INI 192.168.0.100? (y/n)" "${lang_18[$lang]} IP incorrect" is_rangeini
        is_ask "${lang_19[$lang]} DHCP-RANGE-END 192.168.0.250? (y/n)" "${lang_18[$lang]} IP incorrect" is_rangeend
        is_ask "${lang_19[$lang]} Proxy Port Default 3128? (y/n)" "${lang_18[$lang]} Proxy Port incorrect" is_port
        echo OK
        break
        ;;
    [Nn]*)
        # execute command no
        echo NO
        break
        ;;
    *)
        echo
        echo "${lang_07[$lang]}: YES (y) or NO (n)"
        ;;
    esac
done

### ESSENTIAL
clear
echo -e "\n"
echo "Essential Packages..."
# Disk & Partition Tools
nala install -y gparted nfs-common ntfs-3g gsmartcontrol qdirstat gnome-disk-utility
nala install -y --no-install-recommends smartmontools
    
# System Utilities
nala install -y trash-cli pm-utils neofetch cpu-x lsof inotify-tools dmidecode idle3 \
                wmctrl pv dpkg ppa-purge deborphan apt-utils gawk gir1.2-gtop-2.0 \
                finger logrotate tree moreutils rename renameutils sharutils dos2unix \
                gdebi synaptic preload debconf-utils mokutil util-linux linux-tools-common \
                colordiff
    
# Development Libraries & Build Tools
nala install -y uuid-dev libmnl-dev gtkhash libssl-dev libffi-dev python3-dev python3-venv \
                libpam0g-dev autoconf autoconf-archive autogen automake dh-autoreconf \
                pkg-config libpcap-dev libasound2-dev libfontconfig1 clang libuser \
                build-essential module-assistant linux-headers-$(uname -r)
    
# Programming Languages & Environments
nala install -y javascript-common libjs-jquery rubygems-integration rake \
                ruby ruby-did-you-mean ruby-json ruby-minitest ruby-net-telnet \
                ruby-power-assert ruby-test-unit python3-pip python3-psutil xsltproc
    
# UDisks Tools (runtime + development)
nala install -y udisks2 udisks2-btrfs udisks2-lvm2 libglib2.0-dev \
                libudisks2-dev liblvm2-dev
    
# File System Utilities
nala install -y reiserfsprogs reiser4progs xfsprogs jfsutils dosfstools e2fsprogs \
                hfsprogs hfsutils hfsplus mtools nilfs-tools f2fs-tools quota lvm2 attr jmtpfs
    
# FUSE Tools
nala install -y libfuse2t64 exfat-fuse gvfs-fuse bindfs sshfs
    
# Network / Geo / Web Tools
nala install -y conntrack i2c-tools wget bind9-dnsutils geoip-database wsdd
    
# Mesa (if there any problems, install the package: libegl-mesa0)
nala install -y mesa-utils
    
# Mail
service sendmail stop >/dev/null 2>&1
update-rc.d -f sendmail remove >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive nala install -y postfix

# Search tool
add-apt-repository -y ppa:christian-boxdoerfer/fsearch-stable
nala install -y fsearch
    
# Fonts
nala install -y fonts-lato fonts-liberation fonts-dejavu
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
nala install -y ttf-mscorefonts-installer fontconfig
fc-cache -f
    
# ubuntu database
update-desktop-database
echo OK
sleep 1

cleanupgrade
fixbroken

### SETUP
echo -e "\n"
echo "Gateproxy Packages..."
sed -i "/127.0.1.1/r $gp/conf/server/hosts.txt" /etc/hosts

# ACLs
cp -rf $gp/acl/* "$aclroute"
chmod -x "$aclroute"/*

# DHCP: isc-dhcp-server
nala install -y isc-dhcp-server
systemctl disable isc-dhcp-server6
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$LAN_INTERFACE\"/" /etc/default/isc-dhcp-server

# PHP
nala install -y php

# http server: apache2
nala install -y apache2 apache2-doc apache2-utils apache2-dev \
                apache2-suexec-pristine libaprutil1t64 libaprutil1-dev \
                libtest-fatal-perl
systemctl enable apache2.service
# To fix apache2 error: Syntax error on line 146 of /etc/apache2/apache2.conf | Cannot load /usr/lib/apache2/modules/mod_dnssd.so
#nala install -y libapache2-mod-dnssd
# To fix apache2-doc error:
apt -qq install -y --reinstall apache2-doc
fixbroken
cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
sed -i -E 's/^([[:space:]]*)Listen[[:space:]]+([0-9]+)/\1Listen 0.0.0.0:\2/' /etc/apache2/ports.conf

# Proxy: squid-cache
while pgrep squid > /dev/null; do
    killall -s SIGTERM squid &>/dev/null
    sleep 5
done
nala purge -y squid* &>/dev/null
rm -rf /var/spool/squid* /var/log/squid* /etc/squid* /dev/shm/* &>/dev/null
rm -f /run/squid.pid &>/dev/null
#DEBIAN_FRONTEND=noninteractive nala install -y --no-install-recommends squid-openssl
nala install -y squid-openssl squid-langpack squid-common squidclient squid-purge
fixbroken
mkdir -p /var/log/squid >/dev/null 2>&1
touch /var/log/squid/{access,cache,store,deny}.log >/dev/null 2>&1
chown proxy:adm /var/log/squid/*.log
chmod 640 /var/log/squid/*.log
mkdir -p /var/spool/squid/rock >/dev/null 2>&1
chown -R proxy:proxy /var/spool/squid/rock
chmod -R 700 /var/spool/squid/rock
systemctl enable squid.service
squid -z
cp -f /etc/logrotate.d/squid{,.bak} &>/dev/null
sed -i '/sharedscripts/a \    create 0644 proxy adm' /etc/logrotate.d/squid
# Let’s Encrypt certificate for client to Squid proxy encryption (Optional)
#nala install -y certbot python3-certbot-apache
    
# Web Admin: webmin
# https://www.maravento.com/2019/06/instalar-modulo-webmin-por-linea-de.html
curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
chmod +x setup-repos.sh
echo "y" | ./setup-repos.sh
cleanupgrade
nala install -y webmin
fixbroken
/usr/share/webmin/install-module.pl $gp/conf/monitor/text-editor.wbm
find $aclroute -maxdepth 1 -type f | tee /etc/webmin/text-editor/files &>/dev/null
systemctl enable webmin.service
echo "Webmin Access: https://localhost:10000"
    
# Web Admin + Virtualization:
# https://www.maravento.com/2022/11/cockpit.html
# QEMU/KVM
nala install -y qemu-kvm virt-manager virtinst libvirt-clients libvirt-daemon-system \
                virtiofsd qemu-system qemu-guest-agent
usermod -aG kvm "$local_user"
usermod -aG libvirt "$local_user"
systemctl enable --now libvirtd
# Note: For Linux Guest, run: sudo apt install -y qemu-guest-agent
# Virtual Tools
nala install -y bridge-utils libguestfs-tools ovmf
# Cockpit
nala install -y cockpit cockpit-storaged cockpit-networkmanager cockpit-packagekit \
                cockpit-machines cockpit-sosreport virt-viewer
cp $gp/conf/server/cockpit.conf /etc/fail2ban/filter.d/cockpit.conf
systemctl enable --now cockpit cockpit.socket
echo "Cockpit Access: http://localhost:9090"
    
# Process: glances
# https://www.maravento.com/2023/04/glances.html
nala install -y glances
systemctl enable glances.service
systemctl stop glances.service
export GLANCES_VERSION=$(glances -V | head -n 1 | awk '{print $2}' | sed 's/^v//')
wget "https://github.com/nicolargo/glances/archive/refs/tags/v${GLANCES_VERSION}.tar.gz"
tar -xzf v${GLANCES_VERSION}.tar.gz
rm v${GLANCES_VERSION}.tar.gz
cp -r glances-${GLANCES_VERSION}/glances/outputs/static/public/ /usr/lib/python3/dist-packages/glances/outputs/static/
rm -rf glances-${GLANCES_VERSION}
sed -i '/ExecStart=\/usr\/bin\/glances -s -B 127.0.0.1/c\ExecStart=\/usr\/bin\/glances -w -B 0.0.0.0 -t 10 -p 61208' /usr/lib/systemd/system/glances.service
systemctl daemon-reload
systemctl start glances.service
echo "Glances Access: http://localhost:61208"
    
# Net Pack
# Net Tools (Replace NIC and IP/CIDR)
nala install -y wireless-tools     # Wireless tools: iwconfig, iwlist, iwpriv
nala install -y fping              # Net diagnostics: fping -a -g 192.168.1.0/24
nala install -y ethtool            # Net config: ethtool eth0
# Net test: On server: iperf3 -s | On client: iperf3 -c serverip
DEBIAN_FRONTEND=noninteractive nala install -y iperf3  2>/dev/null
# Net Scanning (Replace NIC and IP/CIDR)
nala install -y masscan            # masscan --ports 0-65535 192.168.0.0/16
nala install -y nbtscan            # nbtscan 192.168.1.0/24
nala install -y nast               # nast -m
nala install -y arp-scan           # arp-scan --localnet
nala install -y arping             # arping -I eth0 192.168.1.1
nala install -y netdiscover        # netdiscover
# Nmap
nala install -y nmap python3-nmap ndiff
# Domain/IP Scanning
nala install -y traceroute         # traceroute google.com
nala install -y mtr-tiny           # mtr google.com
    
# Traffic Reports: Sarg
# https://www.maravento.com/2014/03/network-monitor.html
nala install -y sarg
fixbroken
mkdir -p /var/www/squid-reports
cp -f /etc/sarg/sarg.conf{,.bak} &>/dev/null
cp -f $gp/conf/monitor/sarg.conf /etc/sarg/sarg.conf
chmod -x /etc/sarg/sarg.conf
cp -f /etc/sarg/usertab{,.bak} &>/dev/null
cp -f $gp/conf/monitor/usertab /etc/sarg/usertab
chmod -x /etc/sarg/usertab
cp -f $gp/conf/monitor/sargaudit.conf /etc/apache2/sites-available/sargaudit.conf
chmod 644 /etc/apache2/sites-available/sargaudit.conf
a2ensite -q sargaudit.conf
sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log &>/dev/null
crontab -l | {
    cat
    echo "@daily sarg -l /var/log/squid/access.log -o /var/www/squid-reports &> /dev/null"
} | crontab -
crontab -l | {
    cat
    echo '@weekly find /var/www/squid-reports -name "2*" -mtime +30 -type d -exec rm -rf "{}" \; &> /dev/null'
} | crontab -
grep -qxF 'Listen 0.0.0.0:18801' /etc/apache2/ports.conf || grep -qxF 'Listen 18801' /etc/apache2/ports.conf || echo 'Listen 0.0.0.0:18801' >> /etc/apache2/ports.conf
echo "Sarg Access: http://localhost:18801 or http://$serverip:18801/"
echo "Sarg Usernames: /etc/sarg/usertab (${lang_25[$lang]} 192.168.0.10 GATEPROXY)"

# Monitor: lightsquid
# https://github.com/maravento/vault/tree/master/lightsquid
nala install -y libcgi-session-perl libgd-perl
tar -xf $gp/conf/monitor/lightsquid-1.8.1.tar.gz
mkdir -p /var/www/lightsquid
cp -f -R lightsquid-1.8.1/* /var/www/lightsquid/
rm -rf lightsquid-1.8.1
chmod +x /var/www/lightsquid/*.{cgi,pl}
cp -f $gp/conf/monitor/lightsquid.conf /etc/apache2/conf-available/lightsquid.conf
a2enmod cgid
a2enconf lightsquid
crontab -l | {
    cat
    echo "*/10 * * * * /var/www/lightsquid/lightparser.pl today"
} | crontab -
crontab -l | {
    cat
    echo "#*/12 * * * * /etc/scr/bandata.sh"
} | crontab -
echo "Lightsquid Access: http://localhost/lightsquid/"
echo "Lightsquid Usernames: /var/www/lightsquid/realname.cfg"
echo "Lightsquid (first time run): /var/www/lightsquid/lightparser.pl"
echo "Lightsquid (check bandata IP): cat /etc/acl/{banmonth,bandaily}.txt | uniq"
    
# Warning for lightsquid-bandata
mkdir -p /var/www/html/warning
chown -R www-data:www-data /var/www/html/warning
#escaped_serverip=$(echo "$serverip" | sed 's/\./\\\\./g')
#sed -i "s/192\\\\.168\\\\.0\\\\.10/$escaped_serverip/g" $gp/conf/monitor/warning.html
cp -f $gp/conf/monitor/warning.html /var/www/html/warning/warning.html
# http
cp -f $gp/conf/monitor/warning.conf /etc/apache2/sites-available/warning.conf
chmod 644 /etc/apache2/sites-available/warning.conf
touch /var/log/apache2/{warning_access,warning_error}.log
grep -qxF 'Listen 0.0.0.0:18880' /etc/apache2/ports.conf || grep -qxF 'Listen 18880' /etc/apache2/ports.conf || echo 'Listen 0.0.0.0:18880' >> /etc/apache2/ports.conf

a2enmod rewrite
a2ensite -q warning.conf
echo "Warning: http://$serverip:18880"

# Security:
# fail2ban
nala install -y fail2ban
cp $gp/conf/server/jail.local /etc/fail2ban/jail.local
sed -i 's/^#\?allowipv6 *= *.*/allowipv6 = 0/' /etc/fail2ban/fail2ban.conf
systemctl enable fail2ban.service
echo "Check: sudo fail2ban-client status <jail_name>"
echo "Unban all: sudo fail2ban-client unban --all"
echo "Unban Jail: sudo fail2ban-client set <jail_name> unban --all"
# lynis
nala install -y lynis
echo "Lynis Run: lynis -c -Q and log: /var/log/lynis.log"
# ipset
nala install -y ipset
    
# Logs: 
# ulog2
# https://www.maravento.com/2014/07/registros-iptables.html
chown root:root /var/log
nala install -y ulogd2
mkdir -p /var/log/ulog >/dev/null 2>&1
touch /var/log/ulog/syslogemu.log >/dev/null 2>&1
usermod -a -G ulog "$USER"
crontab -l | {
    cat
    echo "#*/10 * * * * /etc/scr/banip.sh"
} | crontab -
echo "Ulog Access: /var/log/ulog/syslogemu.log"
# rsyslog
# in case fails: nala install -y libfastjson4
nala install -y rsyslog
systemctl enable rsyslog.service
    
# Backup: 
# Timeshift
nala install -y timeshift
# FreeFileSync
nala install -y libatk-adaptor libgail-common
# https://www.maravento.com/2014/06/sincronizacion-espejo.html
chmod +x $gp/conf/scr/ffsupdate.sh
$gp/conf/scr/ffsupdate.sh
crontab -l | {
    cat
    echo "@weekly /etc/scr/ffsupdate.sh"
} | crontab -
echo OK
sleep 1

cleanupgrade
fixbroken

### SAMBA (with SHARE folder, Recycle Bin and Audit)
# https://www.maravento.com/2021/12/samba-full-audit.html
clear
echo -e "\n"
while true; do
read -p "${lang_20[$lang]} Samba?
${lang_21[$lang]} (y/n)" answer
    case $answer in
    [Yy]*)
        # execute command yes
        nala install -y samba samba-common samba-common-bin smbclient winbind cifs-utils
        # in case it fails
        #apt -qq install -y --reinstall samba-common samba-common-bin
        systemctl enable smbd.service
        systemctl enable nmbd.service
        systemctl enable winbind.service
        fixbroken
        groupadd -f sambashare
        mkdir -p $(pwd)/"${lang_22[$lang]}"
        chown -R root:sambashare $(pwd)/"${lang_22[$lang]}"
        #chmod 1777 $(pwd)/"${lang_22[$lang]}"
        chmod 755 $(pwd)/"${lang_22[$lang]}"
        usermod -aG sambashare "$local_user"
        mkdir -p $(pwd)/"${lang_22[$lang]}"/DEMO
        echo "this is a demo file" | tee $(pwd)/"${lang_22[$lang]}"/DEMO/demo.txt
        # Protect the DEMO folder inside the shared folder
        for dir in $(find $(pwd)/"${lang_22[$lang]}" -mindepth 1 -maxdepth 1 -type d); do
          chown root:sambashare "$dir"
          chmod 777 "$dir"
        done
        find $gp/conf/samba -type f -print0 | xargs -0 -I "{}" sed -i "s:compartida:${lang_22[$lang]}:g" "{}"
        mkdir -p /var/lib/samba/usershares >/dev/null 2>&1
        chmod 1775 /var/lib/samba/usershares/
        mkdir -p /var/log/samba >/dev/null 2>&1
        sed -i 's/ \$SMBDOPTIONS//' /lib/systemd/system/smbd.service
        sed -i 's/ \$NMBDOPTIONS//' /lib/systemd/system/nmbd.service
        touch /var/log/samba/log.{samba,audit}
        chown root:adm /var/log/samba/log.{samba,audit}
        chmod 640 /var/log/samba/log.{samba,audit}
        usermod -aG adm syslog
        cp -f /etc/logrotate.d/samba{,.bak} &>/dev/null
        cp -f $gp/conf/samba/samba /etc/logrotate.d/samba
        cp -f /etc/samba/smb.conf{,.bak} &>/dev/null
        cp -f $gp/conf/samba/smb.conf /etc/samba/smb.conf
        chmod +x $gp/conf/samba/sambacron.sh
        $gp/conf/samba/sambacron.sh
        chmod +x $gp/conf/samba/sambaload.sh
        $gp/conf/samba/sambaload.sh >>$gp/conf/scr/servicesload.sh
        read -p "${lang_17[$lang]} ${lang_23[$lang]}: " SMBNAME
        if [ "$SMBNAME" ]; then
            smbpasswd -a $SMBNAME
            pdbedit -L
        fi
        # samba-rsyslog
        cp -f /etc/rsyslog.conf{,.bak} &>/dev/null
        sed 's/^[^#]*\($FileOwner syslog\|$FileGroup adm\|$FileCreateMode 0640\|$FileCreateMode 0640\|$DirCreateMode 0755\|$Umask 0022\|$PrivDropToUser syslog\|$PrivDropToGroup syslog\)$/#\1/' -i /etc/rsyslog.conf
        cp -f /etc/rsyslog.d/50-default.conf{,.bak} &>/dev/null
        sed -i "/# First some standard log files.  Log by facility./i # fullaudit\nif \$programname == 'smbd_audit' and not (\$msg contains 'pam_unix') then {\n    action(type=\"omfile\" file=\"/var/log/samba/log.audit\")\n    stop\n}" /etc/rsyslog.d/50-default.conf
        cp -f /etc/logrotate.d/rsyslog{,.bak} &>/dev/null
        sed -i '/sharedscripts/a \    create 0644 syslog adm' /etc/logrotate.d/rsyslog
        logrotate -s /var/lib/logrotate/status -f /etc/logrotate.conf > /dev/null 2>&1 || echo "⚠️ Error: logrotate status fail"
        rm -f /var/lib/logrotate/status.lock &>/dev/null
        if [ -f /var/lib/logrotate/status ]; then
            chmod 640 /var/lib/logrotate/status
            chown root:root /var/lib/logrotate/status
        else
            echo "⚠️ Warning: /var/lib/logrotate/status was not created"
        fi
        echo "Samba Log: /var/log/samba/log.audit"
        echo "check smb.conf: testparm"
        break
        ;;
    [Nn]*)
        # execute command no
        echo NO
        break
        ;;
    *)
        echo
        echo "${lang_07[$lang]}: YES (y) or NO (n)"
        ;;
    esac
done
echo OK
sleep 1

cleanupgrade
fixbroken

### ACLs
echo -e "\n"
echo "Downloading ACLs..."
# Allow IP
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackip/master/bipupdate/lst/allowip.txt -O $aclroute/allowip.txt
# Block words
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/squid/blockwords.txt -O $aclroute/blockwords.txt
# Veto Files
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/smb/vetofiles.txt -O $aclroute/vetofiles.txt
# Block TLDs
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/blocktlds.txt -O $aclroute/blocktlds.txt
# Blackweb
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackweb/master/blackweb.tar.gz
cat blackweb.tar.gz* | tar xzf -
cp blackweb.txt $aclroute/blackweb.txt
echo OK
sleep 1

### ADD CONFIG
echo -e "\n"
echo "Applying Config..."
# squid
cp -f /etc/squid/squid.conf{,.bak} &>/dev/null
cp -f $gp/conf/server/squid.conf /etc/squid/squid.conf
chown root:root /etc/squid/squid.conf
chmod 644 /etc/squid/squid.conf
# dhcp
cp -f /etc/default/isc-dhcp-server{,.bak} &>/dev/null
cp -f $gp/conf/server/isc-dhcp-server /etc/default/isc-dhcp-server
chown root:root /etc/default/isc-dhcp-server
chmod 644 /etc/default/isc-dhcp-server
# netplan
cp -f /etc/netplan/config.yaml{,.bak} &>/dev/null
cp -f $gp/conf/server/config.yaml /etc/netplan/config.yaml
chown root:root /etc/netplan/config.yaml
chmod 600 /etc/netplan/config.yaml
# scripts
cp -fr $gp/conf/scr/* $scr
chown -R root:root $scr/*
chmod -R +x $scr/*
# Choose your security level: "Secure Share Memory" (optional)
#echo 'none /run/shm tmpfs defaults,ro 0 0' | tee -a /etc/fstab &> /dev/null
#echo 'tmpfs /tmp tmpfs defaults,size=30%,nofail,noatime,mode=1777 0 0' | tee -a /etc/fstab &> /dev/null
# alternative
echo 'tmpfs /tmp tmpfs defaults,size=512M,nofail,noatime,mode=1777 0 0' | tee -a /etc/fstab &> /dev/null
echo OK
sleep 1

echo -e "\n"
echo "Proxy Apache Config..."
cp -f /etc/apache2/sites-available/000-default.conf{,.bak} &>/dev/null
sed -i "s_\(#LogLevel info ssl:warn\)_\1\n\tLogLevel warn_" /etc/apache2/sites-available/000-default.conf
sed -i '/DocumentRoot/{
    s/\(DocumentRoot.*\)/\1/g
    r $gp/conf/server/000-add.txt
}' /etc/apache2/sites-available/000-default.conf
mkdir -p /var/www/wpad
cp -fr $gp/conf/wpad/* /var/www/wpad/
cp -f $gp/conf/server/proxy.conf /etc/apache2/sites-available/proxy.conf
chmod 644 /etc/apache2/sites-available/proxy.conf
a2ensite -q proxy.conf
chmod -R 755 /var/www/
grep -qxF 'Listen 0.0.0.0:18800' /etc/apache2/ports.conf || grep -qxF 'Listen 18800' /etc/apache2/ports.conf || echo 'Listen 0.0.0.0:18800' >> /etc/apache2/ports.conf
apachectl -t -D DUMP_INCLUDES -S
echo "WPAD-PAC Proxy Auto Access: http://SERVER_IP:18800/proxy.pac"
echo OK
sleep 1

echo -e "\n"
echo "Adding Parameters..."
tee -a /etc/rsyslog.conf >/dev/null <<EOT
*.none    /var/log/ulog/syslogemu.log
*.none    /usr/local/ddos/ddos.log
EOT

# backup conf files
cp -f /etc/security/limits.conf{,.bak} &>/dev/null
cp -f /etc/systemd/system.conf{,.bak} &>/dev/null
cp -f /etc/systemd/user.conf{,.bak} &>/dev/null
cp -f /etc/sysctl.conf{,.bak} &>/dev/null
cp -f /etc/hosts{,.bak} &>/dev/null

# adding parameters
tee -a /etc/security/limits.conf >/dev/null <<EOT
*       soft    nproc   65535
*       hard    nproc   65535
*       soft    nofile  65535
*       hard    nofile  65535
root    soft    nproc   65535
root    hard    nproc   65535
root    soft    nofile  65535
root    hard    nofile  65535
EOT
tee -a /etc/sysctl.conf >/dev/null <<EOT
# System optimization
fs.file-max = 65535
fs.inotify.max_user_watches = 65535
vm.overcommit_memory = 1
vm.swappiness = 10
# TCP/NET optimization
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 65535
net.ipv4.ip_forward = 1
# Optional
net.ipv4.tcp_congestion_control = bbr
EOT
echo "DefaultLimitNOFILE=65535" | tee -a /etc/systemd/system.conf >/dev/null
echo "DefaultLimitNOFILE=65535" | tee -a /etc/systemd/user.conf >/dev/null
sysctl -p

echo "Apache Config..."
cp -f /etc/apache2/apache2.conf{,.bak} &>/dev/null
#echo 'RequestReadTimeout header=10-20,MinRate=500 body=20,MinRate=500' | tee -a /etc/apache2/apache2.conf # optional
cp -f $gp/conf/server/servername.conf /etc/apache2/conf-available/servername.conf
a2enconf servername
chmod -R 775 /var/www
chown -R www-data:www-data /var/www

# Hardening
cp -f /etc/apache2/conf-available/security.conf{,.bak} &>/dev/null
sed -i "s:ServerSignature On:ServerSignature Off:g" /etc/apache2/conf-available/security.conf
sed -i "s:ServerTokens OS:ServerTokens Prod:g" /etc/apache2/conf-available/security.conf
sed 's/^[#]*\(Header set X-Content-Type-Options: "nosniff"\)$/\1/' -i /etc/apache2/conf-available/security.conf
sed 's/^[#]*\(Header set X-Frame-Options: "sameorigin"\)$/\1/' -i /etc/apache2/conf-available/security.conf
echo 'FileETag None' | tee -a /etc/apache2/conf-available/security.conf
echo 'Header unset ETag' | tee -a /etc/apache2/conf-available/security.conf
echo 'Options all -Indexes' | tee -a /etc/apache2/conf-available/security.conf
# Headers (opcional)
#ln -sf /etc/apache2/mods-available/headers.load /etc/apache2/mods-available/headers.load
a2enmod headers &>/dev/null
# apache reload
systemctl reload apache2.service
echo OK
sleep 1

### APACHE PASSWORD
echo -e "\n"
echo "Create Apache Password: /var/www/..."
echo -e "\n"
htpasswd -c /etc/apache2/.htpasswd "$local_user"
apache2ctl configtest
echo OK
sleep 1

cleanupgrade
fixbroken

### CRONTAB
echo -e "\n"
echo "Add Crontab Tasks..."
crontab -l | {
    cat
    echo "@reboot systemctl daemon-reload
@reboot /etc/scr/clock.sh
@reboot /etc/scr/lock.sh
@reboot /etc/scr/blackusb.sh off
@reboot /etc/scr/serverload.sh
@hourly /etc/scr/servicesload.sh
#*/30 * * * * /etc/scr/serverload.sh
@weekly /etc/scr/cleaner.sh
@weekly /etc/scr/logrotate.sh
@monthly find /usr/local/ddos/* /var/log/* -type f -exec truncate -s 0 {} \;
@monthly journalctl --vacuum-size=500M && systemctl restart systemd-journald.service"
} | crontab -
echo OK
sleep 1

cleanupgrade
fixbroken

### ENDING
# Restart Daemon
systemctl daemon-reexec &>/dev/null
# Update initramfs (optional)
#update-initramfs -u -k all
# create alias "upgrade"
sudo -u "$local_user" bash -c "echo alias upgrade=\"'sudo nala upgrade --purge -y && sudo aptitude -y safe-upgrade && sudo sync && sudo dpkg --configure -a && sudo nala install --fix-broken -y && sudo updatedb && sudo snap refresh'\"" >>/home/"$local_user"/.bashrc
sudo -u "$local_user" bash -c "echo alias server=\"'sudo /etc/scr/serverload.sh'\"" >>/home/"$local_user"/.bashrc
sudo -u "$local_user" bash -c "echo alias cleaner=\"'sudo /etc/scr/cleaner.sh'\"" >>/home/"$local_user"/.bashrc
# snap
snap set system proxy.http!
snap set system proxy.https!
snap refresh snapd
systemctl restart snapd
snap refresh

cleanupgrade
fixbroken

clear
echo -e "\n"
echo "${lang_24[$lang]}"
echo "after reboot, run: systemctl list-units --type service --state running,failed"
read RES
rm -rfv *tar.gz *.sh *.deb *.txt
journalctl --rotate
journalctl --vacuum-time=1s
systemctl restart systemd-journald
systemctl daemon-reexec
systemctl daemon-reload
update-ca-certificates -f
systemctl reload apache2
a2query -s
#apt -qq -y remove --purge `deborphan --guess-all` # optional
#dpkg -l | grep "^rc" | cut -d " " -f 3 | xargs dpkg --purge &> /dev/null # optional
reboot

[ -d "$gp" ] && rm -rf "$gp"
(sleep 2 && rm -- "$SCRIPT_PATH") &
