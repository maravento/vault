#!/usr/bin/env bash
# by maravento.com

# UniOPOS

# SO: Ubuntu 20.04/22.04 x64
# Version: Alpha (Use at your own risk)

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# WGET
wgetd='wget -q --show-progress -c --no-check-certificate --retry-connrefused --timeout=10 --tries=20'

# LOCAL USER
local_user=${SUDO_USER:-$(whoami)}

echo -e "\n"
# CHECKING SO
function checkos() {
    echo "Check OS..."
    is_uversion=$(lsb_release -sc | grep -P 'focal|jammy')
    if [ "$is_uversion" ]; then
        echo "OK. Ubuntu 20.04/22.04"
    else
        echo "Aborted installation. Check Minimum Requirements"
        exit
    fi
}

function x64() {
    echo "Check Architecture x64"
    ARCHITECTURE=$(uname -m)
    if [ "${ARCHITECTURE}" == 'x86_64' ]; then
        echo "OK"
        checkos
    else
        echo "Aborted installation. Check Minimum Requirements"
        exit
    fi
}
x64

clear
echo -e "\n"
echo "    Welcome to uniOPOS Install"
echo "    uniCenta oPOS Point Of Sale + Dependencies"
echo -e "\n"
echo "    Main Package:"
echo "    uniCenta oPOS (Install or WebServer) v4.6.4"
echo "    Dependencies:"
echo "    Stack (LAMP v7.1.33-0 or AMPPS v3.8) and Java SE (1.8.0_212)"
echo "    Optional: Webmin"
echo -e "\n"
echo "    Press ENTER to start or CTRL+C to exit"
echo -e "\n"
read RES
clear
echo -e "\n"

### BASIC ###
killall -s SIGTERM apt apt-get &>/dev/null
fuser -vki /var/lib/dpkg/lock &>/dev/null
rm /var/lib/apt/lists/lock &>/dev/null
rm /var/cache/apt/archives/lock &>/dev/null
rm /var/lib/dpkg/lock &>/dev/null
rm /var/cache/debconf/*.dat &>/dev/null
dpkg --configure -a
pro config set apt_news=false
apt -qq install -y --reinstall systemd-timesyncd
apt -qq install -y nala
timedatectl set-ntp true

## CHECK DEPENDENCIES
echo -e "\n"
echo "Dependencies & Tools Setup. Wait..."
nala install -y curl software-properties-common aptitude mlocate net-tools wget libnotify-bin debconf-utils libaio1 libaio-dev libncurses5 megatools libc6-i386
echo "OK"

# UPDATE
echo -e "\n"
echo "Update. Wait..."
function cleanupgrade() {
    nala upgrade --purge -y
    aptitude safe-upgrade -y
    fc-cache
    sync
    updatedb
}
cleanupgrade
function fixbroken() {
    dpkg --configure -a
    nala install --fix-broken -y
}
fixbroken
echo "OK"

# KILL SERVICES
echo -e "\n"
echo "Kill services. Wait..."
for process in $(ps -ef | grep -i '[a]pache*\|[m]ysql*'); do killall $process &>/dev/null; done
echo "OK"

# JAVA 8 PPA
# Check: dpkg --get-selections | grep java && dpkg --get-selections | grep jdk
echo -e "\n"
# Optional:
#echo "Removing All Java Versions. Wait..."
#dpkg-query -W -f='${binary:Package}\n' | grep -E -e '^(ia32-)?(sun|oracle)-java' -e '^openjdk-' -e '^icedtea' -e '^(default|gcj)-j(re|dk)' -e '^gcj-(.*)-j(re|dk)' -e '^java-common' | xargs apt-get -y remove
#cleanupgrade
#bash -c 'ls -d /home/*/.java' | xargs rm -rf &> /dev/null
#rm -rf /usr/lib/jvm/* &> /dev/null
#updatedb
#echo "OK"
echo "Java 8 Setup. Wait..."
while [ -z "$(java -version 2>&1 | grep 'java version \"1.8')" ]; do
    add-apt-repository ppa:ts.sch.gr/ppa -y &>/dev/null
    echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections
    #apt -qq -y install oracle-java8-set-default
    nala install -y --no-install-recommends oracle-java8-set-default
    java -version
done
echo "OK"

function lamp_download() {
    wget --no-check-certificate --timeout=10 --tries=1 --method=HEAD "$1"
    if [ $? -eq 0 ]; then
        $wgetd "$1"
    else

    fi
}

