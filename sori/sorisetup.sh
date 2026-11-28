#!/bin/bash
# maravento.com
#
################################################################################
#
# sorisetup -- SORI installer
# FILE: sorisetup.sh
#
# USAGE:
# COMMAND                             ACTION
# sudo bash sorisetup.sh              Show menu
# sudo bash sorisetup.sh --install    Install
# sudo bash sorisetup.sh --update     Update
# sudo bash sorisetup.sh --uninstall  Uninstall
#
# LOG: sorisetup.log (next to the script)
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

# logging
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="${script_dir}/sorisetup.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then echo "$msg" >&2; else echo "$msg"; fi
}
info() { log "INFO: $*"; }
warn() { log "WARNING: $*"; }
err()  { log "ERROR: $*"; }
abort() { err "$*"; exit 1; }

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -abort"
    exit 1
fi

# dependencies
for dep_cmd in apt-get dpkg dpkg-query systemctl openssl ss; do
    if ! command -v "$dep_cmd" >/dev/null 2>&1; then
        log "ERROR: dependency '$dep_cmd' is not installed -abort"
        exit 1
    fi
done

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
            log "INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no interface with IPv4 -abort"
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
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

source_web="${script_dir}/web"
source_db="${script_dir}/db"
source_tools="${script_dir}/tools"
install_dir="/var/www/sori"
conf_dir="/etc/sori"
env_file="${conf_dir}/sori.env"
vhost_file="/etc/apache2/sites-available/sori.conf"
frontend_port="10600"
database_name="sori"
database_user="sori"
database_socket="/run/mysqld/mysqld.sock"
backup_dir="/etc/bak/sori"
# Settings written to sori.env with these defaults
env_settings=(SESSION_TIMEOUT=7200 LOGIN_MAX_ATTEMPTS=5 LOGIN_WINDOW_MINUTES=10
              LOGIN_ATTEMPTS_KEEP_DAYS=1 DETAIL_ROWS_LIMIT=500)
# Packages the project needs: web server, PHP, database, Access reader, backup tools
project_pkgs=(apache2 libapache2-mod-php php-cli php-mysql mariadb-server mariadb-client
              mdbtools curl zip cron)

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

