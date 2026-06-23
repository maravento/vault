#!/bin/bash
# maravento.com
#
################################################################################
#
# smbstack - Samba with Shared Folder, Recycle Bin and Audit
# https://github.com/maravento/vault/smbstack
#
################################################################################

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

### PATHS
SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
CONF_DIR="$SCRIPT_DIR/conf"
WEB_DIR="$SCRIPT_DIR/web"
TOOLS_DIR="$SCRIPT_DIR/tools"
SMBSTACK_WWW="/var/www/smbstack"
SMBSTACK_WEB="$SMBSTACK_WWW/web"
SMBSTACK_TOOLS="$SMBSTACK_WWW/tools"
SMBSTACK_ENV="$SMBSTACK_WWW/smbstack.env"

### REPOSITORY STRUCTURE CHECK
check_repo() {
    local missing=0
    for dir in "$CONF_DIR" "$WEB_DIR" "$TOOLS_DIR"; do
        if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
            missing=1
            break
        fi
    done
    if [ "$missing" -eq 1 ]; then
        echo ""
        echo "ERROR: Repository files not found. Run:"
        echo ""
        echo "  wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py"
        echo "  chmod +x gitfolder.py"
        echo "  python3 gitfolder.py https://github.com/maravento/vault/smbstack"
        echo ""
        exit 1
    fi
}
check_repo

