#!/bin/bash
# maravento.com
#
################################################################################
#
# phpvirtualbox install
# https://www.maravento.com/2015/02/administrando-vms.html
# Requires Virtualbox 7x
#
# special thanks to:
# https://github.com/BartekSz95
#
################################################################################

set -euo pipefail

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# cleanup temporary files on exit or error
WORK_DIR="$(pwd)"
cleanup() {
    rm -f "$WORK_DIR/main.zip"
    rm -rf "$WORK_DIR/phpvirtualbox-main"
}
trap cleanup EXIT

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

echo "phpVirtualBox Starting. Wait..."

retry_cmd() {
    local max_attempts=10
    local attempt=1
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "ERROR: command failed after $max_attempts attempts: $*"
            exit 1
        fi
        echo "WARNING: command failed (attempt $attempt/$max_attempts), retrying in 10s: $*"
        attempt=$((attempt + 1))
        sleep 10
    done
}

# check dependencies
pkgs=(bsdutils lsof unzip apache2 libapache2-mod-php php php-soap php-xml)
missing=()
for p in "${pkgs[@]}"; do
    dpkg -s "$p" &>/dev/null || missing+=("$p")
done
unavailable=()
for p in "${missing[@]}"; do
    apt-cache show "$p" &>/dev/null || unavailable+=("$p")
done
if [ "${#unavailable[@]}" -gt 0 ]; then
    echo "Missing dependencies not found in APT:"
    for u in "${unavailable[@]}"; do echo " - $u"; done
    echo "Please install them manually or enable the required repositories."
    exit 1
fi
if [ "${#missing[@]}" -gt 0 ]; then
    echo "Waiting for APT/DPKG locks to be released..."
    APT_LOCK_TIMEOUT=120
    APT_LOCK_ELAPSED=0
    APT_LOCK_FILES=(/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend)
    while lsof "${APT_LOCK_FILES[@]}" >/dev/null 2>&1; do
        if [ "$APT_LOCK_ELAPSED" -ge "$APT_LOCK_TIMEOUT" ]; then
            echo "APT/DPKG locks still held after ${APT_LOCK_TIMEOUT}s. Aborting."
            exit 1
        fi
        echo "Locks still held, waiting... (${APT_LOCK_ELAPSED}s elapsed)"
        sleep 5
        APT_LOCK_ELAPSED=$((APT_LOCK_ELAPSED + 5))
    done
    echo "Installing: ${missing[*]}"
    retry_cmd apt-get -qq update
    if ! retry_cmd apt-get -y install "${missing[@]}"; then
        echo "Error installing: ${missing[*]}"
        exit 1
    fi
else
    echo "Dependencies OK"
fi

# check Virtualbox 7x
output=$(dpkg -l | grep -P 'virtualbox-\d+\.\d+' | awk '{print $2}' || true)
if ! echo "$output" | grep -q "virtualbox-7"; then
    echo "Aborting. Vbox 7 is not installed"
    exit 1
fi

### PHPVBOX
# download phpvirtualbox
retry_cmd wget -q -c https://github.com/BartekSz95/phpvirtualbox/archive/main.zip
DOWNLOAD_SHA256="$(sha256sum main.zip | awk '{print $1}')"
echo "main.zip SHA256: $DOWNLOAD_SHA256"
unzip -q main.zip
# ren config
mv phpvirtualbox-main/config.php-example phpvirtualbox-main/config.php
#mv phpvirtualbox-main/recovery.php-disabled phpvirtualbox-main/recovery.php
# change user
safe_local_user=$(printf '%s' "$local_user" | sed -e 's/[\&:]/\\&/g')
sed -i "0,/var \\\$username/{/var \\\$username/s:'vbox':'$safe_local_user':}" phpvirtualbox-main/config.php
# move folder to final path (remove previous install to avoid nesting on reinstall)
rm -rf /var/www/html/phpvirtualbox
mv phpvirtualbox-main/ /var/www/html/phpvirtualbox
# set chown
chown -R www-data:www-data /var/www/html/phpvirtualbox
# create virtualbox file config
echo "VBOXWEB_USER=$local_user" | tee /etc/default/virtualbox
echo "VBOXWEB_HOST=localhost" | tee -a /etc/default/virtualbox
# add user to vboxusers group if not already a member
if ! id -nG "$local_user" | grep -qw vboxusers; then
    usermod -aG vboxusers "$local_user"
fi
# restart services
if ! service apache2 restart; then
    echo "Failed to restart apache2"
    exit 1
fi
service vboxweb-service stop >/dev/null 2>&1 || true
if ! service vboxweb-service start; then
    echo "Failed to start vboxweb-service"
    exit 1
fi

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

# Add the task to the crontab (skip if already present)
CRON_ENTRY="*/30 * * * * /etc/init.d/phpvbox_port.sh"
if ! crontab -l 2>/dev/null | grep -qF "$CRON_ENTRY"; then
    (crontab -l 2>/dev/null || true; echo "$CRON_ENTRY") | crontab -
fi
if ! service cron restart; then
    echo "Failed to restart cron"
    exit 1
fi
echo "Script and cron task added successfully."
echo
echo "Access: http://localhost/phpvirtualbox"
echo "Default user: admin / Default password: admin"
echo "WARNING: Change the default password immediately after first login."
echo "Go to: Admin menu -> Change Password"
echo "Leaving the default password exposes VirtualBox to unauthorized access."
echo "Use vinagre or remmina to connect (activate Enable Server into Remote Display of VM)"
echo "Done"
