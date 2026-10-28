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
# USAGE: ./joomla.sh
#
# Included: Apache/MySQL/PHP/mkcert
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

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

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: joomla start..."

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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

install_joomla() {
    if [ -d "/var/www/html/joomla" ]; then
        echo "Joomla is already installed /var/www/html/joomla"
        exit 1
    fi

    check_ipv4_interfaces
    check_internet

    read -r -sp "Set the password for the MySQL root user: " ROOTPASS
    echo
    read -r -sp "Set the password for the MySQL joomla user: " DBPASS
    echo

    # Escape backslashes and single quotes for safe embedding in SQL string literals
    SQL_ROOTPASS="${ROOTPASS//\\/\\\\}"
    SQL_ROOTPASS="${SQL_ROOTPASS//\'/\'\'}"
    SQL_DBPASS="${DBPASS//\\/\\\\}"
    SQL_DBPASS="${SQL_DBPASS//\'/\'\'}"

    apt update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    apt upgrade -y

    apt install -y apache2 apache2-doc apache2-utils apache2-dev apache2-suexec-pristine libaprutil1t64 libaprutil1-dev libtest-fatal-perl || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install Apache prerequisites -abort" >&2
        exit 1
    }

    apt install -y php php-mysql php-xml php-mbstring php-curl php-zip php-gd libapache2-mod-php php-cli php-intl php-bcmath unzip || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install PHP prerequisites -abort" >&2
        exit 1
    }

    PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"

    if [ -f "$PHP_INI" ]; then
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 256M/' "$PHP_INI"
        sed -i 's/^post_max_size = .*/post_max_size = 256M/' "$PHP_INI"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
        sed -i 's/^output_buffering = .*/output_buffering = off/' "$PHP_INI"
        sed -i 's~^;date.timezone =.*~date.timezone = America/Bogota~' "$PHP_INI"
        echo "php.ini updated in: $PHP_INI"
    else
        echo "$PHP_INI Not found"
    fi

    apt install mysql-server -y
    dpkg --configure -a
    apt install -f

    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${SQL_ROOTPASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

    DB_EXISTS=$(mysql -u root -p"${ROOTPASS}" -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='joomla_db'" 2>/dev/null)
    USER_EXISTS=$(mysql -u root -p"${ROOTPASS}" -sse "SELECT COUNT(*) FROM mysql.user WHERE user = 'joomla_user' AND host = 'localhost'" 2>/dev/null)

    if [ -z "$DB_EXISTS" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Creating joomla_db database..."
        mysql -u root -p"${ROOTPASS}" <<EOF
CREATE DATABASE joomla_db CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
    else
        echo "The joomla_db database already exists. Its creation is skipped"
    fi

    if [ "${USER_EXISTS:-1}" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Creating joomla_user user..."
        mysql -u root -p"${ROOTPASS}" <<EOF
CREATE USER 'joomla_user'@'localhost' IDENTIFIED BY '${SQL_DBPASS}';
GRANT ALL PRIVILEGES ON joomla_db.* TO 'joomla_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    else
        echo "The user joomla_user@localhost already exists. Its creation is skipped"
    fi

    echo "Searching for latest Joomla version"
    LATEST_VERSION=$(curl -sf "https://api.github.com/repos/joomla/joomla-cms/releases/latest" | grep -oP '"tag_name": "\K[0-9.]+')

    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(curl -sf "https://downloads.joomla.org/" | grep -oP 'Joomla_\d+\.\d+\.\d+-Stable-Full_Package\.zip' | sort -V | tail -n 1 | grep -oP '\d+\.\d+\.\d+')
        if [ -z "$LATEST_VERSION" ]; then
            echo "Could not determine latest Joomla version"
            exit 1
        fi
    fi

    echo "Latest version found: $LATEST_VERSION"

    DOWNLOAD_URL="https://update.joomla.org/releases/$LATEST_VERSION/Joomla_$LATEST_VERSION-Stable-Full_Package.zip"

    if ! curl -L -o joomla.zip "$DOWNLOAD_URL"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: $DOWNLOAD_URL"
        rm -f joomla.zip
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: joomla.zip"

    mkdir -p /var/www/html/joomla

    if ! unzip joomla.zip -d /var/www/html/joomla; then
        echo "Error extracting joomla.zip. File may be corrupt"
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
        apt install libnss3-tools -y
        MKCERT_VER=$(curl -sf "https://api.github.com/repos/FiloSottile/mkcert/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
        MKCERT_VER="${MKCERT_VER:-v1.4.4}"
        if ! curl -L -o mkcert "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VER}/mkcert-${MKCERT_VER}-linux-amd64"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VER}/mkcert-${MKCERT_VER}-linux-amd64"
            exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: mkcert"
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: password cannot be empty -abort"
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') Removing Joomla..."
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
    echo "Joomla successfully removed"
}

delete_dependencies() {
    local purge_failed=0
    echo "$(date '+%Y-%m-%d %H:%M:%S') Removing MySQL, Apache2, PHP and mkcert..."
    systemctl stop apache2 mysql
    if ! apt purge --auto-remove mysql-server mysql-client mysql-common apache2 'php*' libapache2-mod-php -y; then
        purge_failed=1
    fi
    rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null
    rm -rf /etc/apache2 /var/www/html 2>/dev/null
    rm -rf /etc/php /var/log/apache2 2>/dev/null
    rm -rf /var/lib/php 2>/dev/null
    rm -f /usr/local/bin/mkcert 2>/dev/null
    rm -f /etc/ssl/certs/localhost.pem
    rm -f /etc/ssl/private/localhost-key.pem
    if [ "$purge_failed" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Dependency data removed, packages pending -alert"
    else
        echo "Dependencies successfully removed"
    fi
}

warning() {
    read -r -p " WARNING: This will remove MySQL/Apache2/PHP/mkcert. Confirm? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        delete_dependencies
    else
        echo "Operation cancelled"
        sleep 1
    fi
}

clear
echo
echo "======== JOOMLA MENU ========"
echo "1) Install Joomla & dependencies"
echo "2) Delete Joomla"
echo "3) Delete MySQL/Apache2/PHP/mkcert"
echo "4) Exit"
read -r -p "Select an option [1-4]: " OPTION

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

OPTION="${OPTION:-4}"

case "$OPTION" in
    1) install_joomla ;;
    2) delete_joomla ;;
    3) warning ;;
    4) ;;
    *) echo "Invalid Option"; exit 1 ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: joomla done"
