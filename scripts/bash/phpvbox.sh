#!/bin/bash
# maravento.com

# phpvirtualbox install
# https://www.maravento.com/2015/02/administrando-vms.html
# Requires Virtualbox 7x

# special thanks to:
# https://github.com/BartekSz95

echo "phpVirtualBox Starting. Wait..."
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
pkgs='bsdutils unzip apache2 libapache2-mod-php php php-soap php-xml'
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

# check Virtualbox 7x
output=$(dpkg -l | grep -P 'virtualbox-\d+\.\d+' | awk '{print $2}')
if echo "$output" | grep -q "virtualbox-7"; then
    true
else
    echo "Aborting. Vbox 7 is not installed"
fi

### VARIABLES
# LOCAL USER (sudo user no root)
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')

### PHPVBOX
# git clone phpvirtualbox
wget -c https://github.com/BartekSz95/phpvirtualbox/archive/main.zip
unzip -q main.zip
# ren config
mv phpvirtualbox-main/config.php-example phpvirtualbox-main/config.php
#mv phpvirtualbox-main/recovery.php-disabled phpvirtualbox-main/recovery.php
# change user
sed -i "s:'vbox':'$local_user':g" phpvirtualbox-main/config.php
# move folder to final path
mv phpvirtualbox-main/ /var/www/html/phpvirtualbox
# set chown
chown -R www-data:www-data /var/www/html/phpvirtualbox
# create virtualbox file config
echo "VBOXWEB_USER=$local_user" | tee /etc/default/virtualbox
echo "VBOXWEB_HOST=localhost" | tee -a /etc/default/virtualbox
# add user to vboxusers group
usermod -aG vboxusers $local_user
# restart services
service apache2 restart
service vboxweb-service stop >/dev/null
service vboxweb-service start

# Creating the script
echo '#!/bin/bash
if pgrep -x vboxwebsrv > /dev/null; then
    echo "vboxweb OK"
  else
    echo "vboxweb starting..."
    service vboxweb-service start
    sleep 10
    # check again
    if pgrep -x vboxwebsrv > /dev/null; then
        echo "vboxweb start successful"
    else
        echo "vboxweb failed to start"
        logger "vboxweb failed to start"
    fi
fi' >/etc/init.d/phpvbox_port.sh
# execution permissions
chmod +x /etc/init.d/phpvbox_port.sh

# Add the task to the crontab
(
    crontab -l
    echo "*/30 * * * * /etc/init.d/phpvbox_port.sh"
) | crontab -
service cron restart
echo "Script and cron task added successfully."
echo
echo "Access: http://localhost/phpvirtualbox"
echo "default user and password: admin"
echo "Use vinagre or remmina to connect (activate Enable Server into Remote Display of VM)"
echo "Done"
