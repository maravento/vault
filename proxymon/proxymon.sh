#!/bin/bash
# maravento.com
# GPL-3.0 https://www.gnu.org/licenses/gpl.txt
#
# Proxy Monitor module installation/uninstallation script

set -e
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════════
# INITIAL CHECKS
# ════════════════════════════════════════════════════════════════

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

check_dependencies() {
    declare -A pkgs_alts
    pkgs_alts=(
        [squid]="squid squid-openssl"
        [apache2]="apache2 apache2-bin apache2-data apache2-doc apache2-utils"
    )

    pkgs='wget git tar ipset libnotify-bin nbtscan libcgi-session-perl libgd-perl python-is-python3 coreutils sarg php libapache2-mod-php php-cli fonts-lato fonts-liberation fonts-dejavu'
    for p in "${!pkgs_alts[@]}"; do
        pkgs+=" $p"
    done

    missing=""
    for p in $pkgs; do
        if [[ -n "${pkgs_alts[$p]}" ]]; then
            found=false
            for alt in ${pkgs_alts[$p]}; do
                dpkg -s "$alt" &>/dev/null && { found=true; break; }
            done
            if ! $found; then
                missing+=" $p"
            fi
        else
            dpkg -s "$p" &>/dev/null || missing+=" $p"
        fi
    done

    missing=$(echo "$missing" | xargs)
    if [[ -n "$missing" ]]; then
        echo -e "${RED}❌ Missing dependencies: $missing${NC}"
        echo -e "${YELLOW}Please install manually with:${NC}"
        echo -e "apt-get install $missing"
        echo -e "${YELLOW}After installation, if apache2-doc has issues, run:${NC}"
        echo -e "apt -qq install -y --reinstall apache2-doc"
        exit 1
    else
        echo -e "${GREEN}✅ All dependencies are installed${NC}"
    fi
}

check_apache_config() {
    if command -v php >/dev/null 2>&1; then
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    else
        echo -e "${RED}❌ PHP is not installed${NC}"
        exit 1
    fi
    
    config_errors=""

    if [ ! -f /etc/apache2/mods-available/mpm_prefork.conf ]; then
        config_errors+="❌ /etc/apache2/mods-available/mpm_prefork.conf not found\n"
    fi

    if [ ! -f /etc/php/$PHP_VERSION/apache2/php.ini ]; then
        if [ -f /etc/php/$PHP_VERSION/cli/php.ini ]; then
            mkdir -p /etc/php/$PHP_VERSION/apache2
            cp /etc/php/$PHP_VERSION/cli/php.ini /etc/php/$PHP_VERSION/apache2/php.ini
            echo -e "${GREEN}✅ php.ini copied to /etc/php/$PHP_VERSION/apache2/${NC}"
        else
            config_errors+="❌ php.ini not found\n"
        fi
    fi

    if ! apache2ctl -M 2>/dev/null | grep -q "mpm_prefork"; then
        config_errors+="❌ mpm_prefork module is not enabled\n"
    fi

    if ! apache2ctl -M 2>/dev/null | grep -q "php_module"; then
        config_errors+="❌ php_module is not enabled\n"
    fi

    if [[ -n "$config_errors" ]]; then
        echo -e "${RED}$config_errors${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ Apache and PHP configuration is valid${NC}"
    fi
}

check_squid_traffic() {
    if [ ! -f /var/log/squid/access.log ]; then
        echo -e "${RED}❌ /var/log/squid/access.log not found${NC}"
        exit 1
    fi

    log_lines=$(wc -l < /var/log/squid/access.log 2>/dev/null || echo 0)

    if [ "$log_lines" -eq 0 ]; then
        echo -e "${RED}❌ access.log is empty (0 lines)${NC}"
        exit 1
    fi

    log_entries=$(grep -cE "TCP_(HIT|MISS|TUNNEL|DENIED|ERROR)" /var/log/squid/access.log 2>/dev/null || echo 0)

    if [ "$log_entries" -eq 0 ]; then
        echo -e "${RED}❌ No valid traffic found ($log_lines lines, 0 valid)${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ Squid traffic: $log_lines lines, $log_entries valid entries${NC}"
    fi
}