function lamp_stack() {
    # LAMP SETUP
    # Uninstall: /opt/bitnami/uninstall
    # Start/Stop/Status/Restart: /opt/bitnami/ctlscript.sh start/stop/status/restart
    # To access phpmyadmin on a VPS, edit: # /opt/bitnami/apps/phpmyadmin/conf/httpd-app.conf
    # change: "Allow from 127.0.0.1" for "Allow from all" and "Require local" for "Require all granted"
    echo "LAMP v7.1.33-0 Setup. Wait..."
    echo "Open TCP 80,443,3306 ports in your Firewall"
    kill $(ps aux | grep '[h]ttpd' | awk '{print $2}') &>/dev/null
    lamp_download 'https://downloads.bitnami.com/files/stacks/lampstack/7.1.33-0/bitnami-lampstack-7.1.33-0-linux-x64-installer.run'
    chmod +x bitnami-lampstack-7.1.33-0-linux-x64-installer.run
    # run help for more options: ./bitnami-lampstack-7.1.33-0-linux-x64-installer.run --help
    ./bitnami-lampstack-7.1.33-0-linux-x64-installer.run --mode unattended --prefix /opt/bitnami --enable-components phpmyadmin --disable-components varnish,zendframework,symfony,codeigniter,cakephp,smarty,laravel --base_password uniopos --mysql_password uniopos --phpmyadmin_password uniopos --launch_cloud 0
    fixbroken
    chmod +x /opt/bitnami/manager-linux-x64.run
    chmod +x /opt/bitnami/ctlscript.sh
    /opt/bitnami/ctlscript.sh stop &>/dev/null
    wget -q -N https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/lamp.ico -O /opt/bitnami/img/lamp.ico
    # LAMP LAUNCHER
    cat <<EOF | tee /opt/bitnami/run.sh
#!/usr/bin/env bash
pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY /opt/bitnami/manager-linux-x64.run
EOF
    chmod +x /opt/bitnami/run.sh
    cat <<EOF | tee "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/lamp.desktop" "/home/$local_user/.local/share/applications/lamp.desktop"
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Application
Name=LAMP
Comment=Run Bitnami LAMP
Exec=/opt/bitnami/run.sh
Icon=/opt/bitnami/img/lamp.ico
Path=
Terminal=false
StartupNotify=false
EOF
    chmod +x "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/lamp.desktop" "/home/$local_user/.local/share/applications/lamp.desktop"
    echo "OK"
}

function ampps_download() {
    wget --no-check-certificate --timeout=10 --tries=1 --method=HEAD "$1"
    if [ $? -eq 0 ]; then
        $wgetd "$1"
    else
        megadl 'https://mega.nz/#!CIkW2JAK!dbo-Cs5LONeczEZcW0vwY8SXY7q2EekzgZIpCPLpSLQ'
    fi
}

function ampps_stack() {
    # AMPPS SETUP
    # Ampps: http://localhost/ampps
    # phpmyadmin: http://localhost/phpmyadmin
    # Wiki: http://www.ampps.com/wiki/Installing_AMPPS_on_Linux
    # Download: http://www.ampps.com/downloads
    echo "AMPPS v3.8 Setup. Wait..."
    echo "Open TCP 80,443,3306 ports in your Firewall"
    kill $(ps aux | grep '[h]ttpd' | awk '{print $2}') &>/dev/null
    ampps_download 'http://s4.softaculous.com/a/ampps/files/Ampps-3.8-x86_64.run'
    chmod +x Ampps-3.8-x86_64.run
    ./Ampps-3.8-x86_64.run &>/dev/null
    killall /usr/local/ampps/Ampps httpd mysqld &>/dev/null
    mkdir -p /usr/local/ampps/apache/lib/backup
    mv -fv /usr/local/ampps/apache/lib/libapr* $_ &>/dev/null
    nala install -y libaprutil1 libaprutil1-dev libapr1 libapr1-dev
    fixbroken
    # AMPPS LAUNCHER
    cat <<EOF | tee /usr/local/ampps/run.sh
#!/usr/bin/env bash
pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY QT_X11_NO_MITSHM=1 /usr/local/ampps/Ampps
EOF
    chmod +x /usr/local/ampps/run.sh
    cat <<EOF | tee "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/ampps.desktop" "/home/$local_user/.local/share/applications/ampps.desktop"
[Desktop Entry]
Encoding=UTF-8
Version=1.0
Name=AMPPS
Comment=Run Softaculous AMPPS
Type=Application
Exec=/usr/local/ampps/run.sh
Icon=/usr/local/ampps/ampps/softaculous/enduser/themes/default/images/ampps/softaculousampps.png
Terminal=false
StartupNotify=false
EOF
    chmod +x "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/ampps.desktop" "/home/$local_user/.local/share/applications/ampps.desktop"
    echo "OK"
}

