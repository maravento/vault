#!/bin/bash
# maravento.com
#
################################################################################
#
# Joomla install | remove
# FILE: joomla.sh
#
# DESCRIPTION: Interactive menu to install Joomla with its Apache/MySQL/PHP
# stack and local mkcert certificates, remove Joomla only, or remove the
# whole stack. Run as root.
#
# USAGE:
# COMMAND              ACTION
# sudo bash joomla.sh  Run (no arguments)
#
# Included: Apache/MySQL/PHP/mkcert
#
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: joomla start..."

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

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

install_php_hardening() (
    local conf_dir="${1%/*}/conf.d" target staged
    [ -d "$conf_dir" ] || return 1
    target="$conf_dir/99-project-php-hardening.ini"
    staged=$(mktemp -- "$target.XXXXXXXX") || return 1
    trap 'rm -f -- "$staged"' EXIT
    cat > "$staged" <<'PHP_HARDENING' || return 1
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
allow_url_include = Off
enable_dl = Off
session.use_strict_mode = 1
session.use_only_cookies = 1
session.cookie_httponly = 1
session.upload_progress.enabled = 0
file_uploads = Off
upload_max_filesize = 2M
post_max_size = 8M
max_file_uploads = 20
PHP_HARDENING
    [ ! -L "$target" ] || return 1
    if [ -e "$target" ]; then
        [ -f "$target" ] || return 1
        if cmp -s -- "$staged" "$target" && [ "$(stat -c %a -- "$target")" = 644 ]; then
            return 0
        fi
        [ -f "$target.bak" ] || cp -p -- "$target" "$target.bak" || return 1
    fi
    chmod 0644 -- "$staged" && mv -fT -- "$staged" "$target"
)

retry_cmd() {
    [ "$#" -ge 2 ] || return 2
    local retry_label="$1" retry_attempt retry_status
    shift
    for retry_attempt in 1 2 3; do
        if "$@"; then
            return 0
        else
            retry_status=$?
        fi
        [ "$retry_attempt" -lt 3 ] || return "$retry_status"
        if declare -F log >/dev/null; then
            log "INFO: $retry_label: retry $((retry_attempt + 1))/3" >&2
        else
            printf '%s INFO: %s: retry %s/3\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "$retry_label" \
                "$((retry_attempt + 1))" >&2
        fi
        sleep 5
    done
}

# Download with the rules.md labels; a failed file is removed
get_file() {
    local source_url="$1" target_file="$2" http_code curl_status
    http_code=$(curl -sL --retry 2 --connect-timeout 10 -w '%{http_code}' -o "$target_file" "$source_url")
    curl_status=$?
    case "$http_code" in
        200)
            if [ "$curl_status" -eq 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: $(basename "$target_file")"
                return 0
            fi
            echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: $source_url" ;;
        000) echo "$(date '+%Y-%m-%d %H:%M:%S') TIMEOUT: $source_url" ;;
        5*) echo "$(date '+%Y-%m-%d %H:%M:%S') BUSY: $http_code $source_url" ;;
        404|410) echo "$(date '+%Y-%m-%d %H:%M:%S') BROKEN: $http_code $source_url" ;;
        *) echo "$(date '+%Y-%m-%d %H:%M:%S') HTTP_ERROR: $http_code $source_url" ;;
    esac
    rm -f "$target_file"
    return 1
}

# dependencies (network checks, before the menu)
net_checked=0
for dep in iproute2 libc-bin coreutils grep sed unzip curl; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
                # the download proves link and internet; only IPv4 is left to check
                check_ipv4_interfaces
            else
                check_ipv4_interfaces
                check_internet
            fi
            apt-get update -qq || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2; exit 1; }
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing $dep"
        if ! apt-get install -y "$dep" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

