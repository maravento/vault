#!/usr/bin/env bash
# by maravento.com

# Gateproxy

# Note: &>/dev/nul is an abbreviation for >/dev/null 2>&1

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

### LANGUAGE EN-ES ###
lang_01=("Check System..." "Verificando Sistema...")
lang_02=("Aborted installation. Check the Minimum Requirements" "Instalacion Abortada. Verifique los Requisitos Mínimos")
lang_03=("Checking Bandwidth..." "Verificando Ancho de Banda...")
lang_04=("Update and Clean" "Actualización y Limpieza")
lang_05=("Fix Broken Packages" "Arreglando Paquetes Rotos")
lang_06=("Wait..." "Espere...")
#lang_07=("the name of user account" "el nombre de la cuenta de usuario")
lang_08=("Answer" "Responda")
lang_09=("Check Dependencies..." "Verificando Dependencias...")
lang_10=("Older NIC-Ethernet Format Detected" "Se ha detectado formato antiguo NIC-Ethernet")
lang_11=("List of Network Interfaces Detected" "Lista de Interfaces de Red Detectadas")
lang_12=("Public Network Interface (Internet)" "Interfaz de Red Publica (Internet)")
lang_13=("Local Network Interface" "Interfaz de Red Local")
lang_14=("Welcome to GateProxy" "Bienvenido a GateProxy")
lang_15=("Minimum Requirements:" "Requisitos Mínimos:")
lang_16=("Press ENTER to start or CTRL+C to abort" "Presione ENTER para iniciar o CTRL+C para abortar")
lang_17=("Server settings:" "Parametros del servidor:")
lang_18=("Enter" "Introduzca")
lang_19=("You have entered" "Ha introducido")
lang_20=("Do you want to change?" "Desea modificar?")
lang_21=("Do you want to install" "Desea instalar")
lang_22=("with SHARE folder, Recycle Bin and Audit" "con carpeta COMPARTIDA, Papelera Reciclaje y Auditoria")
lang_23=("share" "compartida")
lang_24=("the name of samba user" "el nombre del usuario de samba")
lang_25=("Done. Press ENTER to Reboot" "Terminado. Presione ENTER para Reiniciar")
lang_26=("e.g." "e.j.")

test "${LANG:0:2}" == "en"
en=$?

### CHECK SO ###
clear
echo -e "\n"
echo "${lang_01[${en}]}"
function is_ubuntu() {
    #is_uversion=$(lsb_release -sc | grep -P 'focal|jammy') # optional
    is_uversion=$(lsb_release -sc | grep 'jammy')
    if [ "$is_uversion" ]; then
        echo "OK. Ubuntu 22.04.x"
        #if [ "$(lsb_release -sc | grep 'focal')" ]; then for i in universe multiverse restricted; do add-apt-repository -y $i; done; fi # optional (for 20.04)
    else
        echo "${lang_02[${en}]}"
        exit
    fi
}

function getconf_x64() {
    if [ $(getconf LONG_BIT) = "64" ]; then
        # 64 bit
        echo "OK. 64-Bit System"
    else
        # 32 bit
        echo "Fail. 32-Bit System"
    fi
}

function x64() {
    ARCHITECTURE=$(uname -m)
    if [ "${ARCHITECTURE}" == 'x86_64' ]; then
        getconf_x64
        is_ubuntu
    else
        getconf_x64
        echo "${lang_02[${en}]}"
        exit
    fi
}
x64

### BANDWIDTH ###
clear
echo -e "\n"
echo "${lang_03[${en}]}"
dlmin="1.00"
mb="Mbit/s"
dl=$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple --no-upload | grep 'Download:')
resume=$(curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py | python3 - --simple)
dlvalue=$(echo "$dl" | awk '{print $2}')
dlmb=$(echo "$dl" | awk '{print $3}')

function download() {
    if (($(echo "$dlvalue $dlmin" | awk '{print ($1 < $2)}'))); then
        echo "WARNING! Bandwidth Download Slow: $dlvalue $dlmb < $dlmin $mb (min value)"
    else
        echo OK
    fi
}

if [[ "$mb" == "$dlmb" ]]; then
    download
else
    echo "Incorrect Value. Abort: $resume"
    exit
fi