### LOCAL USER (multi-strategy detection with validation)
detect_user() {
    local_user=""
    local_user=$(who | awk '/\(:0\)/{print $1; exit}')
    [ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
    [ -z "$local_user" ] && local_user="${SUDO_USER:-}"
    [ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
    [ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
    if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
        echo "ERROR: Cannot determine a valid local user"
        exit 1
    fi
    echo "Using local user: $local_user"
}

### SHARED FOLDER SETUP
select_shared_folder() {
    echo ""
    echo "Shared folder setup"
    echo "-------------------"
    while true; do
        read -p "Enter shared folder name (eng: shared / esp: compartida): " SHARED_NAME
        if [ -z "$SHARED_NAME" ]; then
            echo "ERROR: Folder name cannot be empty"
        elif [[ "$SHARED_NAME" =~ [^a-zA-Z0-9_-] ]]; then
            echo "ERROR: Folder name can only contain letters, numbers, hyphens and underscores"
            SHARED_NAME=""
        else
            break
        fi
    done
    SHARED_PATH="/home/$local_user/$SHARED_NAME"

    if [ -d "$SHARED_PATH" ]; then
        echo "Folder '$SHARED_PATH' already exists. Verifying permissions..."
        perms_ok=1

        actual_owner=$(stat -c "%U" "$SHARED_PATH")
        actual_group=$(stat -c "%G" "$SHARED_PATH")
        actual_mode=$(stat -c "%a" "$SHARED_PATH")

        if [ "$actual_owner" != "$local_user" ] || [ "$actual_group" != "sambashare" ]; then
            echo "  Owner/group mismatch (got $actual_owner:$actual_group, expected $local_user:sambashare). Fixing..."
            chown "$local_user":sambashare "$SHARED_PATH"
            perms_ok=0
        fi

        if [ "$actual_mode" != "755" ]; then
            echo "  Mode mismatch (got $actual_mode, expected 755). Fixing..."
            chmod 755 "$SHARED_PATH"
            perms_ok=0
        fi

        while IFS= read -r dir; do
            dir_owner=$(stat -c "%U" "$dir")
            dir_group=$(stat -c "%G" "$dir")
            dir_mode=$(stat -c "%a" "$dir")
            if [ "$dir_owner" != "$local_user" ] || [ "$dir_group" != "sambashare" ]; then
                echo "  Fixing owner/group on: $dir"
                chown "$local_user":sambashare "$dir"
                perms_ok=0
            fi
            if [ "$dir_mode" != "2775" ]; then
                echo "  Fixing mode on: $dir"
                chmod 2775 "$dir"
                perms_ok=0
            fi
        done < <(find "$SHARED_PATH" -mindepth 1 -type d)

        while IFS= read -r file; do
            file_owner=$(stat -c "%U" "$file")
            file_group=$(stat -c "%G" "$file")
            file_mode=$(stat -c "%a" "$file")
            if [ "$file_owner" != "$local_user" ] || [ "$file_group" != "sambashare" ]; then
                echo "  Fixing owner/group on: $file"
                chown "$local_user":sambashare "$file"
                perms_ok=0
            fi
            if [ "$file_mode" != "664" ]; then
                echo "  Fixing mode on: $file"
                chmod 664 "$file"
                perms_ok=0
            fi
        done < <(find "$SHARED_PATH" -mindepth 1 -type f)

        if ! getfacl "$SHARED_PATH" 2>/dev/null | grep -q "user:www-data:r-x"; then
            echo "  Missing ACL for www-data. Fixing..."
            setfacl -m u:www-data:r-x "$SHARED_PATH"
            perms_ok=0
        fi
        # root ACL: mask r-x (blocks group write on root), default mask rwx (allows group write in subdirs)
        setfacl -m mask::r-x "$SHARED_PATH"
        setfacl -d -m u:www-data:r-x "$SHARED_PATH"
        setfacl -d -m g:sambashare:rwx "$SHARED_PATH"
        setfacl -d -m mask::rwx "$SHARED_PATH"
        # recycle bin
        mkdir -p "$SHARED_PATH/.recycle"
        chown www-data:www-data "$SHARED_PATH/.recycle"
        chmod 755 "$SHARED_PATH/.recycle"
        setfacl -m g:sambashare:rwx "$SHARED_PATH/.recycle"
        setfacl -d -m g:sambashare:rwx "$SHARED_PATH/.recycle"

        if [ "$perms_ok" -eq 1 ]; then
            echo "  Permissions OK"
        else
            echo "  Permissions corrected"
        fi
    else
        sudo -u "$local_user" mkdir -p "$SHARED_PATH"
        chmod 755 "$SHARED_PATH"
        chown "$local_user":sambashare "$SHARED_PATH"
        sudo -u "$local_user" mkdir -p "$SHARED_PATH/DEMO"
        sudo -u "$local_user" bash -c "echo 'this is a demo file' > '$SHARED_PATH/DEMO/demo.txt'"
        find "$SHARED_PATH" -mindepth 1 -type d -exec chown "$local_user":sambashare {} \; -exec chmod 2775 {} \;
        find "$SHARED_PATH" -mindepth 1 -type f -exec chown "$local_user":sambashare {} \; -exec chmod 664 {} \;
        setfacl -m u:www-data:r-x "$SHARED_PATH"
        setfacl -m mask::r-x "$SHARED_PATH"
        setfacl -d -m u:www-data:r-x "$SHARED_PATH"
        setfacl -d -m g:sambashare:rwx "$SHARED_PATH"
        setfacl -d -m mask::rwx "$SHARED_PATH"
        # recycle bin
        mkdir -p "$SHARED_PATH/.recycle"
        chown www-data:www-data "$SHARED_PATH/.recycle"
        chmod 755 "$SHARED_PATH/.recycle"
        setfacl -m g:sambashare:rwx "$SHARED_PATH/.recycle"
        setfacl -d -m g:sambashare:rwx "$SHARED_PATH/.recycle"
    fi

    echo "Shared folder: $SHARED_PATH"
    echo ""
}

### INSTALL
### CHECK ALREADY INSTALLED
check_already_installed() {
    local installed=0
    local reasons=""

    if pdbedit -L 2>/dev/null | grep -q ":"; then
        installed=1
        reasons+="  - Samba users already registered (pdbedit)\n"
    fi

    if [ -f "$SMBSTACK_ENV" ]; then
        installed=1
        reasons+="  - smbstack.env already exists: $SMBSTACK_ENV\n"
    fi

    if [ -f "/etc/samba/smb.conf" ]; then
        _existing_share=""
        [ -f "$SMBSTACK_ENV" ] && _existing_share=$(grep "^SHARED_NAME=" "$SMBSTACK_ENV" | cut -d= -f2 | tr -d '"')
        if [ -n "$_existing_share" ] && grep -q "\[${_existing_share}\]" /etc/samba/smb.conf 2>/dev/null; then
            installed=1
            reasons+="  - smb.conf already configured: /etc/samba/smb.conf\n"
        fi
    fi

    if [ "$installed" -eq 1 ]; then
        echo ""
        echo "ERROR: Samba is already installed. Aborting."
        echo ""
        printf "%b" "$reasons"
        echo ""
        echo "To update, run: sudo bash smbinstall.sh --update"
        echo ""
        exit 1
    fi
}

do_install() {
    check_already_installed
    detect_user

    # dependency check
    if systemctl is-active --quiet nginx; then
        echo "ERROR: nginx is running. Disable it first: systemctl stop nginx"
        exit 1
    fi

    for cmd in apache2 a2ensite a2dissite a2enmod htpasswd php; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "ERROR: $cmd not found. Run first:"
            echo "  apt-get install -y apache2 apache2-utils libapache2-mod-php"
            echo "  apt-get install -y --reinstall apache2-doc"
            exit 1
        fi
    done

    if ! systemctl is-active --quiet apache2; then
        echo "ERROR: apache2 is not running. Start it first: systemctl start apache2"
        exit 1
    fi

    if ! command -v rsyslogd &>/dev/null; then
        echo "ERROR: rsyslog not found. Install it first: apt-get install -y rsyslog"
        exit 1
    fi

    if ! systemctl is-active --quiet rsyslog; then
        echo "ERROR: rsyslog is not running. Start it first: systemctl start rsyslog"
        exit 1
    fi

    if ! command -v logrotate &>/dev/null; then
        echo "ERROR: logrotate not found. Install it first: apt-get install -y logrotate"
        exit 1
    fi

    # enable required apache modules
    a2enmod -q headers mime rewrite

    # samba packages
    DEBIAN_FRONTEND=noninteractive apt-get install -y samba samba-common samba-common-bin smbclient winbind cifs-utils

    systemctl enable smbd.service
    systemctl enable winbind.service

    groupadd -f sambashare
    usermod -aG sambashare "$local_user"

    # smbguest: dedicated unprivileged samba guest user
    if ! id smbguest &>/dev/null; then
        useradd -r -s /bin/false smbguest
        echo "smbguest created"
    fi
    usermod -aG sambashare smbguest
    # create samba password for smbguest (random, not used interactively)
    SMB_GUEST_PASS=$(openssl rand -base64 16)
    printf "%s\n%s\n" "$SMB_GUEST_PASS" "$SMB_GUEST_PASS" | smbpasswd -a -s smbguest
    unset SMB_GUEST_PASS
    usermod -a -G sambashare www-data

    select_shared_folder

    mkdir -p /var/lib/samba/usershares
    chmod 1775 /var/lib/samba/usershares/
    mkdir -p /var/log/samba

    cp -f /lib/systemd/system/smbd.service{,.bak} &>/dev/null
    sed -i 's/ \$SMBDOPTIONS//' /lib/systemd/system/smbd.service

    # samba web viewer and tools
    touch /var/log/samba/log.samba /var/log/samba/log.audit
    chown root:adm /var/log/samba/log.samba /var/log/samba/log.audit
    chmod 660 /var/log/samba/log.samba /var/log/samba/log.audit

    # smbwatch log
    touch /var/log/smbwatch.log
    chown root:root /var/log/smbwatch.log
    chmod 640 /var/log/smbwatch.log

    mkdir -p "$SMBSTACK_WEB"
    cp -f "$WEB_DIR/smbaudit.html" "$SMBSTACK_WEB/"
    cp -f "$WEB_DIR/smbapi.php" "$SMBSTACK_WEB/"
    cp -f "$WEB_DIR/smbaudit-diagnostic.php" "$SMBSTACK_WEB/"
    cp -f "$WEB_DIR/shared.php" "$SMBSTACK_WEB/"
    chmod -R 755 "$SMBSTACK_WEB"
    chown -R www-data:www-data "$SMBSTACK_WEB"

    # apache vhosts (both in smbweb.conf)
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    grep -qxF "Listen 0.0.0.0:3092" /etc/apache2/ports.conf || echo "Listen 0.0.0.0:3092" | tee -a /etc/apache2/ports.conf
    cp -f "$WEB_DIR/smbweb.conf" /etc/apache2/sites-available/smbweb.conf
    a2ensite -q smbweb.conf

    # replace placeholders in deployed files (not in repo)
    for f in \
        /etc/apache2/sites-available/smbweb.conf \
        /etc/rsyslog.d/fullaudit.conf \
        "$SMBSTACK_WEB/smbaudit.html" \
        "$SMBSTACK_WEB/smbapi.php" \
        "$SMBSTACK_WEB/smbaudit-diagnostic.php" \
        "$SMBSTACK_WEB/shared.php"; do
        [ -f "$f" ] || continue
        escaped_user=$(printf '%s' "$local_user" | sed 's/[&/\\|]/\\&/g')
        sed -i "s|your_user|$escaped_user|g" "$f"
        sed -i "s|compartida|$SHARED_NAME|g" "$f"
    done

    # logrotate
    cp -f /etc/logrotate.d/samba{,.bak} &>/dev/null
    cat > /etc/logrotate.d/samba <<'EOF'
/var/log/samba/log.audit {
    weekly
    missingok
    rotate 7
    create 0660 root adm
    postrotate
        systemctl restart rsyslog > /dev/null 2>&1 || true
    endscript
    compress
    notifempty
}
/var/log/samba/log.samba {
    weekly
    missingok
    rotate 7
    postrotate
        systemctl reload smbd > /dev/null || true
    endscript
    compress
    notifempty
}
EOF

    # smbwatch logrotate
    cp -f /etc/logrotate.d/smbwatch{,.bak} &>/dev/null
    cat > /etc/logrotate.d/smbwatch <<'EOF'
/var/log/smbwatch.log {
    weekly
    missingok
    rotate 7
    create 0640 root root
    compress
    notifempty
}
EOF

    # smb.conf
    prompt_smb_net_iface() {
        while true; do
            read -p "Enter Samba server IP/network (e.g. 192.168.1.0/24): " SMB_NET
            if [ -z "$SMB_NET" ]; then
                echo "ERROR: Network cannot be empty"
            elif ! [[ "$SMB_NET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
                echo "ERROR: Invalid format. Expected x.x.x.x/xx (e.g. 192.168.1.0/24)"
                SMB_NET=""
            else
                break
            fi
        done
        echo "Available interfaces:"
        ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | sed 's/^/  /'
        while true; do
            read -p "Enter network interface: " SMB_IFACE
            if [ -z "$SMB_IFACE" ]; then
                echo "ERROR: Interface cannot be empty"
            elif ! ip link show "$SMB_IFACE" &>/dev/null; then
                echo "ERROR: Interface $SMB_IFACE not found"
                SMB_IFACE=""
            else
                break
            fi
        done
    }

    apply_smb_conf_placeholders() {
        local escaped_user
        escaped_user=$(printf '%s' "$local_user" | sed 's/[&/\\|]/\\&/g')
        sed -i "s|your_user|$escaped_user|g" /etc/samba/smb.conf
        sed -i "s|compartida|$SHARED_NAME|g" /etc/samba/smb.conf
    }

    apply_smb_conf_interfaces() {
        sed -i "s|interfaces = .*|interfaces = 127.0.0.0/8 $SMB_NET $SMB_IFACE|" /etc/samba/smb.conf
        sed -i "s|hosts allow = .*|hosts allow = 127.0.0.1, $SMB_NET|" /etc/samba/smb.conf
        echo "interfaces set to: 127.0.0.0/8 $SMB_NET $SMB_IFACE"
        echo "hosts allow set to: 127.0.0.1, $SMB_NET"
    }

    if [ -f /etc/samba/smb.conf ]; then
        while true; do
            read -p "smb.conf already exists. Overwrite? (y/n): " ow
            case "$ow" in
                [Yy])
                    cp -f /etc/samba/smb.conf{,.bak}
                    echo "Backup saved: /etc/samba/smb.conf.bak"
                    cp -f "$CONF_DIR/smb.conf" /etc/samba/smb.conf
                    apply_smb_conf_placeholders
                    prompt_smb_net_iface
                    apply_smb_conf_interfaces
                    break
                    ;;
                [Nn])
                    echo "Skipping smb.conf"
                    prompt_smb_net_iface
                    break
                    ;;
                *)
                    echo "ERROR: Answer y or n"
                    ;;
            esac
        done
    else
        cp -f "$CONF_DIR/smb.conf" /etc/samba/smb.conf
        apply_smb_conf_placeholders
        prompt_smb_net_iface
        apply_smb_conf_interfaces
    fi

    # rsyslog
    cp -f /etc/rsyslog.conf{,.bak} &>/dev/null
    sed -i -E 's/^(\s*(\$FileOwner|\$FileGroup|\$FileCreateMode|\$DirCreateMode|\$Umask|\$PrivDropToUser|\$PrivDropToGroup)\b.*)/#\1/' /etc/rsyslog.conf
    cp -f "$CONF_DIR/fullaudit.conf" /etc/rsyslog.d/fullaudit.conf
    chmod 644 /etc/rsyslog.d/fullaudit.conf
    chown root:root /etc/rsyslog.d/fullaudit.conf
    usermod -a -G adm www-data

    cp -f /etc/logrotate.d/rsyslog{,.bak} &>/dev/null
    grep -qF 'create 0644 syslog adm' /etc/logrotate.d/rsyslog || \
        sed -i '/sharedscripts/a \    create 0644 syslog adm' /etc/logrotate.d/rsyslog
    grep -qF 'su syslog adm' /etc/logrotate.d/rsyslog || \
        sed -i '/^{$/a \	su syslog adm' /etc/logrotate.d/rsyslog

    logrotate_out=$(logrotate -f /etc/logrotate.d/samba 2>&1)
    if echo "$logrotate_out" | grep -qi "error"; then
        echo "WARNING: logrotate error"
        echo "$logrotate_out"
    fi

    # cron: recycle bin weekly cleanup
    crontab -l 2>/dev/null > "/var/www/smbstack/crontab-$(date +%Y%m%d%H%M%S).bak" || true
    if ! crontab -l 2>/dev/null | grep -qF ".recycle"; then
        (crontab -l 2>/dev/null; echo "@weekly find \"$SHARED_PATH/.recycle/\" -depth -mindepth 1 -mtime +7 -delete >/dev/null 2>&1") | crontab -
    fi

    # service watchdog
    mkdir -p "$SMBSTACK_TOOLS"
    cp -f "$TOOLS_DIR"/*.sh "$SMBSTACK_TOOLS/"
    chmod +x "$SMBSTACK_TOOLS"/*.sh
    # cron: service watchdog at reboot
    if ! crontab -l 2>/dev/null | grep -qF "smbload.sh"; then
        (crontab -l 2>/dev/null; echo "@reboot $SMBSTACK_TOOLS/smbload.sh") | crontab -
    fi

    # netbios support (disabled by default)
    while true; do
        read -p "Enable NetBIOS support? (not recommended) (y/n): " netbios_ans
        case "$netbios_ans" in
            [Yy]|[Nn]) break ;;
            *) echo "ERROR: Answer y or n" ;;
        esac
    done
    case "$netbios_ans" in
        [Yy]*)
            cp -f /etc/samba/smb.conf{,.bak} &>/dev/null
            sed -i 's/^\s*disable netbios\s*=.*/   disable netbios = no/' /etc/samba/smb.conf
            sed -i "s/^;\s*netbios name\s*=.*/   netbios name = $local_user/" /etc/samba/smb.conf
            cat >> /etc/logrotate.d/samba <<'NMBD'
/var/log/samba/log.nmbd {
    weekly
    missingok
    rotate 7
    postrotate
        systemctl reload nmbd 2>/dev/null || true
    endscript
    compress
    notifempty
}
NMBD
            cp -f "$SMBSTACK_TOOLS/smbload.sh" "$SMBSTACK_TOOLS/smbload.sh.tmp"
            cat >> "$SMBSTACK_TOOLS/smbload.sh.tmp" <<'NMBD'

# Samba Service (nmbd)
if pgrep -x nmbd > /dev/null; then
    echo "nmbd: ONLINE"
else
    systemctl stop nmbd.service &>/dev/null
    if systemctl start nmbd.service; then
        echo "nmbd start: $(date)" | tee -a /var/log/syslog
    else
        echo "nmbd start FAILED: $(date)" | tee -a /var/log/syslog
    fi
fi
NMBD
            mv -f "$SMBSTACK_TOOLS/smbload.sh.tmp" "$SMBSTACK_TOOLS/smbload.sh"
            chmod +x "$SMBSTACK_TOOLS/smbload.sh"
            systemctl enable --now nmbd.service
            echo "NetBIOS enabled"
            echo ""
            echo "NOTE: NetBIOS requires the following iptables rules on interface $SMB_IFACE:"
            echo "  iptables -A INPUT   -i $SMB_IFACE -p udp -m multiport --dports 137,138 -j ACCEPT"
            echo "  iptables -A FORWARD -i $SMB_IFACE -p udp -m multiport --dports 137,138 -j ACCEPT"
            echo "  iptables -A INPUT   -i $SMB_IFACE -p tcp --dport 139 -j ACCEPT"
            echo "  iptables -A FORWARD -i $SMB_IFACE -p tcp --dport 139 -j ACCEPT"
            echo ""
            ;;
        *)
            echo "NetBIOS disabled"
            ;;
    esac

    systemctl daemon-reload
    systemctl restart smbd winbind rsyslog apache2

    # detect server IP from SMB_IFACE
    SERVER_IP=$(ip -4 addr show "$SMB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    if [ -z "$SERVER_IP" ]; then
        echo "WARNING: Could not detect IP for interface $SMB_IFACE"
        SERVER_IP=""
    fi

    # create Samba account for local user
    SMBNAME="$local_user"
    while true; do
        read -s -p "Enter Samba password for $SMBNAME: " smb_pass; echo
        read -s -p "Confirm password: " smb_pass2; echo
        [ "$smb_pass" = "$smb_pass2" ] && break
        echo "Passwords do not match. Try again."
    done
    printf "%s\n%s\n" "$smb_pass" "$smb_pass" | smbpasswd -a -s "$SMBNAME"
    unset smb_pass smb_pass2

    # TRUSTED_PROXIES: used by web/shared.php to decide whether the
    # CF-Connecting-IP / X-Forwarded-For headers can be trusted when
    # logging the client IP for web operations (upload/mkdir/delete).
    # Set to 127.0.0.1 so that, if this host is ever reached through a
    # local tunnel (cloudflared or similar), the tunnel's own loopback
    # connection isn't logged as the "client" - the real visitor IP from
    # the forwarded header is used instead. For plain LAN access this has
    # no effect: REMOTE_ADDR is simply used as-is.
    TRUSTED_PROXIES="127.0.0.1"

    # save install config
    cat > "$SMBSTACK_ENV" <<ENV
LOCAL_USER="$local_user"
SHARED_NAME="$SHARED_NAME"
SHARED_PATH="$SHARED_PATH"
SMB_NET="$SMB_NET"
SMB_IFACE="$SMB_IFACE"
SERVER_IP="$SERVER_IP"
SMBNAME="$SMBNAME"
NETBIOS="${netbios_ans:-N}"

# TRUSTED_PROXIES: IPv4 address(es), comma-separated, whose REMOTE_ADDR
# is trusted to supply the real client IP via CF-Connecting-IP /
# X-Forwarded-For headers (used by web/shared.php for audit logging).
# Default 127.0.0.1 avoids logging the loopback connection of a local
# tunnel (if any) as the client. Safe to leave as-is for LAN-only use.
TRUSTED_PROXIES="$TRUSTED_PROXIES"
ENV
    chown root:www-data "$SMBSTACK_ENV"
    chmod 640 "$SMBSTACK_ENV"

    echo ""
    echo "Audit log  : /var/log/samba/log.audit"
    echo "Audit web  : http://localhost:3092/audit"
    echo "Shared web : http://localhost:3092/shared"
    echo "Shared dir : $SHARED_PATH"
    echo "Tools dir  : $SMBSTACK_TOOLS"
    echo "Env file   : $SMBSTACK_ENV"
    echo "Check conf : testparm"
    echo ""
    echo "NOTE: The shared folder is independent of the Samba installer."
    echo "      To remove it, you must do so manually: rm -rf $SHARED_PATH"
    echo "      To use a custom path, edit smb.conf and smbweb.conf manually after install."
    echo ""
    echo "DONE"
}

### UPDATE
do_update() {
    if [ ! -f "$SMBSTACK_ENV" ]; then
        echo "ERROR: smbstack is not installed."
        exit 1
    fi

    # load saved config
    local allowed_env_keys=" LOCAL_USER SHARED_NAME SHARED_PATH SMB_NET SMB_IFACE SERVER_IP SMBNAME NETBIOS TRUSTED_PROXIES WATCH_LIMIT_GB WATCH_EXCLUDE "
    while IFS= read -r line; do
        [[ "$line" =~ ^[A-Z_]+=.* ]] && {
            key="${line%%=*}"
            val="${line#*=}"
            val=$(echo "$val" | tr -d '"')
            case "$allowed_env_keys" in
                *" $key "*) export "$key=$val" ;;
                *) echo "WARNING: ignoring unknown key in $SMBSTACK_ENV: $key" ;;
            esac
        }
    done < "$SMBSTACK_ENV"
    echo "Updating with config: user=$LOCAL_USER shared=$SHARED_PATH net=$SMB_NET iface=$SMB_IFACE"
    echo ""

    # web files (application code only - no user-customized config files)
    for src in "$WEB_DIR"/*; do
        [ -f "$src" ] || continue
        fname="$(basename "$src")"
        case "$fname" in
            smbaudit.html|smbapi.php|smbaudit-diagnostic.php|shared.php)
                dst="$SMBSTACK_WEB/$fname"
                ;;
            *)
                continue
                ;;
        esac
        [ -f "$dst" ] || continue
        cp -f "$dst" "${dst}.bak" &>/dev/null
        cp -f "$src" "$dst"
        sed -i "s|your_user|$LOCAL_USER|g" "$dst"
        sed -i "s|compartida|$SHARED_NAME|g" "$dst"
        echo "  Updated: $fname"
    done

    # tools
    for f in "$TOOLS_DIR"/*.sh; do
        [ -f "$f" ] || continue
        fname="$(basename "$f")"
        cp -f "$SMBSTACK_TOOLS/$fname" "$SMBSTACK_TOOLS/$fname.bak" &>/dev/null
        cp -f "$f" "$SMBSTACK_TOOLS/$fname"
        chmod +x "$SMBSTACK_TOOLS/$fname"
        echo "  Updated: $fname"
    done

    systemctl daemon-reload
    systemctl restart smbd winbind rsyslog apache2

    echo ""
    echo "DONE"
}

### UNINSTALL
do_uninstall() {
    # load samba username from env
    if [ -f "$SMBSTACK_ENV" ]; then
        SMBNAME=$(grep "^SMBNAME=" "$SMBSTACK_ENV" | cut -d= -f2 | tr -d '"')
        if [ -n "$SMBNAME" ]; then
            pdbedit -x "$SMBNAME" 2>/dev/null || true
            echo "Samba user removed: $SMBNAME"
        fi
    fi
    userdel smbguest 2>/dev/null || true

    # apache sites
    a2dissite -q smbweb.conf &>/dev/null
    sed -i '/Listen 0.0.0.0:3092/d' /etc/apache2/ports.conf
    rm -f /etc/apache2/sites-available/smbweb.conf

    # project web directory
    rm -rf "$SMBSTACK_WWW"

    # rsyslog
    rm -f /etc/rsyslog.d/fullaudit.conf
    [ -f /etc/rsyslog.conf.bak ] && cp -f /etc/rsyslog.conf.bak /etc/rsyslog.conf

    # logrotate
    [ -f /etc/logrotate.d/samba.bak ] && cp -f /etc/logrotate.d/samba.bak /etc/logrotate.d/samba
    [ -f /etc/logrotate.d/rsyslog.bak ] && cp -f /etc/logrotate.d/rsyslog.bak /etc/logrotate.d/rsyslog
    rm -f /etc/logrotate.d/smbwatch /etc/logrotate.d/smbwatch.bak

    # smb.conf
    [ -f /etc/samba/smb.conf.bak ] && cp -f /etc/samba/smb.conf.bak /etc/samba/smb.conf

    # smbd.service
    [ -f /lib/systemd/system/smbd.service.bak ] && cp -f /lib/systemd/system/smbd.service.bak /lib/systemd/system/smbd.service

    # cron entries
    crontab -l 2>/dev/null > "/root/crontab-uninstall-$(date +%Y%m%d%H%M%S).bak" || true
    crontab -l 2>/dev/null | grep -v "\.recycle" | grep -v "smbload.sh" | grep -v "smbwatch.sh" | crontab -

    # samba packages
    DEBIAN_FRONTEND=noninteractive apt-get remove -y samba samba-common samba-common-bin smbclient winbind cifs-utils
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

    systemctl daemon-reload
    systemctl restart apache2 rsyslog

    echo "DONE"
}

### STATUS
do_status() {
    echo "=== Samba Services ==="
    for svc in smbd winbind; do
        if systemctl is-active --quiet "$svc"; then
            echo "  $svc: RUNNING"
        else
            echo "  $svc: STOPPED"
        fi
    done

    echo ""
    echo "=== Apache Ports ==="
    for port in 3092; do
        if ss -tlnp | grep -q ":$port"; then
            echo "  :$port OPEN"
        else
            echo "  :$port CLOSED"
        fi
    done

    echo ""
    echo "=== Audit Log ==="
    if [ -f /var/log/samba/log.audit ]; then
        echo "  Last 5 entries:"
        tail -5 /var/log/samba/log.audit | sed 's/^/    /'
    else
        echo "  /var/log/samba/log.audit not found"
    fi

    echo ""
    echo "=== smb.conf ==="
    testparm -s 2>/dev/null | head -20 | sed 's/^/  /' || echo "  testparm not available"
}

### MENU
show_menu() {
    echo ""
    echo "smbstack installer"
    echo "------------------"
    echo "  1) Install"
    echo "  2) Update"
    echo "  3) Uninstall"
    echo "  4) Status"
    echo "  5) Exit"
    echo ""
    read -p "Select option: " opt
    case "$opt" in
        1) do_install ;;
        2) do_update ;;
        3) do_uninstall ;;
        4) do_status ;;
        5) exit 0 ;;
        *) echo "Invalid option"; show_menu ;;
    esac
}

### ARGUMENT HANDLING
case "${1:-}" in
    --install)   do_install ;;
    --update)    do_update ;;
    --uninstall) do_uninstall ;;
    --status)    do_status ;;
    "")          show_menu ;;
    *)
        echo "Usage: $(basename "$0") [--install|--update|--uninstall|--status]"
        exit 1
        ;;
esac