# Servers Stack Install
echo -e "\n"
echo "Servers Stack Setup..."
PS3='Select a number and press Enter (LAMP recommended): '
options=("LAMP" "AMPPS")
select op in "${options[@]}"; do
    case $op in
    "LAMP")
        lamp_stack
        fixbroken
        break
        ;;
    "AMPPS")
        ampps_stack
        fixbroken
        break
        ;;
    *)
        echo "invalid option"
        ;;
    esac
done

function unioposinstall() {
    # UNICENTA OPOS INSTALL
    echo -e "\n"
    echo "Unicenta OPOS v4.6.4 Setup. Wait..."
    megadl 'https://mega.nz/#!eM8gjKpB!58CFp5j7MuR85Z33g7INSHzes5SZfnLQAnapOYEfn9I'
    chmod +x unicentaopos-4.6.4-linux-x64-installer.run
    ./unicentaopos-4.6.4-linux-x64-installer.run --unattendedmodeui none --installer-language en --mode unattended --prefix "/opt/unicentaopos-4.6.4"
    chmod +x /opt/unicentaopos-4.6.4/start.sh
    # UNICENTA OPOS LAUNCHER
    cat <<EOF | tee "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/unicenta.desktop" "/home/$local_user/.local/share/applications/unicenta.desktop"
[Desktop Entry]
Encoding=UTF-8
Version=4.6.4
Name=Unicenta
Comment=Run Unicenta OPOS
Type=Application
Exec=/opt/unicentaopos-4.6.4/start.sh
Icon=/opt/unicentaopos-4.6.4/unicentaopos.ico
Terminal=false
EOF
    chmod +x "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/unicenta.desktop" "/home/$local_user/.local/share/applications/unicenta.desktop"
    echo "OK"
}

function unioposwebserver() {
    # UNICENTA OPOS WEBSERVER
    echo -e "\n"
    echo "Unicenta OPOS v4.6.4 WebServer Setup. Wait..."
    megadl 'https://mega.nz/#!nd8S1TBL!Y6KFKjYrcxmV6scbxb67plIYg5Gspk39-X6IT9Z3W_w'
    tar -xzf unicenta-webserver.tar.gz -C /opt/
    # UNICENTA OPOS WEBSERVER LAUNCHER
    cat <<EOF | tee /opt/unicenta-webserver/run.sh
#!/usr/bin/env bash
cd /opt/unicenta-webserver/
java -jar unicenta-server.war -j jetty.properties
EOF
    chmod +x /opt/unicenta-webserver/run.sh
    echo "OK"
}

# Unicenta OPOS Install
echo -e "\n"
echo "UnicetaOPOS versions"
PS3='Select a number and press Enter: '
options=("INSTALL" "WEBSERVER")
select op in "${options[@]}"; do
    case $op in
    "INSTALL")
        unioposinstall
        fixbroken
        break
        ;;
    "WEBSERVER")
        unioposwebserver
        cp -f /opt/unicenta-webserver/jetty.properties{,.bak}
        sed -i "s:org.webswing.server.host=localhost:org.webswing.server.host=0.0.0.0:g" /opt/unicenta-webserver/jetty.properties
        fixbroken
        break
        ;;
    *)
        echo "invalid option"
        ;;
    esac
done

# WEBMIN
# Access: https://IP:10000/
# MySQL database: https://doxfer.webmin.com/Webmin/MySQL_Database_Server
echo -e "\n"
while true; do
    read -p "Do You Want To Install Webmin (Optional)? (y/n)" answer
    case $answer in
    [Yy]*)
        # execute command yes
        nala install -y apt-transport-https software-properties-common
        wget -q http://www.webmin.com/jcameron-key.asc -O- | gpg --no-default-keyring --keyring gnupg-ring:/etc/apt/trusted.gpg.d/ubuntu-webmin.gpg --import
        chmod 644 /etc/apt/trusted.gpg.d/ubuntu-webmin.gpg
        add-apt-repository -y "deb [arch=amd64] https://download.webmin.com/download/repository sarge contrib" &>/dev/null
        nala install -y webmin
        fixbroken
        cp -f /etc/webmin/apache/config{,.bak}
        wget -q -N https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/webmin/apacheconfig -O /etc/webmin/apache/config
        cp -f /etc/webmin/mysql/config{,.bak}
        wget -q -N https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/webmin/mysqlconfig -O /etc/webmin/mysql/config
        # SYSCTL
        cp -f /etc/sysctl.conf{,.bak}
        sh -c 'echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf'
        # optional
        #sh -c 'echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf'
        echo "OK"
        break
        ;;
    [Nn]*)
        # execute command no
        echo "OK"
        break
        ;;
    *)
        echo
        echo "Answer: YES (y) or NO (n)"
        ;;
    esac
done
echo "Done"
notify-send "UniOPOS Done" "Restart PC" -i checkbox