### VARIABLES AND FOLDERS ###
gp=$(pwd)/gateproxy
zone=/etc/zones
if [ ! -d $zone ]; then mkdir -p $zone; fi &>/dev/null
aclroute=/etc/acl
if [ ! -d $aclroute ]; then mkdir -p $aclroute; fi &>/dev/null
scr=/etc/scr
if [ ! -d $scr ]; then mkdir -p $scr; fi &>/dev/null

# LOCAL USER (sudo user no root)
local_user=${SUDO_USER:-$(whoami)}

### BASIC ###
apt -qq install -y nala curl software-properties-common apt-transport-https aptitude net-tools mlocate plocate git git-gui gitk subversion gist
apt -qq install -y --reinstall systemd-timesyncd
apt -qq remove -y zsys
dpkg --configure -a
fuser -vki /var/lib/dpkg/lock &>/dev/null
hdparm -W /dev/sda &>/dev/null
hwclock -w &>/dev/null
killall apt-get &>/dev/null
killall -s SIGTERM apt apt-get &>/dev/null
pro config set apt_news=false
rm /var/cache/apt/archives/lock &>/dev/null
rm /var/cache/debconf/*.dat &>/dev/null
rm /var/lib/apt/lists/lock &>/dev/null
rm /var/lib/dpkg/lock &>/dev/null
timedatectl set-ntp true &>/dev/null
ubuntu-drivers autoinstall &>/dev/null
#systemctl disable avahi-daemon cups-browser &> /dev/null # optional
ifconfig lo 127.0.0.1
cp /etc/crontab{,.bak} &>/dev/null
crontab /etc/crontab &>/dev/null
cp /etc/apt/sources.list{,.bak} &>/dev/null

### CLEAN | UPDATE ###
clear
echo -e "\n"
function cleanupgrade() {
    echo "${lang_04[${en}]}. ${lang_06[${en}]}"
    nala upgrade --purge -y
    aptitude safe-upgrade -y
    fc-cache
    sync
    updatedb
}

function fixbroken() {
    echo "${lang_05[${en}]}. ${lang_06[${en}]}"
    dpkg --configure -a
    nala install --fix-broken -y
}

cleanupgrade
fixbroken

### PACKAGES ###
clear
echo -e "\n"
echo "${lang_09[${en}]}"

### GATEPROXY ###
echo -e "\n"
if [ -d $gp ]; then rm -rf $gp; fi &>/dev/null
svn export "https://github.com/maravento/vault/trunk/gateproxy" >/dev/null 2>&1

### CONFIG ###
clear
echo -e "\n"
hostnamectl set-hostname "$HOSTNAME"
find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:gateproxy:$HOSTNAME:g" "{}"
# changing name user account in config files
find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:your_user:$local_user:g" "{}"

# public interface
function public_interface() {
    read -p "${lang_18[${en}]} ${lang_12[${en}]} (${lang_26[${en}]} enpXsX): " ETH0
    if [ "$ETH0" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:eth0:$ETH0:g" "{}"
    fi
}

# local interface
function local_interface() {
    read -p "${lang_18[${en}]} ${lang_13[${en}]} (${lang_26[${en}]} enpXsX): " ETH1
    if [ "$ETH1" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:eth1:$ETH1:g" "{}"
    fi
}

function is_interfaces() {
    is_interfaces=$(ifconfig | grep eth0)
    if [ "$is_interfaces" ]; then
        echo "${lang_10[${en}]}"
        echo "${lang_02[${en}]}"
        rm -rf $gp &>/dev/null
        exit
    else
        echo "Check Net Interfaces: OK"
        echo "${lang_11[${en}]}:"
        ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
        public_interface
        local_interface
        echo OK
    fi
}
is_interfaces

### START ###
clear
echo -e "\n"
echo "    ${lang_14[${en}]}"
echo -e "\n"
echo "    ${lang_15[${en}]}"
echo "    GNU/Linux:    Ubuntu 22.04.x x64"
echo "    Processor:    Up to Intel 1x GHz"
echo "    Interfaces:   Public and Local"
echo "    RAM:          4 GB reserved for Squid-Cache"
echo "    HDD/SSD:      100 GB reserved for Squid-Cache"
echo -e "\n"
echo "    ${lang_16[${en}]}"
echo -e "\n"
read RES
clear

### PARAMETERS ###
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
            echo "${lang_08[${en}]}: YES (y) or NO (n)"
            ;;
        esac
    done
}
# gateway
function is_gateway() {
    read -p "${lang_18[${en}]} IP (${lang_26[${en}]} 192.168.0.10): " GATEWAY
    GATEWAYNEW=$(echo "$GATEWAY" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')

    if [ "$GATEWAYNEW" ]; then
        find $gp/conf -type f -print0 | while IFS= read -r -d '' file; do
            sed -i "s:192.168.0.10:$GATEWAYNEW:g" "$file"
        done
        find $gp/acl -type f \( -name "mac-*" -o -name "blockdhcp*" \) -print0 | while IFS= read -r -d '' file; do
            sed -i "s:192.168.0\.:$(echo "$GATEWAYNEW" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" "$file"
        done
        echo "${lang_19[${en}]} IP $GATEWAY and Range :OK"
    fi
}

# netmask
function is_mask1() {
    read -p "${lang_18[${en}]} Netmask (${lang_26[${en}]} 255.255.255.0): " MASK1
    MASKNEW1=$(echo "$MASK1" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$MASKNEW1" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:255.255.255.0:$MASKNEW1:g" "{}"
        echo "${lang_19[${en}]} Netmask $MASK1 :OK"
    fi
}

function is_mask2() {
    read -p "${lang_18[${en}]} Subnet-Mask (${lang_26[${en}]} 24): " MASK2
    MASKNEW2=$(echo "$MASK2" | grep -E '[0-9]')
    if [ "$MASKNEW2" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:/24:/$MASKNEW2:g" "{}"
        echo "${lang_19[${en}]} Subnet-Mask $MASK2 :OK"
    fi
}

# dns primary
function is_dns1() {
    read -p "${lang_18[${en}]} DNS1 (${lang_26[${en}]} 8.8.8.8): " DNS1
    DNSNEW1=$(echo "$DNS1" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$DNSNEW1" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.8.8:$DNSNEW1:g" "{}"
        echo "${lang_19[${en}]} DNS1 $DNS1 :OK"
    fi
}

# dns secondary
function is_dns2() {
    read -p "${lang_18[${en}]} DNS2 (${lang_26[${en}]} 8.8.4.4): " DNS2
    DNSNEW2=$(echo "$DNS2" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$DNSNEW2" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.4.4:$DNSNEW2:g" "{}"
        echo "${lang_19[${en}]} DNS2 $DNS2 :OK"
    fi
}

# localnet
function is_localnet() {
    read -p "${lang_18[${en}]} Localnet (${lang_26[${en}]} 192.168.0.0): " LOCALNET
    LOCALNETNEW=$(echo "$LOCALNET" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$LOCALNETNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.0:$LOCALNETNEW:g" "{}"
        echo "${lang_19[${en}]} Localnet $LOCALNET :OK"
    fi
}

# broadcast
function is_broadcast() {
    read -p "${lang_18[${en}]} Broadcast (${lang_26[${en}]} 192.168.0.255): " BROADCAST
    BROADCASTNEW=$(echo "$BROADCAST" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$BROADCASTNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.255:$BROADCASTNEW:g" "{}"
        echo "${lang_19[${en}]} Broadcast $BROADCAST :OK"
    fi
}

# dhcp range
function is_rangeini() {
    read -p "${lang_18[${en}]} DHCP-RANGE-INI (${lang_26[${en}]} 192.168.0.100): " RANGEINI
    RANGEININEW=$(echo "$RANGEINI" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$RANGEININEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.100:$RANGEININEW:g" "{}"
        echo "${lang_19[${en}]} correct DHCP-RANGE-INI $RANGEINI :OK"
    fi
}

function is_rangeend() {
    read -p "${lang_18[${en}]} DHCP-RANGE-END (${lang_26[${en}]} 192.168.0.250): " RANGEEND
    RANGEENDNEW=$(echo "$RANGEEND" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$RANGEENDNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.250:$RANGEENDNEW:g" "{}"
        echo "${lang_19[${en}]} correct DHCP-RANGE-END $RANGEEND :OK"
    fi
}

# squid port
function is_port() {
    read -p "${lang_18[${en}]} Proxy Port (${lang_26[${en}]} 3128): " PORT
    PORTNEW=$(echo "$PORT" | grep -E '[1-9]')
    if [ "$PORTNEW" ]; then
        find $gp/conf -type f -print0 | xargs -0 -I "{}" sed -i "s:3128:$PORTNEW:g" "{}"
        echo "${lang_19[${en}]} Proxy Port $PORT :OK"
    fi
}

echo -e "\n"
while true; do
    read -p "${lang_17[${en}]}
Gateway 192.168.0.10, Mask 255.255.255.0, Network /24, DNS 8.8.8.8 8.8.4.4,
Localnet 192.168.0.0, Broadcast 192.168.0.255, DHCP-Range ini-100 end-250, Proxy 3128
    ${lang_20[${en}]} (y/n)" answer
    case $answer in
    [Yy]*)
        # execute command yes
        is_ask "${lang_20[${en}]} Gateway 192.168.0.10? (y/n)" "${lang_19[${en}]} IP incorrect" is_gateway
        is_ask "${lang_20[${en}]} Mask 255.255.255.0? (y/n)" "${lang_19[${en}]} Mask incorrect" is_mask1
        is_ask "${lang_20[${en}]} Sub-Mask /24? (y/n)" "${lang_19[${en}]} Sub-Mask incorrect" is_mask2
        is_ask "${lang_20[${en}]} DNS1 8.8.8.8? (y/n)" "${lang_19[${en}]} DNS1 incorrect" is_dns1
        is_ask "${lang_20[${en}]} DNS2 8.8.4.4? (y/n)" "${lang_19[${en}]} DNS2 incorrect" is_dns2
        is_ask "${lang_20[${en}]} Localnet 192.168.0.0? (y/n)" "${lang_19[${en}]} Localnet incorrect" is_localnet
        is_ask "${lang_20[${en}]} Broadcast 192.168.0.255? (y/n)" "${lang_19[${en}]} Broadcast incorrect" is_broadcast
        is_ask "${lang_20[${en}]} DHCP-RANGE-INI 192.168.0.100? (y/n)" "${lang_19[${en}]} IP incorrect" is_rangeini
        is_ask "${lang_20[${en}]} DHCP-RANGE-END 192.168.0.250? (y/n)" "${lang_19[${en}]} IP incorrect" is_rangeend
        is_ask "${lang_20[${en}]} Proxy Port Default 3128? (y/n)" "${lang_19[${en}]} Proxy Port incorrect" is_port
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
        echo "${lang_08[${en}]}: YES (y) or NO (n)"
        ;;
    esac
done

### ESSENTIAL ###
clear
echo -e "\n"
function essential_setup() {
    echo "Essential Packages..."
    # Disk Tools
    nala install -y gparted libfuse2 nfs-common ntfs-3g exfat-fuse gsmartcontrol qdirstat libguestfs-tools gvfs-fuse
    nala install -y --no-install-recommends smartmontools
    # compression
    nala install -y p7zip-full p7zip-rar rar unrar unzip zip unace cabextract arj zlib1g-dev tzdata tar
    # system tools
    nala install -y gawk gir1.2-gtop-2.0 gir1.2-xapp-1.0 javascript-common libjs-jquery libxapp1 rake ruby ruby-did-you-mean ruby-json ruby-minitest ruby-net-telnet ruby-power-assert ruby-test-unit rubygems-integration xapps-common python3-pip libssl-dev libffi-dev python3-dev python3-venv idle3 python3-psutil gtkhash moreutils renameutils libpam0g-dev dh-autoreconf rename wmctrl dos2unix i2c-tools bind9-dnsutils geoip-database neofetch ppa-purge gdebi synaptic pm-utils sharutils wget dpkg pv libnotify-bin inotify-tools expect tcl-expect tree preload xsltproc debconf-utils mokutil uuid-dev libmnl-dev conntrack gcc make autoconf autoconf-archive autogen automake pkg-config deborphan perl lsof finger logrotate linux-firmware util-linux linux-tools-common build-essential module-assistant linux-headers-$(uname -r)
    # mesa (if there any problems, install the package: libegl-mesa0)
    nala install -y mesa-utils
    # file tools
    nala install -y reiserfsprogs reiser4progs xfsprogs jfsutils dosfstools e2fsprogs hfsprogs hfsutils hfsplus mtools nilfs-tools f2fs-tools quota sshfs lvm2 attr jmtpfs
    # Optional: Running a .desktop file in the terminal. e.g.: dex foo.desktop
    nala install -y dex
    update-desktop-database
}
essential_setup
echo OK
sleep 1

cleanupgrade
fixbroken

### GATEPROXY ###
echo -e "\n"
function gateproxy_setup() {
    echo "Gateproxy Packages..."
    sed -i "/127.0.1.1/r $gp/conf/server/hosts.txt" /etc/hosts
    # ACLs
    cp -rf $gp/acl/* "$aclroute"
    chmod -x "$aclroute"/*
    # DHCP: isc-dhcp-server
    nala install -y isc-dhcp-server
    systemctl disable isc-dhcp-server6
    # php
    nala install -y php
    # http server: apache2
    nala install -y apache2 apache2-doc apache2-utils apache2-dev apache2-suexec-pristine libaprutil1 libaprutil1-dev
    systemctl enable apache2.service
    # To fix apache2 error: Syntax error on line 146 of /etc/apache2/apache2.conf | Cannot load /usr/lib/apache2/modules/mod_dnssd.so
    #nala install -y libapache2-mod-dnssd
    # To fix apache2-doc error:
    apt -qq install -y --reinstall apache2-doc
    fixbroken
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    sed -i '/^Listen.*/a Listen 8000\nListen 10100\nListen 10200\nListen 10300' /etc/apache2/ports.conf
    # Proxy: squid-cache
    service squid stop &>/dev/null
    systemctl stop squid.service &>/dev/null
    nala purge -y squid* &>/dev/null
    rm -rf /var/spool/squid/* /var/log/squid/* /etc/squid3 /dev/shm/* &>/dev/null
    nala install -y squid squid-langpack
    fixbroken
    killall -s SIGTERM squid &>/dev/null
    if [ ! -d /var/log/squid ]; then mkdir -p /var/log/squid; fi &>/dev/null
    if [[ ! -f /var/log/squid/{access,cache,store,deny}.log ]]; then touch /var/log/squid/{access,cache,store,deny}.log; fi &>/dev/null
    chown -R proxy:proxy /var/log/squid
    # Web Admin: webmin
    wget -c http://www.webmin.com/jcameron-key.asc -O- | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/ubuntu-webmin.gpg --import
    chmod 644 /etc/apt/trusted.gpg.d/ubuntu-webmin.gpg
    add-apt-repository -y "deb [arch=amd64] https://download.webmin.com/download/repository sarge contrib" &>/dev/null
    cleanupgrade
    nala install -y webmin
    fixbroken
    /usr/share/webmin/install-module.pl $gp/conf/monitor/text-editor.wbm
    find $aclroute -maxdepth 1 -type f | tee /etc/webmin/text-editor/files &>/dev/null
    systemctl enable webmin.service
    echo "Webmin Access: https://localhost:10000"
    # Web Admin: cockpit
    nala install -y cockpit cockpit-storaged cockpit-networkmanager cockpit-packagekit cockpit-machines cockpit-sosreport virt-viewer
    systemctl start cockpit cockpit.socket
    systemctl enable --now cockpit cockpit.socket
    echo "cockpit: http://localhost:9090"
    # Process: glances
    nala install -y glances
    pkill glances &>/dev/null
    wget -q --show-progress -c https://github.com/nicolargo/glances/archive/refs/tags/v3.2.7.tar.gz
    tar -xzf v3.2.7.tar.gz
    cp -f -R glances-3.2.7/glances/outputs/static/public/ /usr/lib/python3/dist-packages/glances/outputs/static/
    systemctl enable glances.service
    sed -i '/ExecStart=\/usr\/bin\/glances -s -B 127.0.0.1/c\ExecStart=\/usr\/bin\/glances -w -B 127.0.0.1 -t 10' /usr/lib/systemd/system/glances.service
    systemctl daemon-reload
    echo "Glances Access: http://127.0.0.1:61208"
    # Net Tools: nbtscan, nmap, wireless-tools
    nala install -y nbtscan nmap python3-nmap wireless-tools
    # Net Traffic: sniffnet
    nala install -y libpcap-dev libasound2-dev libfontconfig1
    lastsniffnet=$(curl -s https://api.github.com/repos/GyulyVGC/sniffnet/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
    wget -c https://github.com/GyulyVGC/sniffnet/releases/download/v${lastsniffnet}/sniffnet.deb
    dpkg -i sniffnet.deb
    setcap 'cap_net_raw,cap_net_admin=eip' /usr/bin/sniffnet
    sed -i -e 's/^Exec=sudo \/usr\/bin\/sniffnet$/Exec=\/usr\/bin\/sniffnet/' -e 's/^Terminal=true$/Terminal=false/' /usr/share/applications/sniffnet.desktop
    # Monitor: lightsquid
    nala install -y libcgi-session-perl libgd-gd2-perl
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
        echo "*/12 * * * * /etc/scr/bandata.sh"
    } | crontab -
    echo "lightsquid: http://localhost/lightsquid/"
    echo "lightsquid: Usernames: /var/www/lightsquid/realname.cfg"
    echo "lightsquid: first time run: /var/www/lightsquid/lightparser.pl"
    echo "lightsquid: check bandata IP cat /etc/acl/{banmonth,bandaily}.txt | uniq"
    # Traffic Reports: Sarg
    nala install -y sarg fonts-liberation fonts-dejavu
    fixbroken
    mkdir -p /var/www/squid-reports
    cp -f /etc/sarg/sarg.conf{,.bak} &>/dev/null
    cp -f $gp/conf/monitor/sarg.conf /etc/sarg/sarg.conf
    chmod -x /etc/sarg/sarg.conf
    cp -f /etc/sarg/usertab{,.bak} &>/dev/null
    cp -f $gp/conf/monitor/usertab /etc/sarg/usertab
    chmod -x /etc/sarg/usertab
    cp -f $gp/conf/monitor/sargaudit.conf /etc/apache2/sites-available/sargaudit.conf
    chmod -x /etc/apache2/sites-available/sargaudit.conf
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
    echo "Sarg Access: http://localhost:10300 or http://SERVER_IP:10300/"
    echo "Sarg Usernames: /etc/sarg/usertab (${lang_26[${en}]} 192.168.0.10 GATEPROXY)"
    # Firewall Iptables Complement: ipset
    nala install -y ipset
    # Firewall Filter: ddos deflate
    mkdir -p /usr/local/ddos
    chown root:root /usr/local/ddos
    tar -xzf $gp/conf/server/ddos.tar.gz
    cp -f -R ddos/* /usr/local/ddos
    chmod 0755 /usr/local/ddos/ddos.sh
    crontab -l | {
        cat
        echo "0-59/1 * * * * /usr/local/ddos/ddos.sh &> /dev/null"
    } | crontab -
    echo "DDOS Deflate IPs Exclude: /usr/local/ddos/ignore"
    echo "DDOS Deflate IPs Ban: /usr/local/ddos/ddos.log"
    # Logs: ulog, rsyslog
    chown root:root /var/log
    nala install -y ulogd2
    if [ ! -d /var/log/ulog ]; then mkdir -p /var/log/ulog && touch /var/log/ulog/syslogemu.log; fi
    usermod -a -G ulog "$USER"
    crontab -l | {
        cat
        echo "#*/10 * * * * /etc/scr/banip.sh"
    } | crontab -
    echo "Ulog: /var/log/ulog/syslogemu.log"
    nala install -y rsyslog
    # in case rsyslog fails: nala install -y libfastjson4
    systemctl enable rsyslog.service
    # Backup: timeshift
    nala install -y timeshift
    # Backup: FreeFileSync
    chmod +x $gp/conf/scr/ffsupdate.sh
    $gp/conf/scr/ffsupdate.sh
    crontab -l | {
        cat
        echo "@weekly /etc/scr/ffsupdate.sh"
    } | crontab -
    # Web Terminal: shellinabox
    nala install -y shellinabox
    echo "Shellinabox Access: https://localhost:4200/"
}
gateproxy_setup
echo OK
sleep 1