# Ask a question where Enter means no
ask_no() {
    local no_answer
    read -r -p "$1 [y/N]: " no_answer
    case "${no_answer:-n}" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

# The project is installed when any of its own paths exists
is_installed() {
    [ -d "$install_dir" ] || [ -f "$env_file" ] || [ -f "$vhost_file" ]
}

# Check that every file the code copy needs exists in the repository
check_sources() {
    local source_item
    for source_item in "${source_web}/public/index.php" \
                       "${source_web}/public/assets/sori.css" "${source_web}/public/assets/sori.js" \
                       "${source_web}/public/assets/document.js" "${source_web}/public/assets/third_party.js" \
                       "${source_web}/app/product.php" "${source_web}/app/third_party.php" "${source_web}/app/supplier_payment.php" \
                       "${source_web}/app/views/product_form.php" "${source_web}/app/views/third_party_form.php" \
                       "${source_web}/app/views/supplier_payment_new.php" \
                       "${source_web}/app/lib.php" "${source_web}/app/i18n.php" \
                       "${source_web}/app/lang_en.php" "${source_web}/app/modules.php" \
                       "${source_web}/app/screens.php" "${source_web}/app/write.php" "${source_web}/app/invoice.php" "${source_web}/app/receipt.php" \
                       "${source_web}/app/sales_return.php" "${source_web}/app/purchase.php" "${source_web}/app/purchase_return.php" \
                       "${source_web}/app/views/receipt_new.php" "${source_web}/app/views/sales_return_new.php" \
                       "${source_web}/app/views/purchase_new.php" "${source_web}/app/views/purchase_return_new.php" \
                       "${source_web}/app/views/admin.php" "${source_web}/app/views/detail.php" \
                       "${source_web}/app/views/document_new.php" \
                       "${source_web}/app/views/home.php" "${source_web}/app/views/layout.php" \
                       "${source_web}/app/views/list.php" "${source_web}/app/views/login.php" \
                       "${source_web}/app/views/pending.php" \
                       "${source_db}/schema.sql" "${source_db}/app.sql" \
                       "${source_tools}/sorimigrate.php" "${source_tools}/soribk.sh" \
                       "${source_tools}/sorienv.sh"; do
        [ -f "$source_item" ] || abort "source is not a file: $(basename "$source_item") -abort"
    done
}

# Copy the code. The .env and the databases are never touched here.
copy_code() {
    install -d -m 755 "$install_dir" || abort "cannot create $install_dir -abort"
    rm -rf "${install_dir}/public" "${install_dir}/app" "${install_dir}/db" "${install_dir}/tools"
    cp -a "${source_web}/public" "${source_web}/app" "$source_db" "$source_tools" "${install_dir}/" \
        || abort "cannot copy the code to $install_dir -abort"
    chown -R root:root "$install_dir"
    chmod -R go-w "$install_dir"
    chmod 750 "${install_dir}/tools/soribk.sh" || abort "cannot set backup script permissions -abort"
    info "updated ${install_dir}"
}

# Run SQL as the database administrator through the local socket
sql_admin() {
    mariadb "$@"
}

# Time zone of the server: dates follow the place where the company works
detect_timezone() {
    local zone
    zone=$(timedatectl show -p Timezone --value 2>/dev/null) || zone=""
    [[ "$zone" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]] || abort "cannot detect the server time zone -abort"
    echo "$zone"
}

write_env() {
    local database_password="$1" server_timezone
    server_timezone=$(detect_timezone) || exit 1
    install -d -m 750 -o root -g www-data "$conf_dir" || abort "cannot create $conf_dir -abort"
    cat > "$env_file" <<EOF
# =============================================================================
# Database
DB_SOCKET=${database_socket}
DB_NAME=${database_name}
DB_USER=${database_user}
DB_PASS=${database_password}
# =============================================================================
# Settings
TIMEZONE=${server_timezone}
$(printf '%s\n' "${env_settings[@]}")
# Backup
BACKUP_DIR=${backup_dir}
# =============================================================================
EOF
    chown root:www-data "$env_file"
    chmod 640 "$env_file"
    info "sori.env written"
}

write_vhost() {
    cat > "$vhost_file" <<EOF
# SORI frontend. It listens only on the local machine; publish it with a tunnel.
Listen 127.0.0.1:${frontend_port}
<VirtualHost 127.0.0.1:${frontend_port}>
    ServerName localhost
    DocumentRoot ${install_dir}/public
    <Directory ${install_dir}/public>
        Options -Indexes -MultiViews
        AllowOverride None
        Require all granted
        FallbackResource /index.php
    </Directory>
    <IfModule mod_php.c>
        php_admin_flag display_errors off
        php_admin_flag expose_php off
    </IfModule>
    ErrorLog \${APACHE_LOG_DIR}/sori-error.log
    CustomLog \${APACHE_LOG_DIR}/sori-access.log combined
</VirtualHost>
EOF
    info "sori.conf written"
}

reload_apache() {
    apache2ctl configtest >/dev/null 2>&1 || abort "apache2 configuration test failed -abort"
    systemctl reload apache2 || abort "cannot reload apache2 -abort"
}

# Install the packages the project needs that are still missing
install_packages() {
    local missing_pkgs=() pkg_name network_command
    for pkg_name in "${project_pkgs[@]}"; do
        [ "$(dpkg-query -W -f='${db:Status-Status}' "$pkg_name" 2>/dev/null)" = "installed" ] || missing_pkgs+=("$pkg_name")
    done
    if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        for network_command in ip awk getent; do
            if ! command -v "$network_command" >/dev/null 2>&1; then
                abort "network command '$network_command' missing -abort"
            fi
        done
        check_ipv4_interfaces
        check_internet
        retry_cmd "update package index" apt-get update -qq \
            || abort "cannot update the package index -abort"
        retry_cmd "install packages" env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y -qq "${missing_pkgs[@]}" \
            || abort "package installation failed -abort"
        info "installed packages: ${missing_pkgs[*]}"
    fi
}

do_install() {
    # Already installed? Check before anything else
    if is_installed; then
        abort "SORI is already installed; use --update or --uninstall -abort"
    fi
    check_sources
    if ss -ltnH "sport = :${frontend_port}" | grep -q .; then
        abort "port ${frontend_port} is already in use -abort"
    fi

    # Packages
    install_packages

    # Database
    systemctl is-active --quiet mariadb || systemctl enable --now mariadb \
        || abort "cannot start mariadb -abort"
    local database_password admin_password admin_hash
    database_password="$(openssl rand -hex 16)"
    admin_password="$(openssl rand -hex 8)"
    sql_admin <<EOF || abort "cannot create the database user -abort"
CREATE DATABASE IF NOT EXISTS \`${database_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE OR REPLACE USER '${database_user}'@'localhost' IDENTIFIED BY '${database_password}';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${database_name}\`.* TO '${database_user}'@'localhost';
GRANT SELECT, INSERT, UPDATE, DELETE ON \`${database_name}\\_%\`.* TO '${database_user}'@'localhost';
FLUSH PRIVILEGES;
EOF
    sql_admin "$database_name" < "${source_db}/app.sql" \
        || abort "cannot create the control tables -abort"
    admin_hash="$(php -r 'echo password_hash(trim(fgets(STDIN)), PASSWORD_DEFAULT);' <<< "$admin_password")"
    [ -n "$admin_hash" ] || abort "cannot hash the administrator password -abort"
    sql_admin "$database_name" <<EOF || abort "cannot create the administrator -abort"
INSERT INTO sori_users (client_id, username, name, hash, role)
VALUES (NULL, 'admin', 'Administrator', '${admin_hash}', 'admin');
EOF
    info "database ${database_name} created"

    # Files and configuration
    copy_code
    write_env "$database_password"
    bash "${install_dir}/tools/soribk.sh" --install \
        || abort "cannot register the backup cron -abort"

    # Apache
    write_vhost
    a2ensite sori >/dev/null || abort "cannot enable the site -abort"
    reload_apache
    if ! curl -fsS -o /dev/null --retry 5 --retry-connrefused --retry-delay 1 \
            "http://127.0.0.1:${frontend_port}/login"; then
        abort "frontend does not answer on port ${frontend_port} -abort"
    fi
    info "sori installed"
    echo "admin password: ${admin_password}"
}

do_update() {
    is_installed || abort "SORI is not installed; use --install -abort"
    check_sources
    [ -w "$install_dir" ] || abort "dst is not writable: $install_dir -abort"
    [ -f "$env_file" ] || abort "dst is not a file: $(basename "$env_file") -abort"

    install_packages
    bash "${source_tools}/soribk.sh" || abort "backup failed -abort"
    copy_code
    bash "${install_dir}/tools/soribk.sh" --install \
        || abort "cannot register the backup cron -abort"
    sql_admin "$database_name" < "${source_db}/app.sql" \
        || abort "cannot update the control tables -abort"
    reload_apache
    info "sori updated"
}

do_uninstall() {
    is_installed || abort "SORI is not installed -abort"

    if ! ask_no "Remove SORI?"; then
        info "uninstall cancelled"
        return 0
    fi

    bash "${install_dir}/tools/soribk.sh" --uninstall || warn "cannot remove the backup cron -alert"
    a2dissite sori >/dev/null 2>&1 || true
    rm -f "$vhost_file"
    if apache2ctl configtest >/dev/null 2>&1; then
        systemctl reload apache2 || warn "cannot reload apache2 -alert"
    fi
    rm -rf "$install_dir" "$conf_dir"

    # Client data is deleted only on a separate, explicit confirmation
    local database_list
    database_list="$(sql_admin -N -e "SHOW DATABASES LIKE '${database_name}\\_%'" 2>/dev/null; \
                     sql_admin -N -e "SHOW DATABASES LIKE '${database_name}'" 2>/dev/null)"
    if [ -n "$database_list" ]; then
        if ask_no "Delete the databases ($(echo "$database_list" | paste -sd' ')) and the user ${database_user}?"; then
            local database_item
            while IFS= read -r database_item; do
                sql_admin -e "DROP DATABASE \`${database_item}\`" \
                    || abort "cannot delete database ${database_item} -abort"
            done <<< "$database_list"
            sql_admin -e "DROP USER IF EXISTS '${database_user}'@'localhost'" || true
            info "databases removed"
        else
            info "databases kept"
        fi
    fi
    info "sori uninstalled"
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# Interactive menu shown when the script runs without arguments
show_menu() {
    while true; do
        echo ""
        echo "==== SORI Installation Menu ===="
        echo "1) Install"
        echo "2) Update"
        echo "3) Uninstall"
        echo "4) Exit"
        read -r -p "Select option [4]: " menu_option
        echo ""
        menu_option="${menu_option:-4}"
        case "$menu_option" in
            1) do_install || exit 1; break ;;
            2) do_update || exit 1; break ;;
            3) do_uninstall || exit 1; break ;;
            4) break ;;
            *) info "invalid option -retry" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

info "sorisetup start..."

# Run the action given on the command line, or fall back to the menu
case "${1:-}" in
    --install) do_install || exit 1 ;;
    --update) do_update || exit 1 ;;
    --uninstall) do_uninstall || exit 1 ;;
    "") show_menu ;;
    *)
        err "invalid option -abort"
        echo "Usage: $(basename "$0") [--install|--update|--uninstall]"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

info "sorisetup done"
