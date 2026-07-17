#!/bin/bash
# maravento.com
#
################################################################################
#
# Squid SSL-Bump Installer
#
################################################################################

echo "Squid SSL-Bump. Wait..."
echo

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

CA_CERT_D=/usr/local/share/ca-certificates

# Function: Remove regular squid and install squid-openssl
remove_and_install_squid_openssl() {
    echo "Backing up /etc/squid/squid.conf..."
    BACKUP_CONF=$(mktemp /tmp/squid.conf.bak.XXXXXX)
    [ -f /etc/squid/squid.conf ] && cp /etc/squid/squid.conf "$BACKUP_CONF"

    echo "Removing old squid..."
    apt purge -y squid* &>/dev/null
    rm -rf /var/spool/squid* /var/log/squid* /etc/squid*
    rm -f "$CA_CERT_D/squid_proxyCA.crt"

    echo "Installing squid-openssl..."
    apt update || { echo "ERROR: apt update failed"; exit 1; }
    apt install -y squid-openssl squid-langpack squid-common squidclient squid-purge || {
        echo "ERROR: Failed to install squid-openssl packages"
        exit 1
    }

    # Restore previous configuration
    if [ -f "$BACKUP_CONF" ]; then
        mkdir -p /etc/squid
        cp "$BACKUP_CONF" /etc/squid/squid.conf
    fi

    mkdir -p /var/log/squid
    touch /var/log/squid/{access,cache,store,deny}.log
    chown -R proxy:proxy /var/log/squid

    systemctl enable squid.service
}


# Function: Configure SSL-Bump
ssl_bump_setup() {
    CERT_D=/etc/squid/cert
    CERT=$CERT_D/squid_proxyCA.pem
    rm -rf "$CERT"
    mkdir -p "$CERT_D"

    echo "Generating SSL certificate..."
    umask 077
    openssl req -new -newkey rsa:4096 -sha256 -days 365 -nodes -x509 \
        -keyout "$CERT" -out "$CERT"

    chown -R proxy:proxy "$CERT_D"
    chmod 0400 "$CERT"

    echo "Adding certificate to system..."
    CA_CERT_D=/usr/local/share/ca-certificates
    mkdir -p "$CA_CERT_D"
    openssl x509 -inform PEM -in "$CERT" -out "$CA_CERT_D/squid_proxyCA.crt"
    update-ca-certificates

    SSL_DB=/var/spool/squid/ssl_db
    if [ -f /usr/lib/squid/security_file_certgen ]; then
        echo "Initializing SSL certificate database..."
        rm -rf "$SSL_DB"
        /usr/lib/squid/security_file_certgen -c -s "$SSL_DB" -M 4MB
        chown -R proxy:proxy "$SSL_DB"
        chmod 700 "$SSL_DB"
    else
        echo "Error: security_file_certgen not found. Is squid-openssl properly installed?"
        exit 1
    fi
}

for dep in openssl update-ca-certificates; do
    if ! command -v "$dep" &>/dev/null; then
        echo "ERROR: '$dep' is not installed. Run: sudo apt install ca-certificates openssl"
        exit 1
    fi
done

# Check if squid is installed
if ! dpkg -l | grep -qw squid; then
    echo "Squid is not installed. Installing squid-openssl..."
    # Only install squid-openssl if it's not installed
    apt update || { echo "ERROR: apt update failed"; exit 1; }
    apt install -y squid-openssl squid-langpack squid-common squidclient squid-purge || {
        echo "ERROR: Failed to install squid-openssl packages"
        exit 1
    }
elif dpkg -l | grep -qw squid-openssl; then
    echo "Squid with SSL support is already installed."
else
    echo "Squid without SSL support detected."
    read -rp "Do you want to install squid with SSL support (squid-openssl)? (yes/no): " answer
    if [[ "$answer" =~ ^[Yy][Ee]?[Ss]$ ]]; then
        # If squid without SSL is detected, remove it and reinstall squid-openssl
        remove_and_install_squid_openssl
    else
        echo "Aborted by user."
        exit 0
    fi
fi


# Run SSL-Bump configuration
ssl_bump_setup
echo "Done. SSL-Bump configured"
echo "Certificate PEM path: /etc/squid/cert/squid_proxyCA.pem"
echo "Certificate CRT path: /usr/local/share/ca-certificates/squid_proxyCA.crt"
echo "Edit squid.conf and add:"
echo 'http_port 3128 ssl-bump cert=/etc/squid/cert/squid_proxyCA.pem generate-host-certificates=on options=NO_SSLv3,NO_TLSv1,NO_TLSv1_1,SINGLE_DH_USE,SINGLE_ECDH_USE'
echo "ssl_bump bump all"