cleanupgrade
fixbroken

### SAMBA (with SHARE folder, Recycle Bin and Audit) ###
clear
echo -e "\n"
while true; do
    read -p "${lang_21[${en}]} Samba?
    ${lang_22[${en}]} (y/n)" answer
    case $answer in
    [Yy]*)
        # execute command yes
        nala install -y samba samba-common samba-common-bin smbclient winbind cifs-utils
        #apt -qq install -y --reinstall samba-common samba-common-bin # in case it fails
        systemctl enable smbd.service
        systemctl enable nmbd.service
        systemctl enable winbind.service
        fixbroken
        mkdir -p $(pwd)/"${lang_23[${en}]}"
        chown -R nobody.nogroup $(pwd)/"${lang_23[${en}]}"
        chmod -R a+rwx $(pwd)/"${lang_23[${en}]}"
        find $gp/conf/samba -type f -print0 | xargs -0 -I "{}" sed -i "s:compartida:${lang_23[${en}]}:g" "{}"
        if [ ! -d /var/lib/samba/usershares ]; then mkdir -p /var/lib/samba/usershares; fi
        chmod 1775 /var/lib/samba/usershares/
        chmod +t /var/lib/samba/usershares/
        if [ ! -d /var/log/samba ]; then mkdir -p /var/log/samba; fi
        touch /var/log/samba/audit.log
        mkdir -p /var/www/smbaudit
        touch /var/www/smbaudit/audit.log
        cp -f $gp/conf/samba/smbaudit.conf /etc/apache2/sites-available/smbaudit.conf
        a2ensite -q smbaudit.conf
        cp -f /etc/logrotate.d/samba{,.bak} &>/dev/null
        cp -f $gp/conf/samba/samba /etc/logrotate.d/samba
        cp -f /etc/samba/smb.conf{,.bak} &>/dev/null
        cp -f $gp/conf/samba/smb.conf /etc/samba/smb.conf
        cp -f $gp/conf/samba/libuser.conf /etc/libuser.conf
        sed -i "/SAMBA/r $gp/conf/samba/smbipt.txt" $gp/conf/scr/iptables.sh
        chmod +x $gp/conf/samba/sambacron.sh
        $gp/conf/samba/sambacron.sh
        chmod +x $gp/conf/samba/sambaload.sh
        $gp/conf/samba/sambaload.sh >>$gp/conf/scr/servicesload.sh
        read -p "${lang_18[${en}]} ${lang_24[${en}]}: " SMBNAME
        if [ "$SMBNAME" ]; then
            smbpasswd -a $SMBNAME
            pdbedit -L
        fi
        # samba-rsyslog
        cp -f /etc/rsyslog.conf{,.bak} &>/dev/null
        sed 's/^[^#]*\($FileOwner syslog\|$FileGroup adm\|$FileCreateMode 0640\|$FileCreateMode 0640\|$DirCreateMode 0755\|$Umask 0022\|$PrivDropToUser syslog\|$PrivDropToGroup syslog\)$/#\1/' -i /etc/rsyslog.conf
        cp -f /etc/rsyslog.d/50-default.conf{,.bak} &>/dev/null
        sed -i '/# First some standard log files.  Log by facility./i # fullaudit rule\nif $PRI == 173 then {\n   /var/log/samba/audit.log\n stop\n}' /etc/rsyslog.d/50-default.conf
        cp -f /etc/logrotate.d/rsyslog{,.bak} &>/dev/null
        sed -i "/	sharedscripts/r $gp/conf/samba/smbrsyslog.txt" /etc/logrotate.d/rsyslog
        echo "Samba Audit: http://localhost:10100/audit.log | http://SERVER_IP:10100/audit.log"
        echo "Samba Log: /var/log/samba/audit.log"
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
        echo "${lang_08[${en}]}: YES (y) or NO (n)"
        ;;
    esac
