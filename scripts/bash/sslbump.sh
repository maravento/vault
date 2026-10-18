#!/bin/bash
# maravento.com
#
################################################################################
#
# Squid SSL-Bump Installer
#
# DESCRIPTION: Installs squid-openssl, replacing a plain squid if it is
# present, and generates the CA certificate that SSL-Bump needs.
#
# USAGE: sudo bash sslbump.sh
#
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

# Function: Report whether a package is installed, not merely residual
package_installed() {
    [ "$(dpkg-query -W -f='${db:Status-Status}' "$1" 2>/dev/null)" = installed ]
}

# dependencies
for dep in openssl ca-certificates systemd util-linux; do
    if ! package_installed "$dep"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') sslbump start..."

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

CA_CERT_D=/usr/local/share/ca-certificates

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Function: Remove regular squid and install squid-openssl
remove_and_install_squid_openssl() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') Backing up /etc/squid..."
    BACKUP_DIR=$(mktemp -d /tmp/squid.etc.bak.XXXXXX) || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create Squid backup directory -abort" >&2
        exit 1
    }
    if [ -d /etc/squid ] && ! cp -a /etc/squid/. "$BACKUP_DIR/"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot back up Squid configuration -abort" >&2
        exit 1
    fi

    echo "WARNING: this will purge Squid packages and remove configuration, cache and logs"
    echo "Configuration backup: $BACKUP_DIR"
    read -rp "Confirm Squid purge? (yes/no) [no]: " confirm_purge
    if [[ "$confirm_purge" != "yes" ]]; then
        echo "Purge cancelled"
        echo "$(date '+%Y-%m-%d %H:%M:%S') sslbump done at: $(date '+%Y-%m-%d %H:%M:%S')"
        exit 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Removing old squid..."
    apt purge -y 'squid*' &>/dev/null || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot purge Squid packages -abort" >&2
        exit 1
    }
    rm -rf /var/spool/squid* /var/log/squid* /etc/squid
    rm -f "$CA_CERT_D/squid_proxyCA.crt"

    echo "$(date '+%Y-%m-%d %H:%M:%S') Installing squid-openssl..."
    apt update || { echo "ERROR: apt update failed -abort" >&2; exit 1; }
    apt install -y squid-openssl squid-langpack squid-common squidclient squid-purge || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to install squid-openssl packages -abort" >&2
        exit 1
    }

    # Restore previous configuration
    if [ -d "$BACKUP_DIR" ]; then
        if ! { mkdir -p /etc/squid && cp -a "$BACKUP_DIR/." /etc/squid/; }; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot restore Squid configuration -abort" >&2
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: backup kept at: $BACKUP_DIR" >&2
            exit 1
        fi
    fi

    if ! { mkdir -p /var/log/squid &&
        touch /var/log/squid/{access,cache,store,deny}.log &&
        chown -R proxy:proxy /var/log/squid; }; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot prepare Squid logs -abort" >&2
        exit 1
    fi

    systemctl enable squid.service || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot enable squid.service -abort" >&2
        exit 1
    }
}

# Function: Configure SSL-Bump
ssl_bump_setup() {
    if [ ! -f /usr/lib/squid/security_file_certgen ] ||
        [ ! -x /usr/lib/squid/security_file_certgen ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: security_file_certgen is missing or not executable -abort" >&2
        exit 1
    fi

    CERT_D=/etc/squid/cert
    CERT=$CERT_D/squid_proxyCA.pem
    mkdir -p "$CERT_D"

    local tmp_cert=""
    echo "$(date '+%Y-%m-%d %H:%M:%S') Generating SSL certificate..."
    umask 077
    if ! { tmp_cert="$(mktemp "${CERT}.XXXXXX")" &&
        openssl req -new -newkey rsa:4096 -sha256 -days 365 -nodes -x509 \
            -keyout "$tmp_cert" -out "$tmp_cert" &&
        mv -fT -- "$tmp_cert" "$CERT"; }; then
        rm -f -- "$tmp_cert"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot generate Squid CA certificate -abort" >&2
        exit 1
    fi

    if ! chown -R proxy:proxy "$CERT_D"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set Squid cert owner and group -abort" >&2
        exit 1
    fi
    if ! chmod 0400 "$CERT"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set squid_proxyCA.pem permissions -abort" >&2
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Adding certificate to system..."
    CA_CERT_D=/usr/local/share/ca-certificates
    mkdir -p "$CA_CERT_D"
    local crt="$CA_CERT_D/squid_proxyCA.crt" tmp_dir
    tmp_dir="$(mktemp -d "${crt}.XXXXXX")" || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot prepare Squid CA export -abort" >&2
        exit 1
    }
    if { [ ! -e "$crt" ] ||
        cp --attributes-only -p -- "$crt" "$tmp_dir/cert"; } &&
        openssl x509 -inform PEM -in "$CERT" -out "$tmp_dir/cert" &&
        mv -fT -- "$tmp_dir/cert" "$crt"; then
        rmdir -- "$tmp_dir"
    else
        rm -f -- "$tmp_dir/cert"
        rmdir -- "$tmp_dir"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot export Squid CA certificate -abort" >&2
        exit 1
    fi
    update-ca-certificates || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update system CA certificates -abort" >&2
        exit 1
    }

    SSL_DB=/var/spool/squid/ssl_db
    echo "$(date '+%Y-%m-%d %H:%M:%S') Initializing SSL certificate database..."
    rm -rf "$SSL_DB"
    /usr/lib/squid/security_file_certgen -c -s "$SSL_DB" -M 4MB || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot initialize Squid SSL database -abort" >&2
        exit 1
    }
    if ! chown -R proxy:proxy "$SSL_DB"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set ssl_db owner and group -abort" >&2
        exit 1
    fi
    if ! chmod 700 "$SSL_DB"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot set ssl_db permissions -abort" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# Check if squid is installed
if ! package_installed squid && ! package_installed squid-openssl; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Squid is not installed. Installing squid-openssl..."
    # Only install squid-openssl if it's not installed
    apt update || { echo "ERROR: apt update failed -abort" >&2; exit 1; }
    apt install -y squid-openssl squid-langpack squid-common squidclient squid-purge || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to install squid-openssl packages -abort" >&2
        exit 1
    }
elif package_installed squid-openssl; then
    echo "Squid with SSL support is already installed"
else
    echo "Squid without SSL support detected"
    read -rp "Do you want to install squid with SSL support (squid-openssl)? (yes/no): " answer
    if [[ "$answer" =~ ^[Yy][Ee]?[Ss]$ ]]; then
        # If squid without SSL is detected, remove it and reinstall squid-openssl
        remove_and_install_squid_openssl
    else
        echo "Aborted by user"
        echo "$(date '+%Y-%m-%d %H:%M:%S') sslbump done at: $(date '+%Y-%m-%d %H:%M:%S')"
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

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') sslbump done at: $(date '+%Y-%m-%d %H:%M:%S')"
