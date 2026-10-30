#!/bin/bash
# maravento.com
#
################################################################################
#
# phpvbox -- phpVirtualBox web interface installer
# FILE: phpvbox.sh
#
# DESCRIPTION:
# Installs phpVirtualBox, a web interface for VirtualBox, under Apache.
# Requires VirtualBox 7.x already installed.
#
# USAGE:
# sudo ./phpvbox.sh
#
################################################################################

set -euo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# cleanup temporary files on exit or error
work_dir="$(pwd)"
cleanup() {
    rm -f "$work_dir/master.zip"
    rm -rf "$work_dir/phpvirtualbox-master"
}
trap cleanup EXIT

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# local_user detection
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no local user; create one with sudo access -abort" >&2
    exit 1
fi
echo "Using local user: $local_user"

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: phpvbox start..."

retry_cmd() {
    local max_attempts=10
    local attempt=1
    local retry_name retry_failure retry_arg
    retry_name="$(basename "$1")"
    retry_failure="$retry_name failed"
    case "$retry_name" in
        apt-get)
            for retry_arg in "$@"; do
                case "$retry_arg" in
                    install) retry_failure="package installation failed"; break ;;
                    update) retry_failure="package list update failed"; break ;;
                esac
            done
            ;;
        curl|wget) retry_failure="$retry_name download failed" ;;
    esac
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $retry_failure -abort" >&2
            exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $retry_name: retry $((attempt + 1))/$max_attempts"
        attempt=$((attempt + 1))
        sleep 10
    done
}

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort" >&2
    exit 1
}

check_ipv4_interfaces
check_internet

# check dependencies
pkgs=(bsdutils lsof unzip apache2 libapache2-mod-php php php-soap php-xml wget procps cron iproute2 libc-bin)
missing=()
for p in "${pkgs[@]}"; do
    [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == *"ok installed"* ]] || missing+=("$p")
done
unavailable=()
for p in "${missing[@]}"; do
    apt-cache show "$p" &>/dev/null || unavailable+=("$p")
done
if [ "${#unavailable[@]}" -gt 0 ]; then
    echo "Missing dependencies not found in APT:"
    for u in "${unavailable[@]}"; do echo " - $u"; done
    echo "Please install them manually or enable required repositories"
    exit 1
fi
if [ "${#missing[@]}" -gt 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Waiting for APT/DPKG locks to be released..."
    apt_lock_timeout=120
    apt_lock_elapsed=0
    apt_lock_files=(/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend)
    while lsof "${apt_lock_files[@]}" >/dev/null 2>&1; do
        if [ "$apt_lock_elapsed" -ge "$apt_lock_timeout" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: APT/DPKG locks still held after ${apt_lock_timeout}s -abort" >&2
            exit 1
        fi
        echo "Locks still held, waiting... (${apt_lock_elapsed}s elapsed)"
        sleep 5
        apt_lock_elapsed=$((apt_lock_elapsed + 5))
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

# ------------------------------------------------------------------------------
# PHPVBOX
# ------------------------------------------------------------------------------

# download phpvirtualbox
retry_cmd wget -q -c https://github.com/phpvirtualbox/phpvirtualbox/archive/master.zip
download_sha256="$(sha256sum master.zip | awk '{print $1}')"
echo "master.zip SHA256: $download_sha256"
unzip -q master.zip
# ren config
mv phpvirtualbox-master/config.php-example phpvirtualbox-master/config.php
#mv phpvirtualbox-master/recovery.php-disabled phpvirtualbox-master/recovery.php
# change user
safe_local_user=$(printf '%s' "$local_user" | sed -e 's/[\&:]/\\&/g')
sed -i "0,/var \\\$username/{/var \\\$username/s:'vbox':'$safe_local_user':}" phpvirtualbox-master/config.php
# move folder to final path (remove previous install to avoid nesting on reinstall)
rm -rf /var/www/html/phpvirtualbox
mv phpvirtualbox-master/ /var/www/html/phpvirtualbox
# set chown
chown -R www-data:www-data /var/www/html/phpvirtualbox
# create virtualbox file config
echo "VBOXWEB_USER=$local_user" | tee /etc/default/virtualbox
echo "VBOXWEB_HOST=localhost" | tee -a /etc/default/virtualbox
# add user to vboxusers group if not already a member
if ! id -nG "$local_user" | grep -qw vboxusers; then
    usermod -aG vboxusers "$local_user"
fi
for apache_php_ini in /etc/php/*/apache2/php.ini; do
    [ -f "$apache_php_ini" ] || continue
    if ! { [ -f "${apache_php_ini}.bak" ] || cp -p "$apache_php_ini" "${apache_php_ini}.bak"; }; then
        echo "ERROR: cannot back up $apache_php_ini -abort" >&2
        exit 1
    fi
    if grep -Eq '^[[:space:]]*;*[[:space:]]*session\.upload_progress\.enabled[[:space:]]*=' "$apache_php_ini"; then
        sed -i 's/^[[:space:]]*;*[[:space:]]*session\.upload_progress\.enabled[[:space:]]*=.*/session.upload_progress.enabled = 0/' "$apache_php_ini" || {
            echo "ERROR: cannot edit $apache_php_ini -abort" >&2
            exit 1
        }
    else
        printf '\nsession.upload_progress.enabled = 0\n' >> "$apache_php_ini" || {
            echo "ERROR: cannot edit $apache_php_ini -abort" >&2
            exit 1
        }
    fi
done

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') vboxweb starting..."
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

# Add the task to /etc/cron.d (single file per project)
cron_tmp=$(mktemp)
printf '%s\n' "*/30 * * * * root /etc/init.d/phpvbox_port.sh" > "$cron_tmp"
install -m 644 -o root -g root "$cron_tmp" /etc/cron.d/phpvbox
rm -f "$cron_tmp"
if ! service cron restart; then
    echo "Failed to restart cron"
    exit 1
fi
echo "Script and cron task added successfully"
echo
echo "Access: http://localhost/phpvirtualbox"
echo "Default user: admin / Default password: admin"
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: change default password immediately after first login"
echo "Go to: Admin menu -> Change Password"
echo "Leaving default password exposes VirtualBox to unauthorized access"
echo "Use vinagre or remmina to connect (activate Enable Server into Remote Display of VM)"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: phpvbox done"