done
echo OK
sleep 1

cleanupgrade
fixbroken

### ACLs ###
echo -e "\n"
echo "Downloading ACLs..."
# Allow IP
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackip/master/bipupdate/lst/allowip.txt -O $aclroute/allowip.txt
# Block TLDs
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/blocktlds.txt -O $aclroute/blocktlds.txt
# Blackweb
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackweb/master/blackweb.tar.gz
cat blackweb.tar.gz* | tar xzf -
cp blackweb.txt $aclroute/blackweb.txt
echo OK
sleep 1

### ADD CONFIG ###
echo -e "\n"
echo "Applying Config..."
cp -f /etc/squid/squid.conf{,.bak} &>/dev/null
cp -f $gp/conf/server/squid.conf /etc/squid/squid.conf
chmod -x /etc/squid/squid.conf
cp -f /etc/default/isc-dhcp-server{,.bak} &>/dev/null
cp -f $gp/conf/server/isc-dhcp-server /etc/default/isc-dhcp-server
cp -f /etc/dhcp/dhclient.conf{,.bak} &>/dev/null
cp -f $gp/conf/server/dhclient.conf /etc/dhcp/dhclient.conf
chmod -x /etc/dhcp/dhclient.conf
cp -f $gp/conf/server/config.yaml /etc/netplan/config.yaml
chmod -x /etc/netplan/config.yaml
cp -fr $gp/conf/scr/* $scr
chown -R root:root $scr/*
chmod -R +x $scr/*
# Choose your security level: "Secure Share Memory" (optional)
#echo 'none /run/shm tmpfs defaults,ro 0 0' | tee --append /etc/fstab &> /dev/null
# alternative
#echo 'tmpfs /tmp tmpfs defaults,size=30%,nofail,noatime,mode=1777 0 0' | tee --append /etc/fstab &> /dev/null
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
chmod -x /etc/apache2/sites-available/proxy.conf
a2ensite -q proxy.conf
chmod -R 755 /var/www/
apachectl -t -D DUMP_INCLUDES -S
echo "WPAD-PAC Proxy Auto Access: http://SERVER_IP:8000/proxy.pac"
echo OK
sleep 1

echo -e "\n"
echo "Adding Parameters..."
tee -a /etc/rsyslog.conf >/dev/null <<EOT
*.none    /var/log/ulog/syslogemu.log
*.none    /usr/local/ddos/ddos.log
EOT

# change value for your limit open files
openfiles="65535"

# change value for your limit watched files (error-enospc)
# note: clean regularly /tmp/
watchedfiles="65535"

# backup conf files
cp -f /etc/security/limits.conf{,.bak} &>/dev/null
cp -f /etc/systemd/system.conf{,.bak} &>/dev/null
cp -f /etc/systemd/user.conf{,.bak} &>/dev/null
cp -f /etc/sysctl.conf{,.bak} &>/dev/null
cp -f /etc/hosts{,.bak} &>/dev/null

# adding parameters
tee -a /etc/security/limits.conf >/dev/null <<EOT
* soft  nproc   $openfiles
* hard  nproc   $openfiles
* soft  nofile  $openfiles
* hard  nofile  $openfiles
root  soft  nproc   $openfiles
root  hard  nproc   $openfiles
root  soft  nofile  $openfiles
root  hard  nofile  $openfiles
EOT
tee -a /etc/sysctl.conf >/dev/null <<EOT
fs.file-max = $openfiles
net.core.somaxconn = $openfiles
vm.overcommit_memory = 1
fs.inotify.max_user_watches = $watchedfiles
net.ipv4.ip_forward=1
vm.swappiness=10
EOT
sh -c 'echo "DefaultLimitNOFILE='$openfiles'" >> /etc/systemd/system.conf'
sh -c 'echo "DefaultLimitNOFILE='$openfiles'" >> /etc/systemd/user.conf'
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

### APACHE PASSWORD ###
echo -e "\n"
echo "Create Apache Password /var/www/..."
echo -e "\n"
#htpasswd -c /etc/apache2/.htpasswd "$USER"
htpasswd -c /etc/apache2/.htpasswd "$local_user"
apache2ctl configtest
echo OK
sleep 1

cleanupgrade
fixbroken

### CRONTAB ###
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

### ENDING ###
# Restart Daemon
systemctl daemon-reexec &>/dev/null
# Update initramfs (optional)
#update-initramfs -u -k all
# Copy HowTo to Desktop..."
sudo -u $local_user bash -c 'cp $(pwd)/gateproxy/howto/gateproxy.pdf "$(xdg-user-dir DESKTOP)/gateproxy.pdf"'
# create alias "upgrade"
sudo -u $local_user bash -c "echo alias upgrade=\"'sudo nala upgrade --purge -y && sudo aptitude -y safe-upgrade && sudo fc-cache && sudo sync && sudo snap refresh && sudo dpkg --configure -a && sudo nala install --fix-broken -y && sudo updatedb'\"" >>/home/$local_user/.bashrc
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
echo "${lang_25[${en}]}"
echo "after reboot, run: systemctl list-units --type service --state running,failed"
read RES
rm -rfv $gp *tar.gz *.sh *.deb *.txt
journalctl --rotate
journalctl --vacuum-time=1s
systemctl restart systemd-journald
#apt -qq -y remove --purge `deborphan --guess-all` # optional
#dpkg -l | grep "^rc" | cut -d " " -f 3 | xargs dpkg --purge &> /dev/null # optional
reboot