# Ask a password; empty answers retry, 3 empty answers abort
read_password() {
    local answer attempt
    for attempt in 1 2 3; do
        read -r -sp "$1" answer
        echo >&2
        if [ -n "$answer" ]; then
            printf '%s' "$answer"
            return 0
        fi
        [ "$attempt" -lt 3 ] && echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: password cannot be empty -retry" >&2
    done
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: password cannot be empty -abort" >&2
    return 1
}

install_joomla() {
    if [ -d "/var/www/html/joomla" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Joomla already installed -skip"
        return 0
    fi

    check_ipv4_interfaces
    check_internet

    # existing configurations that will be modified: ask first
    local existing_configs=() apache_php_ini config_answer
    for apache_php_ini in /etc/php/*/apache2/php.ini; do
        [ -f "$apache_php_ini" ] && existing_configs+=("$apache_php_ini")
    done
    if [ "${#existing_configs[@]}" -gt 0 ]; then
        echo "Joomla will modify these existing configurations:"
        printf ' %s\n' "${existing_configs[@]}"
        read -r -p "Continue with these changes? [y/N]: " config_answer || config_answer=""
        case "${config_answer,,}" in
            y|yes) ;;
            *) echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installation cancelled"; return 0 ;;
        esac
    fi

    ROOTPASS=$(read_password "Set the password for the MySQL root user: ") || exit 1
    DBPASS=$(read_password "Set the password for the MySQL joomla user: ") || exit 1

    # Escape backslashes and single quotes for safe embedding in SQL string literals
    SQL_ROOTPASS="${ROOTPASS//\\/\\\\}"
    SQL_ROOTPASS="${SQL_ROOTPASS//\'/\'\'}"
    SQL_DBPASS="${DBPASS//\\/\\\\}"
    SQL_DBPASS="${SQL_DBPASS//\'/\'\'}"

    retry_cmd "update package lists" apt update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    retry_cmd "update packages" apt upgrade -y

    retry_cmd "install packages" apt install -y apache2 apache2-bin apache2-data apache2-doc apache2-utils || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install Apache prerequisites -abort" >&2
        exit 1
    }
    # apache2-doc breaks after apache2 installs or upgrades; reinstall it always
    retry_cmd "install packages" apt -qq install -y --reinstall apache2-doc || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot reinstall apache2-doc -abort" >&2
        exit 1
    }

    retry_cmd "install packages" apt install -y php php-mysql php-xml php-mbstring php-curl php-zip php-gd libapache2-mod-php php-cli php-intl php-bcmath || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install PHP prerequisites -abort" >&2
        exit 1
    }

    PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"

    if [ -f "$PHP_INI" ]; then
        if ! { [ -f "${PHP_INI}.bak" ] || cp -p "$PHP_INI" "${PHP_INI}.bak"; }; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot back up $PHP_INI -abort" >&2
            exit 1
        fi
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
        sed -i 's/^output_buffering = .*/output_buffering = off/' "$PHP_INI"
        sed -i 's~^;date.timezone =.*~date.timezone = America/Bogota~' "$PHP_INI"
        install_php_hardening "$PHP_INI" || {
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot edit $PHP_INI -abort" >&2
            exit 1
        }
        echo "php.ini updated in: $PHP_INI"
    else
        echo "$PHP_INI Not found"
    fi

    retry_cmd "install packages" apt install mysql-server -y
    dpkg --configure -a
    retry_cmd "install packages" apt install -f

    secure_sql=$(cat <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${SQL_ROOTPASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
)
    # A reinstall keeps MySQL: root then only accepts its current password
    if ! mysql -u root <<<"$secure_sql" 2>/dev/null &&
        ! mysql -u root -p"${ROOTPASS}" <<<"$secure_sql" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [1/2] cannot log in to MySQL as root" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [2/2] use its current root password -abort" >&2
        exit 1
    fi

    DB_EXISTS=$(mysql -u root -p"${ROOTPASS}" -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='joomla_db'" 2>/dev/null) || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot query MySQL -abort" >&2
        exit 1
    }
    USER_EXISTS=$(mysql -u root -p"${ROOTPASS}" -sse "SELECT COUNT(*) FROM mysql.user WHERE user = 'joomla_user' AND host = 'localhost'" 2>/dev/null) || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot query MySQL -abort" >&2
        exit 1
    }

    if [ -z "$DB_EXISTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating joomla_db database..."
        mysql -u root -p"${ROOTPASS}" <<EOF || {
CREATE DATABASE joomla_db CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create joomla_db -abort" >&2
            exit 1
        }
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: joomla_db exists -skip"
    fi

    if [ "${USER_EXISTS:-1}" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Creating joomla_user user..."
        mysql -u root -p"${ROOTPASS}" <<EOF || {
CREATE USER 'joomla_user'@'localhost' IDENTIFIED BY '${SQL_DBPASS}';
GRANT ALL PRIVILEGES ON joomla_db.* TO 'joomla_user'@'localhost';
FLUSH PRIVILEGES;
EOF
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create joomla_user -abort" >&2
            exit 1
        }
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: joomla_user exists -skip"
    fi

    LATEST_VERSION=$(curl -sf "https://api.github.com/repos/joomla/joomla-cms/releases/latest" | grep -oP '"tag_name": "\K[0-9.]+')

    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(curl -sf "https://downloads.joomla.org/" | grep -oP 'Joomla_\d+\.\d+\.\d+-Stable-Full_Package\.zip' | sort -V | tail -n 1 | grep -oP '\d+\.\d+\.\d+')
        if [ -z "$LATEST_VERSION" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot get latest Joomla version -abort" >&2
            exit 1
        fi
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: latest Joomla version: $LATEST_VERSION"

    DOWNLOAD_URL="https://update.joomla.org/releases/$LATEST_VERSION/Joomla_$LATEST_VERSION-Stable-Full_Package.zip"

    get_file "$DOWNLOAD_URL" joomla.zip || exit 1

    mkdir -p /var/www/html/joomla

    if ! unzip joomla.zip -d /var/www/html/joomla; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot extract joomla.zip -abort" >&2
        rm -f joomla.zip
        rm -rf /var/www/html/joomla
        exit 1
    fi

    if ! chown -R www-data:www-data /var/www/html/joomla; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set Joomla owner and group -abort" >&2
        exit 1
    fi
    if ! chmod -R 755 /var/www/html/joomla; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set Joomla permissions -abort" >&2
        exit 1
    fi
    rm -f joomla.zip

    if ! command -v mkcert &>/dev/null; then
        retry_cmd "install packages" apt install libnss3-tools -y
        MKCERT_VER=$(curl -sf "https://api.github.com/repos/FiloSottile/mkcert/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
        MKCERT_VER="${MKCERT_VER:-v1.4.4}"
        get_file "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VER}/mkcert-${MKCERT_VER}-linux-amd64" mkcert || exit 1
        if ! { chmod +x mkcert \
            && mv mkcert /usr/local/bin/mkcert; }; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot deploy mkcert -abort" >&2
            exit 1
        fi
        mkcert -install
    fi

    mkcert localhost
    if ! { mkdir -p /etc/ssl/certs && mv localhost.pem /etc/ssl/certs/; }; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot publish certificate -abort" >&2
        exit 1
    fi
    if ! { mkdir -p /etc/ssl/private && mv localhost-key.pem /etc/ssl/private/; }; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot publish certificate key -abort" >&2
        exit 1
    fi

    cat <<EOF | tee /etc/apache2/sites-available/joomla.conf > /dev/null
<VirtualHost *:80>
    ServerAdmin joomla_user@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html/joomla>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        php_admin_flag file_uploads On
        php_admin_value upload_max_filesize 256M
        php_admin_value post_max_size 256M
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/joomla_error.log
    CustomLog \${APACHE_LOG_DIR}/joomla_access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin joomla_user@localhost
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/localhost.pem
    SSLCertificateKeyFile /etc/ssl/private/localhost-key.pem

    <Directory /var/www/html/joomla>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        php_admin_flag file_uploads On
        php_admin_value upload_max_filesize 256M
        php_admin_value post_max_size 256M
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/joomla_error.log
    CustomLog \${APACHE_LOG_DIR}/joomla_access.log combined
</VirtualHost>
EOF

    a2ensite joomla.conf
    a2enmod ssl
    a2enmod rewrite
    systemctl reload apache2

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Joomla installed and Apache reloaded"
    echo "Access: https://localhost/joomla"
    echo "Config: https://localhost/joomla/administrator/index.php"
    echo
    echo "DB name: joomla_db"
    echo "DB user: joomla_user"
    echo "Password: one you chose at beginning of installation"
    echo "Run mkcert -install for certificates to be trusted automatically"
}

delete_joomla() {
    read -r -sp "Enter the MySQL root password: " ROOTPASS
    echo
    if [ -z "$ROOTPASS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: password cannot be empty -abort" >&2
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Removing Joomla..."
    rm -rf /var/www/html/joomla

    mysql -u root -p"${ROOTPASS}" <<EOF
DROP DATABASE IF EXISTS joomla_db;
DROP USER IF EXISTS 'joomla_user'@'localhost';
FLUSH PRIVILEGES;
EOF

    a2dissite joomla.conf
    rm -f /etc/apache2/sites-available/joomla.conf
    systemctl reload apache2
    rm -f /etc/ssl/certs/localhost.pem /etc/ssl/private/localhost-key.pem
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Joomla removed"
}

# Asks "$1" and returns 0 only on y/Y; Enter or anything else is No
confirm_component() {
    local answer
    read -r -p "$1 (y/N): " answer || answer=""
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Removes one component; logs a WARNING if apt cannot purge its packages
purge_component() {
    local label="$1"; shift
    if ! apt purge --auto-remove -y "$@"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: $label data removed, packages pending -alert"
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $label removed"
}

# Each stack is confirmed on its own: the user may keep any of them. Each one
# removes only the packages install_joomla installed for it; --auto-remove
# takes the dependencies apt pulled in with them
delete_dependencies() {
    if confirm_component "Remove MySQL? It deletes ALL databases in /var/lib/mysql"; then
        systemctl stop mysql 2>/dev/null
        purge_component MySQL mysql-server
        rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: MySQL kept -skip"
    fi
    if confirm_component "Remove Apache2? It deletes ALL sites in /var/www/html"; then
        systemctl stop apache2 2>/dev/null
        purge_component Apache2 apache2 apache2-bin apache2-data apache2-doc apache2-utils
        rm -rf /etc/apache2 /var/www/html /var/log/apache2 2>/dev/null
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Apache2 kept -skip"
    fi
    if confirm_component "Remove PHP and the modules Joomla installed?"; then
        purge_component PHP php php-mysql php-xml php-mbstring php-curl php-zip php-gd \
            libapache2-mod-php php-cli php-intl php-bcmath
        rm -rf /etc/php /var/lib/php 2>/dev/null
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: PHP kept -skip"
    fi
    if confirm_component "Remove mkcert and its localhost certificate?"; then
        rm -f /usr/local/bin/mkcert /etc/ssl/certs/localhost.pem /etc/ssl/private/localhost-key.pem
        purge_component mkcert libnss3-tools
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: mkcert kept -skip"
    fi
}

echo ""
echo "==== Joomla Installation Menu ===="
echo "1) Install Joomla & dependencies"
echo "2) Delete Joomla"
echo "3) Delete MySQL/Apache2/PHP/mkcert"
echo "4) Exit"
read -r -p "Select an option [1-4]: " OPTION
echo ""

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

OPTION="${OPTION:-4}"

case "$OPTION" in
    1) install_joomla ;;
    2) delete_joomla ;;
    3) delete_dependencies ;;
    4) ;;
    *) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2; exit 1 ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: joomla done"
