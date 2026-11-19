#!/bin/bash
# maravento.com
#
################################################################################
#
# Squid SSL-Bump Installer
# FILE: sslbump.sh
#
# DESCRIPTION: Installs squid-openssl, replacing a plain squid if it is
# present, and generates the CA certificate that SSL-Bump needs.
#
# USAGE:
# COMMAND               ACTION
# sudo bash sslbump.sh  Run (no arguments)
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: sslbump start..."

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

CA_CERT_D=/usr/local/share/ca-certificates

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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

# dependencies
net_checked=0
for dep in openssl ca-certificates systemd util-linux iproute2 libc-bin coreutils; do
    if ! package_installed "$dep"; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
            fi
            check_ipv4_interfaces
            check_internet
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

# Function: Remove regular squid and install squid-openssl
remove_and_install_squid_openssl() {
    check_ipv4_interfaces
    check_internet
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Backing up /etc/squid..."
    BACKUP_DIR=$(mktemp -d /tmp/squid.etc.bak.XXXXXX) || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create Squid backup directory -abort" >&2
        exit 1
    }
    if [ -d /etc/squid ] && ! cp -a /etc/squid/. "$BACKUP_DIR/"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot back up Squid configuration -abort" >&2
        exit 1
    fi

    echo "This will purge Squid packages and remove configuration, cache and logs"
    echo "Configuration backup: $BACKUP_DIR"
    read -rp "Confirm Squid purge? (yes/no) [no]: " confirm_purge
    if [[ "$confirm_purge" != "yes" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Squid purge cancelled -skip"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: sslbump done"
        exit 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Removing old squid..."
    apt purge -y 'squid*' &>/dev/null || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot purge Squid packages -abort" >&2
        exit 1
    }
    rm -rf /var/spool/squid* /var/log/squid* /etc/squid
    rm -f "$CA_CERT_D/squid_proxyCA.crt"

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing squid-openssl..."
    retry_cmd "update package lists" apt update || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: apt update failed -abort" >&2; exit 1; }
    retry_cmd "install packages" apt install -y squid-openssl squid-langpack squid-common squidclient squid-purge || {
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: security_file_certgen not executable -abort" >&2
        exit 1
    fi

    CERT_D=/etc/squid/cert
    CERT=$CERT_D/squid_proxyCA.pem
    mkdir -p "$CERT_D"
    if [ -f "$CERT" ]; then
        read -rp "Squid CA already exists; clients that trust it must import the new one. Regenerate it? [y/N]: " regen_ca
        if ! [[ "$regen_ca" =~ ^[Yy]$ ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: keeping the current Squid CA and ssl_db -skip"
            return 0
        fi
    fi

    local tmp_cert=""
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Generating SSL certificate..."
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

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Adding certificate to system..."
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Initializing SSL certificate database..."
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Squid is not installed. Installing squid-openssl..."
    check_ipv4_interfaces
    check_internet
    # Only install squid-openssl if it's not installed
    retry_cmd "update package lists" apt update || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: apt update failed -abort" >&2; exit 1; }
    retry_cmd "install packages" apt install -y squid-openssl squid-langpack squid-common squidclient squid-purge || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Failed to install squid-openssl packages -abort" >&2
        exit 1
    }
elif package_installed squid-openssl; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: squid-openssl already installed -skip"
else
    echo "Squid without SSL support detected"
    read -rp "Do you want to install squid with SSL support (squid-openssl)? (yes/no): " answer
    if [[ "$answer" =~ ^[Yy][Ee]?[Ss]$ ]]; then
        # If squid without SSL is detected, remove it and reinstall squid-openssl
        remove_and_install_squid_openssl
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: aborted by user"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: sslbump done"
        exit 0
    fi
fi

# Run SSL-Bump configuration
ssl_bump_setup
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: SSL-Bump configured"
echo "Certificate PEM path: /etc/squid/cert/squid_proxyCA.pem"
echo "Certificate CRT path: /usr/local/share/ca-certificates/squid_proxyCA.crt"
echo "Edit squid.conf and add:"
echo 'http_port 3128 ssl-bump cert=/etc/squid/cert/squid_proxyCA.pem generate-host-certificates=on options=NO_SSLv3,NO_TLSv1,NO_TLSv1_1,SINGLE_DH_USE,SINGLE_ECDH_USE'
echo "ssl_bump bump all"

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: sslbump done"
