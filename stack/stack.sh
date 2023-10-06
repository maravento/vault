#!/usr/bin/env bash
# by maravento.com

# Stack

# SO: Ubuntu 20.04/22.04 x64

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

# LOCAL USER
local_user=${SUDO_USER:-$(whoami)}

echo "Starting installation..."

### BASIC ###
killall -s SIGTERM apt apt-get &>/dev/null
fuser -vki /var/lib/dpkg/lock &>/dev/null
rm /var/lib/apt/lists/lock &>/dev/null
rm /var/cache/apt/archives/lock &>/dev/null
rm /var/lib/dpkg/lock &>/dev/null
rm /var/cache/debconf/*.dat &>/dev/null
dpkg --configure -a
pro config set apt_news=false
apt -qq install -y nala

### CHECK DEPENDENCIES ###
nala install -y curl software-properties-common aptitude mlocate net-tools wget libnotify-bin debconf-utils libaio1 libaio-dev libncurses5 megatools libc6-i386

### CLEAN | UPDATE ###

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

### KILL SERVICES ###

echo "Kill services. Wait..."
for process in $(ps -ef | grep -i '[a]pache*\|[m]ysql*'); do killall $process &>/dev/null; done
echo "OK"

### STACK ###

function lamp_stack() {
    # LAMP SETUP
    # Uninstall: /opt/bitnami/uninstall
    # Start/Stop/Status/Restart: /opt/bitnami/ctlscript.sh start/stop/status/restart
    # To access phpmyadmin on a VPS, edit: # /opt/bitnami/apps/phpmyadmin/conf/httpd-app.conf
    # change: "Allow from 127.0.0.1" for "Allow from all" and "Require local" for "Require all granted"
    # Open TCP 80,443,3306 ports in your Firewall
    echo "Download LAMP v7.1.33-0 from Mega. Wait..."
    megadl 'https://mega.nz/#!SF0QAbiL!wlXDlAiPXw3Y3ZA9-hCF5yiBV9-VUM9SE7vdT_8fMlo'
    chmod +x bitnami-lampstack-7.1.33-0-linux-x64-installer.run
    echo "OK"
    echo "Installing LAMP. Wait..."
    # run help for more options: ./bitnami-lampstack-7.1.33-0-linux-x64-installer.run --help
    ./bitnami-lampstack-7.1.33-0-linux-x64-installer.run --mode unattended --prefix /opt/bitnami --enable-components phpmyadmin --disable-components varnish,zendframework,symfony,codeigniter,cakephp,smarty,laravel --base_password lampstack --mysql_password lampstack --phpmyadmin_password lampstack --launch_cloud 0
    echo "OK"
    echo "Configuring LAMP. Wait..."
    fixbroken
    chmod +x /opt/bitnami/manager-linux-x64.run
    chmod +x /opt/bitnami/ctlscript.sh
    /opt/bitnami/ctlscript.sh stop &>/dev/null
    wget -q -N https://raw.githubusercontent.com/maravento/vault/master/stack/img/lamp.ico -O /opt/bitnami/img/lamp.ico
    # LAMP LAUNCHER
    cat <<'EOF' | tee /opt/bitnami/run.sh
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

function ampps_stack() {
    # AMPPS SETUP
    # Ampps: http://localhost/ampps
    # phpmyadmin: http://localhost/phpmyadmin
    # Wiki: http://www.ampps.com/wiki/Installing_AMPPS_on_Linux
    # Download: http://www.ampps.com/downloads
    # Open TCP 80,443,3306 ports in your Firewall
    echo "Downloading AMPPS v3.8 from Mega. Wait..."
    megadl 'https://mega.nz/#!CIkW2JAK!dbo-Cs5LONeczEZcW0vwY8SXY7q2EekzgZIpCPLpSLQ'
    chmod +x Ampps-3.8-x86_64.run
    echo "OK"
    echo "Installing AMPPS v3.8. Wait..."
    ./Ampps-3.8-x86_64.run &>/dev/null
    echo "OK"
    echo "Configuring AMPPS v3.8. Wait..."
    killall /usr/local/ampps/Ampps httpd mysqld &>/dev/null
    mkdir -p /usr/local/ampps/apache/lib/backup
    mv -fv /usr/local/ampps/apache/lib/libapr* $_ &>/dev/null
    nala install -y libaprutil1 libaprutil1-dev libapr1 libapr1-dev
    fixbroken
    # AMPPS LAUNCHER
    cat <<'EOF' | tee /usr/local/ampps/run.sh
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
clear
echo -e "\n"
echo "Servers Stack Setup..."
PS3='Select a number and press Enter: '
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

cleanupgrade
fixbroken

echo "Done"