run_initial_checks() {
    echo -e "${BLUE}Running initial checks...${NC}\n"
    check_dependencies
    check_apache_config
    check_squid_traffic
    echo -e "${GREEN}All checks passed!${NC}\n"
}

# ════════════════════════════════════════════════════════════════
# INSTALL FUNCTION
# ════════════════════════════════════════════════════════════════

install_proxymon() {
    echo -e "${YELLOW}📥 Downloading Proxy Monitor...${NC}"
    wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
    chmod +x gitfolderdl.py
    python3 gitfolderdl.py https://github.com/maravento/vault/proxymon 2>/dev/null || {
        echo -e "${RED}❌ Failed to download Proxy Monitor${NC}"
        exit 1
    }
    
    if [[ -f "proxymon/modules.tar.gz" ]]; then
        tar -xf proxymon/modules.tar.gz
    else
        echo -e "${RED}❌ modules.tar.gz not found${NC}"
        exit 1
    fi
    
    mkdir -p /var/www/proxymon
    if [[ -d "modules" && -f "modules/index.html" ]]; then
        cp -rf modules/* /var/www/proxymon/
    else
        echo -e "${RED}❌ modules directory or index.html not found${NC}"
        exit 1
    fi
    
    rm -rf proxymon gitfolderdl.py modules
    
    echo -e "${YELLOW}⚙️  Configuring Apache...${NC}"
    
    if [[ -f "/var/www/proxymon/tools/proxymon.conf" ]]; then
        cp -f /var/www/proxymon/tools/proxymon.conf /etc/apache2/sites-available/proxymon.conf
        echo -e "${GREEN}✅ Proxymon virtualhost configured${NC}"
    fi
    
    if [[ -f "/var/www/proxymon/warning/warning.conf" ]]; then
        cp -f /var/www/proxymon/warning/warning.conf /etc/apache2/sites-available/warning.conf
        echo -e "${GREEN}✅ Warning virtualhost configured${NC}"
    fi
    
    if ! grep -qxF 'Listen 0.0.0.0:18080' /etc/apache2/ports.conf && ! grep -qxF 'Listen 18080' /etc/apache2/ports.conf; then
        echo 'Listen 0.0.0.0:18080' >> /etc/apache2/ports.conf
        echo -e "${GREEN}✅ Port 18080 added to Apache${NC}"
    fi
    
    if ! grep -qxF 'Listen 0.0.0.0:18081' /etc/apache2/ports.conf && ! grep -qxF 'Listen 18081' /etc/apache2/ports.conf; then
        echo 'Listen 0.0.0.0:18081' >> /etc/apache2/ports.conf
        echo -e "${GREEN}✅ Port 18081 added to Apache${NC}"
    fi
    
    echo -e "${YELLOW}🔧 Configuring LightSquid...${NC}"
    /var/www/proxymon/lightsquid/lightparser.pl today
    echo -e "${GREEN}✅ Initial LightSquid report generated${NC}"
    
    sudo -u www-data crontab -l 2>/dev/null | {
        cat
        echo "*/10 * * * * /var/www/proxymon/lightsquid/lightparser.pl today"
    } | sudo -u www-data crontab -
    
    echo -e "${YELLOW}🔧 Configuring Squid Monitor...${NC}"
    read -p "Enter Your Server IP For LAN (default: 192.168.0.10): " serverip
    serverip=${serverip:-192.168.0.10}
    sed -i "s/192.168.0.10/$serverip/g" /var/www/proxymon/tools/bandata.sh

    LANPREFIX=$(echo "$serverip" | cut -d'.' -f1-3)
    LANPREFIX="${LANPREFIX}*"
    sed -i "s/192.168.0\*/$(echo $LANPREFIX | sed 's/\*/\\*/g')/g" /var/www/proxymon/tools/bandata.sh

    echo -e "${YELLOW}Your Net Interfaces Are:${NC}"
    ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
    read -p "Enter LAN Net Interface (e.g: enpXsX, default: eth1): " LAN
    LAN=${LAN:-eth1}
    sed -i "s/eth1/$LAN/g" /var/www/proxymon/tools/bandata.sh
    chmod +x /var/www/proxymon/tools/bandata.sh

    echo -e "${YELLOW}📥 Downloading Example ACL files...${NC}"
    mkdir -p /etc/acl

    wget -q --show-progress -N https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/blocktlds.txt -O /etc/acl/blocktlds.txt
    chmod 644 /etc/acl/blocktlds.txt
    chown root:root /etc/acl/blocktlds.txt
    echo -e "${GREEN}✅ blocktlds.txt downloaded${NC}"

    wget -q --show-progress -N https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/debugbl.txt -O /etc/acl/blocksites.txt
    chmod 644 /etc/acl/blocksites.txt
    chown root:root /etc/acl/blocksites.txt
    echo -e "${GREEN}✅ blocksites.txt downloaded${NC}"

    crontab -l 2>/dev/null | {
        cat
        echo "*/12 * * * * /var/www/proxymon/tools/bandata.sh"
    } | crontab -
    echo -e "${GREEN}✅ Squid Monitor crontab added${NC}"
    
    echo -e "${YELLOW}🔧 Configuring SARG...${NC}"
    mkdir -p /var/www/proxymon/sarg/squid-reports
    
    cp -f /etc/sarg/sarg.conf{,.bak} &>/dev/null
    sed -i 's|output_dir /var/lib/sarg|output_dir /var/www/proxymon/sarg/squid-reports|g' /etc/sarg/sarg.conf
    sed -i 's|^resolve_ip .*|resolve_ip no|g' /etc/sarg/sarg.conf
    sed -i 's|lastlog 0|lastlog 7|g' /etc/sarg/sarg.conf
    
    HOSTNAME=$(hostname)
    cp -f /etc/sarg/usertab{,.bak} &>/dev/null
    
    if ! grep -q "^$serverip" /etc/sarg/usertab; then
        echo "$serverip $HOSTNAME" >> /etc/sarg/usertab
        echo -e "${GREEN}✅ Added $serverip $HOSTNAME to usertab${NC}"
    fi
    
    echo -e "${YELLOW}🔧 Generating Initial SARG Report...${NC}"
    timeout 30 /usr/bin/sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log > /dev/null 2>&1 || true
    echo -e "${GREEN}✅ Initial SARG report generated${NC}"
    
    sudo -u www-data crontab -l 2>/dev/null | {
        cat
        echo "@daily /usr/bin/sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log"
    } | sudo -u www-data crontab -

    sudo -u www-data crontab -l 2>/dev/null | {
        cat
        echo '@weekly find /var/www/proxymon/sarg/squid-reports -name "2*" -mtime +30 -type d -exec rm -rf "{}" \;'
    } | sudo -u www-data crontab -
    
    echo -e "${YELLOW}🔧 Configuring SquidAnalyzer...${NC}"
    chmod -R 755 /var/www/proxymon/squidanalyzer
    chown -R www-data:www-data /var/www/proxymon/squidanalyzer
    
    mkdir -p /var/www/proxymon/squidanalyzer/output
    rm -rf /var/www/proxymon/squidanalyzer/output/* 2>/dev/null

    cd /var/www/proxymon/squidanalyzer || exit 1
    sudo -u www-data perl -I. ./squid-analyzer -c etc/squidanalyzer.conf -d &> /dev/null
    cd - > /dev/null

    sudo -u www-data crontab -l 2>/dev/null | {
        grep -v squid-analyzer
        echo '0 2 * * * cd /var/www/proxymon/squidanalyzer && perl -I. ./squid-analyzer -c etc/squidanalyzer.conf'
    } | sudo -u www-data crontab -
    echo -e "${GREEN}✅ SquidAnalyzer crontab added${NC}"
    
    echo -e "${YELLOW}⚙️  Updating Prefork MPM...${NC}"
    cp -f /etc/apache2/mods-available/mpm_prefork.conf{,.bak} &>/dev/null
    sed -i \
      -e 's/^\(StartServers[[:space:]]*\)5/\110/' \
      -e 's/^\(MinSpareServers[[:space:]]*\)5/\110/' \
      -e 's/^\(MaxSpareServers[[:space:]]*\)10/\115/' \
      -e 's/^\(MaxRequestWorkers[[:space:]]*\)150/\1200/' \
      -e 's/^\(MaxConnectionsPerChild[[:space:]]*\)0/\11000/' \
    /etc/apache2/mods-available/mpm_prefork.conf

    echo -e "${YELLOW}⚙️  Updating PHP...${NC}"
    cp -f /etc/php/$PHP_VERSION/apache2/php.ini{,.bak} &>/dev/null
    sed -i \
      -e 's/^\s*;*\s*max_execution_time\s*=.*/max_execution_time = 120/' \
      -e 's/^\s*max_input_time\s*=.*/max_input_time = 120/' \
      -e 's/^;\s*max_input_time\s*=.*/max_input_time = 120/' \
      -e 's/^\s*memory_limit\s*=.*/memory_limit = 1024M/' \
      -e 's/^\s*post_max_size\s*=.*/post_max_size = 64M/' \
      -e 's/^\s*upload_max_filesize\s*=.*/upload_max_filesize = 64M/' \
      -e 's/^\s*;*\s*opcache.memory_consumption\s*=.*/opcache.memory_consumption = 256/' \
      -e 's/^\s*;*\s*realpath_cache_size\s*=.*/realpath_cache_size = 16M/' \
     /etc/php/$PHP_VERSION/apache2/php.ini
     
    # Hardening
    echo -e "${YELLOW}⚙️  Updating Apache2 Security...${NC}"
    if [ -f /etc/apache2/conf-available/security.conf ]; then
        cp -f /etc/apache2/conf-available/security.conf{,.bak} &>/dev/null
    else
        touch /etc/apache2/conf-available/security.conf
    fi
    sed -i "s/^#*\s*ServerSignature.*/ServerSignature Off/" /etc/apache2/conf-available/security.conf
    sed -i "s/^#*\s*ServerTokens.*/ServerTokens Prod/" /etc/apache2/conf-available/security.conf
    declare -A headers=(
        ["X-Content-Type-Options"]="nosniff"
        ["X-Frame-Options"]="sameorigin"
        ["X-XSS-Protection"]="1; mode=block"
        ["Referrer-Policy"]="strict-origin-when-cross-origin"
    )
    for name in "${!headers[@]}"; do
        value="${headers[$name]}"
        if grep -q "Header set $name" /etc/apache2/conf-available/security.conf; then
            sed -i "s|^#*\s*Header set $name.*|Header set $name \"$value\"|" /etc/apache2/conf-available/security.conf
        else
            echo "Header set $name \"$value\"" >> /etc/apache2/conf-available/security.conf
        fi
    done
    grep -q "^FileETag None" /etc/apache2/conf-available/security.conf || \
        echo 'FileETag None' >> /etc/apache2/conf-available/security.conf

    grep -q "^Header unset ETag" /etc/apache2/conf-available/security.conf || \
        echo 'Header unset ETag' >> /etc/apache2/conf-available/security.conf

    grep -q "^Timeout" /etc/apache2/conf-available/security.conf || \
        echo 'Timeout 60' >> /etc/apache2/conf-available/security.conf
    sed -i 's/Options -Indexes FollowSymLinks/Options -Indexes +FollowSymLinks/g' /etc/apache2/apache2.conf
    a2enmod headers &>/dev/null
    a2enconf security &>/dev/null
     
    echo -e "${YELLOW}🔐 Setting Permissions...${NC}"
    chmod -R 755 /var/www/proxymon/
    chown -R www-data:www-data /var/www/proxymon
    usermod -aG proxy www-data
    chown root:root /etc/squid/squid.conf
    chmod 644 /etc/squid/squid.conf
    
    echo -e "${YELLOW}🔐 Setting Logs...${NC}"
    touch /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log
    chown root:adm /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log
    chmod 640 /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log
    chown proxy:proxy /var/log/squid/*.log
    chmod 640 /var/log/squid/*.log
    
    echo -e "${YELLOW}⚙️  Enabling Apache Modules...${NC}"
    a2dismod mpm_event 2>/dev/null || true
    a2enmod mpm_prefork 2>/dev/null || true
    a2enmod php 2>/dev/null || true
    a2enmod cgid 2>/dev/null || true
    a2enmod cgi 2>/dev/null || true
    a2enmod rewrite 2>/dev/null || true
    
    echo -e "${YELLOW}⚙️  Enabling Apache Sites...${NC}"
    a2ensite proxymon.conf || { echo -e "${RED}❌ Failed to enable proxymon.conf${NC}"; exit 1; }
    a2ensite warning.conf || { echo -e "${RED}❌ Failed to enable warning.conf${NC}"; exit 1; }
    
    echo -e "${GREEN}✅ Restarting Cron...${NC}"
    systemctl restart cron
        
    echo -e "${YELLOW}🔐 Restarting Apache2...${NC}"
    systemctl daemon-reload
    apachectl -t -D DUMP_INCLUDES -S &>/dev/null && echo "✅ Apache configuration OK" || echo "❌ Apache configuration error"
    systemctl restart apache2

    echo -e "${GREEN}🌐 Check Active Apache sites:${NC}"
    a2query -s
    
    echo -e "${GREEN}✅ Proxy Monitor installed successfully${NC}"
    echo -e "${GREEN}🌐 Access Proxy Monitor: http://localhost:18080${NC}"
    echo -e "${GREEN}🌐 Access Warning Portal: http://localhost:18081${NC}"
    notify-send "Proxy Monitor Installed" "$(date)" -i checkbox 2>/dev/null || true
}

# ════════════════════════════════════════════════════════════════
# UNINSTALL FUNCTION
# ════════════════════════════════════════════════════════════════

uninstall_proxymon() {
    echo -e "${YELLOW}⚠️  Uninstalling Proxy Monitor...${NC}"
    
    if [[ ! -d "/var/www/proxymon" ]]; then
        if ! (sudo crontab -l 2>/dev/null | grep -q "bandata.sh") && \
           ! (sudo -u www-data crontab -l 2>/dev/null | grep -q "lightparser.pl\|sarg\|squid-analyzer"); then
            echo -e "${YELLOW}⚠️  Proxy Monitor is not installed${NC}"
            return 0
        fi
    fi
    
    sudo -u www-data crontab -l 2>/dev/null | grep -v "lightparser.pl" | sudo -u www-data crontab - 2>/dev/null || true
    echo -e "${GREEN}✅ LightSquid crontab removed${NC}"

    crontab -l 2>/dev/null | grep -v "bandata.sh" | crontab - 2>/dev/null || true
    echo -e "${GREEN}✅ Squid Monitor crontab removed${NC}"

    sudo -u www-data crontab -l 2>/dev/null | grep -vi "sarg" | sudo -u www-data crontab - 2>/dev/null || true
    echo -e "${GREEN}✅ SARG crontab entries removed${NC}"
    
    if [[ -f "/etc/sarg/sarg.conf.bak" ]]; then
        mv -f /etc/sarg/sarg.conf.bak /etc/sarg/sarg.conf
        echo -e "${GREEN}✅ SARG configuration restored${NC}"
    fi
    
    if [[ -f "/etc/sarg/usertab.bak" ]]; then
        mv -f /etc/sarg/usertab.bak /etc/sarg/usertab
        echo -e "${GREEN}✅ SARG usertab restored${NC}"
    fi

    sudo -u www-data crontab -l 2>/dev/null | grep -v "squid-analyzer" | sudo -u www-data crontab - 2>/dev/null || true
    echo -e "${GREEN}✅ SquidAnalyzer crontab removed${NC}"
        
    if [[ -f "/etc/apache2/sites-available/proxymon.conf" ]]; then
        a2dissite proxymon.conf 2>/dev/null || true
        rm -f /etc/apache2/sites-available/proxymon.conf
        echo -e "${GREEN}✅ Proxymon site disabled${NC}"
    fi
    
    if [[ -f "/etc/apache2/sites-available/warning.conf" ]]; then
        a2dissite warning.conf 2>/dev/null || true
        rm -f /etc/apache2/sites-available/warning.conf
        echo -e "${GREEN}✅ Warning site disabled${NC}"
    fi
    
    if [[ -d "/var/www/proxymon" ]]; then
        rm -rf /var/www/proxymon
        echo -e "${GREEN}✅ Installation directory removed${NC}"
    fi
    
    sed -i '/Listen 0.0.0.0:18080/d' /etc/apache2/ports.conf
    sed -i '/Listen 18080/d' /etc/apache2/ports.conf
    echo -e "${GREEN}✅ Port 18080 removed from Apache${NC}"
    
    sed -i '/Listen 0.0.0.0:18081/d' /etc/apache2/ports.conf
    sed -i '/Listen 18081/d' /etc/apache2/ports.conf
    echo -e "${GREEN}✅ Port 18081 removed from Apache${NC}"
    
    rm -f /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log*
    echo -e "${GREEN}✅ Proxymon log files removed${NC}"
    
    systemctl restart cron
    systemctl daemon-reload
    systemctl restart apache2
    
    echo -e "${GREEN}🌐 Remaining Apache sites:${NC}"
    a2query -s
    
    echo -e "${GREEN}✅ Proxy Monitor uninstalled successfully${NC}"
    notify-send "Proxy Monitor Uninstalled" "$(date)" -i checkbox 2>/dev/null || true
}

# ════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════

run_initial_checks

case "${1:-}" in
    install)
        install_proxymon
        exit 0
        ;;
    uninstall)
        read -p "Are you sure you want to uninstall? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall_proxymon
        else
            echo -e "${YELLOW}Uninstall cancelled${NC}"
            exit 0
        fi
        exit 0
        ;;
    -h|--help)
        echo "Proxy Monitor Installation/Uninstallation Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  install      Install Proxy Monitor"
        echo "  uninstall    Uninstall Proxy Monitor"
        echo "  -h, --help   Show this help message"
        exit 0
        ;;
    "")
        show_menu() {
            clear
            echo -e "${BLUE}════════════════════════════════════════${NC}"
            echo -e "${BLUE}    Proxy Monitor Installer${NC}"
            echo -e "${BLUE}════════════════════════════════════════${NC}"
            echo ""
            echo -e "${YELLOW}1${NC} - Install Proxy Monitor"
            echo -e "${YELLOW}2${NC} - Uninstall Proxy Monitor"
            echo -e "${YELLOW}3${NC} - Exit"
            echo ""
            echo -e "${BLUE}════════════════════════════════════════${NC}"
            echo -n "Select an option: "
        }

        while true; do
            show_menu
            read -r option
            
            case "$option" in
                1)
                    echo ""
                    install_proxymon
                    echo ""
                    echo -n "Press Enter to continue..."
                    read -r
                    ;;
                2)
                    echo ""
                    read -p "Are you sure you want to uninstall? (y/n): " -r
                    echo ""
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        uninstall_proxymon
                    else
                        echo -e "${YELLOW}Uninstall cancelled${NC}"
                    fi
                    echo ""
                    echo -n "Press Enter to continue..."
                    read -r
                    ;;
                3)
                    echo -e "${GREEN}Goodbye!${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid option. Please select 1, 2 or 3${NC}"
                    sleep 2
                    ;;
            esac
        done
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        echo "Use: $0 -h for help"
        exit 1
        ;;
esac
