#!/bin/bash
# maravento.com
#
# Joomla install | remove
# Included: Apache/MySQL/PHP/mkcert
# Tested: Ubuntu 22.04.x / 24.04.x ​​x64

echo "Joomla Starting. Wait..."
printf "\n"

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# checking script execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

install_joomla() {
    if [ -d "/var/www/html/joomla" ]; then
        echo "Joomla is already installed /var/www/html/joomla"
        exit 1
    fi

    # Password
    read -sp "Set the password for the MySQL root user: " ROOTPASS
    echo
    read -sp "Set the password for the MySQL joomla user: " DBPASS
    echo

    # Update
    apt update && apt upgrade -y

    # Apache
    apt install -y apache2 apache2-doc apache2-utils apache2-dev apache2-suexec-pristine libaprutil1t64 libaprutil1-dev libtest-fatal-perl

    # PHP
    apt install -y php php-mysql php-xml php-mbstring php-curl php-zip php-gd libapache2-mod-php php-cli php-intl php-bcmath unzip

    # Detect active PHP version
    PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
    PHP_INI="/etc/php/${PHP_VER}/apache2/php.ini"

    # Make changes to php.ini
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

    # MySQL
    apt install mysql-server -y
    dpkg --configure -a
    apt install -f

    # MySQL Secure Configuration = mysql_secure_installation
    mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOTPASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

    # Create Joomla database and user if they do not exist
    DB_EXISTS=$(mysql -u root -p"${ROOTPASS}" -sse "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='joomla_db'")
    USER_EXISTS=$(mysql -u root -p"${ROOTPASS}" -sse "SELECT COUNT(*) FROM mysql.user WHERE user = 'joomla_user' AND host = 'localhost'")

    if [ -z "$DB_EXISTS" ]; then
        echo "Creando base de datos joomla_db..."
        mysql -u root -p"${ROOTPASS}" <<EOF
CREATE DATABASE joomla_db CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
EOF
    else
        echo "The joomla_db database already exists. Its creation is skipped"
    fi

    if [ "$USER_EXISTS" -eq 0 ]; then
        echo "Creating joomla_user user..."
        mysql -u root -p"${ROOTPASS}" <<EOF
CREATE USER 'joomla_user'@'localhost' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON joomla_db.* TO 'joomla_user'@'localhost';
FLUSH PRIVILEGES;
EOF
    else
        echo "The user joomla_user@localhost already exists. Its creation is skipped"
    fi

    # Joomla
    echo "Searching for the latest Joomla version..."
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/joomla/joomla-cms/releases/latest" | grep -oP '"tag_name": "\K[0-9.]+')

    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(curl -s "https://downloads.joomla.org/" | grep -oP 'Joomla_\d+\.\d+\.\d+-Stable-Full_Package\.zip' | sort -V | tail -n 1 | grep -oP '\d+\.\d+\.\d+')
        if [ -z "$LATEST_VERSION" ]; then
            echo "Could not determine the latest Joomla version."
            exit 1
        fi
    fi

    echo "Latest version found: $LATEST_VERSION"

    DOWNLOAD_URL="https://update.joomla.org/releases/$LATEST_VERSION/Joomla_$LATEST_VERSION-Stable-Full_Package.zip"
    echo "Downloading from: $DOWNLOAD_URL"
    curl -L -o joomla.zip "$DOWNLOAD_URL"

    if [ $? -eq 0 ]; then
        echo "Download completed: joomla.zip"
    else
        echo "Error downloading Joomla."
        exit 1
    fi

    mkdir -p /var/www/html/joomla
    unzip joomla.zip -d /var/www/html/joomla
    chown -R www-data:www-data /var/www/html/joomla
    chmod -R 755 /var/www/html/joomla
    rm joomla.zip

    # phpMyAdmin (Optional)
    #DEBIAN_FRONTEND=noninteractive apt install phpmyadmin -y
    #a2enconf phpmyadmin

    # mkcert
    if ! command -v mkcert &> /dev/null; then
        apt install libnss3-tools -y
        curl -L -o mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64
        chmod +x mkcert
        mv mkcert /usr/local/bin/mkcert
        mkcert -install
    fi

    # Create certificates for localhost
    mkcert localhost
    mkdir -p /etc/ssl/certs && mv localhost.pem /etc/ssl/certs/
    mkdir -p /etc/ssl/private && mv localhost-key.pem /etc/ssl/private/

    # Create VirtualHost SSL
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
    SSLCertificateFile      /etc/ssl/certs/localhost.pem
    SSLCertificateKeyFile   /etc/ssl/private/localhost-key.pem

    <Directory /var/www/html/joomla>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/joomla_error.log
    CustomLog \${APACHE_LOG_DIR}/joomla_access.log combined
</VirtualHost>
EOF

    # Activate VirtualHost HTTP and HTTPS
    a2ensite joomla.conf
    a2enmod ssl
    a2enmod rewrite
    systemctl reload apache2

    echo "Done"
    echo "Access: https://localhost/joomla"
    echo "Config: https://localhost/joomla/administrator/index.php"
    echo
    echo "DB name: joomla_db"
    echo "DB user: joomla_user"
    echo "Password: the one you chose at the beginning of the installation"
    echo "Run mkcert -install for certificates to be trusted automatically"
}

delete_joomla() {
    read -sp "Enter the MySQL root password: " ROOTPASS
    echo
    echo "Removing Joomla..."
    rm -rf /var/www/html/joomla

    mysql -u root -p"${ROOTPASS}" <<EOF
DROP DATABASE IF EXISTS joomla_db;
DROP USER IF EXISTS 'joomla_user'@'localhost';
FLUSH PRIVILEGES;
EOF

    a2dissite joomla.conf
    rm -f /etc/apache2/sites-available/joomla.conf
    systemctl reload apache2
    rm -f ~/certs/localhost.pem ~/certs/localhost-key.pem
    echo "Joomla successfully removed"
}

delete_dependencies() {
    echo "Removing MySQL, Apache2, PHP and mkcert..."

    # Stop services
    systemctl stop apache2 mysql

    # Remove packages
    apt purge --auto-remove mysql-server mysql-client mysql-common apache2 php* libapache2-mod-php -y

    # Delete configurations and databases
    rm -rf /etc/mysql /var/lib/mysql /var/log/mysql 2>/dev/null
    rm -rf /etc/apache2 /var/www/html 2>/dev/null
    rm -rf /etc/php /var/log/apache2 2>/dev/null
    rm -rf /var/lib/php 2>/dev/null

    # Delete certificates created with mkcert
    rm -rf ~/certs 2>/dev/null
    rm -f /usr/local/bin/mkcert 2>/dev/null
    rm -f /etc/ssl/certs/localhost.pem
    rm -f /etc/ssl/private/localhost-key.pem

    echo "Dependencies successfully removed"
}

warning() {
    read -p "⚠️ WARNING: This will remove MySQL/Apache2/PHP/mkcert. Confirm? (y/n): " confirm
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
echo " 1)  Install Joomla & dependencies"
echo " 2)  Delete Joomla"
echo " 3)  Delete MySQL/Apache2/PHP/mkcert"
echo " 4)  Exit"
read -p "Select an option [1-4]: " OPTION

case $OPTION in
    1) install_joomla ;;
    2) delete_joomla ;;
    3) warning ;;
    4) echo "Exit"; exit 0 ;;
    *) echo "Invalid Option"; exit 1 ;;
esac
