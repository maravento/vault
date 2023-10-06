#!/usr/bin/env bash
# by maravento.com

# UniOPOS No Java

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

# Variables:
wgetd='wget -q -c --show-progress --no-check-certificate --retry-connrefused --timeout=10 --tries=20'

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
echo "    uniCenta oPOS (Install) v5.0-1 Beta (No Java Needed)"
echo "    Dependencies:"
echo "    LAMP v7.1.33-0"
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
kill $(ps aux | grep '[a]pache*' | awk '{print $2}') &>/dev/null
kill $(ps aux | grep '[h]ttpd' | awk '{print $2}') &>/dev/null
kill $(ps aux | grep '[m]ysql*' | awk '{print $2}') &>/dev/null

ps aux | grep mysqld
ps aux | grep mysql
echo "OK"

# LAMP SETUP
# Uninstall: /opt/bitnami/uninstall
# Start/Stop/Status/Restart: /opt/bitnami/ctlscript.sh start/stop/status/restart
# To access phpmyadmin on a VPS, edit: # /opt/bitnami/apps/phpmyadmin/conf/httpd-app.conf
# change: "Allow from 127.0.0.1" for "Allow from all" and "Require local" for "Require all granted"
echo "LAMP v7.1.33-0 Setup. Wait..."
echo "Open TCP 80,443,3306 ports in your Firewall"
kill $(ps aux | grep '[h]ttpd' | awk '{print $2}') &>/dev/null
megadl 'https://mega.nz/#!SF0QAbiL!wlXDlAiPXw3Y3ZA9-hCF5yiBV9-VUM9SE7vdT_8fMlo'
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

# UNICENTA OPOS INSTALL
echo -e "\n"
echo "Unicenta OPOS v5.0-1 Beta Setup. Wait..."
megadl 'https://mega.nz/file/jZMmHapI#q9q13uF-205hLKghzWfZSnk-jTsXWt9Vh8szQ8S6EBg'
chmod +x unicenta-opos_5-0-1_amd64.deb
dpkg -i unicenta-opos_5-0-1_amd64.deb
chmod +x /opt/unicentaopos/bin/unicentaopos
# UNICENTA OPOS LAUNCHER
cat <<EOF | tee "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/unicenta.desktop" "/home/$local_user/.local/share/applications/unicenta.desktop"
[Desktop Entry]
Encoding=UTF-8
Version=5.0
Name=Unicenta
Comment=Run Unicenta OPOS
Type=Application
Exec=/opt/unicentaopos/bin/unicentaopos
Icon=/opt/unicentaopos/lib/app/classes/com/openbravo/images/unicentaopos.ico
Terminal=false
EOF
chmod +x "$(sudo -u $local_user bash -c 'xdg-user-dir DESKTOP')/unicenta.desktop" "/home/$local_user/.local/share/applications/unicenta.desktop"
echo "Done"
