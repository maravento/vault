#!/bin/bash
# maravento.com
# GPL-3.0 https://www.gnu.org/licenses/gpl.txt
#
# Proxy Monitor module installation/uninstallation script
#
# Description:
#   This script installs or uninstalls the Proxy Monitor application.
#   Proxy Monitor provides traffic monitoring and reporting for Squid proxy servers
#   with Squidmon, LightSquid, SARG, Sqstat and Squid Analyzer modules.
#
# Features:
# - LightSquid traffic reporting module (fast reports, per-user statistics, and daily/monthly traffic)
# - SQStat for real-time monitoring
# - SARG report generator (detailed and customizable reports)
# - SquidAnalyzer log analysis module (graphical traffic statistics and usage trends)
# - Bandata script for bandwidth control, usage limits, and quota management (integrated with LightSquid)
# - Squidmon statistics module (advanced statistics, report printing, and ACL-driven operations)
# - Warning portal for quota limit notifications
# - Automatic dependency checking
# - Crontab task management
# - Apache virtual host configuration
#
# Usage:
#   sudo ./proxymon.sh [OPTIONS]
#
# Options:
#   install      Install Proxy Monitor
#   uninstall    Uninstall Proxy Monitor
#   -h, --help   Show help message
#
# Examples:
#   sudo ./proxymon.sh              # Interactive menu
#   sudo ./proxymon.sh install      # Direct installation
#   sudo ./proxymon.sh uninstall    # Direct uninstallation

set -e
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# check root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}This script must be run as root${NC}" 1>&2
    exit 1
fi

# check script execution
if pidof -x "$(basename "$0")" >/dev/null; then
    for p in $(pidof -x "$(basename "$0")"); do
        if [ "$p" -ne $$ ]; then
            echo -e "${RED}Script $0 is already running...${NC}"
            exit 1
        fi
    done
fi

# check SO
check_os() {
    UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "")
    UBUNTU_ID=$(lsb_release -is 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    
    if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
        echo -e "${YELLOW}⚠️  Unsupported system (Ubuntu 22.04/24.04 recommended). Use at your own risk${NC}"
    else
        echo -e "${GREEN}✅ OS: Ubuntu $UBUNTU_VERSION${NC}"
    fi
}

# ════════════════════════════════════════════════════════════════
# INSTALL FUNCTION
# ════════════════════════════════════════════════════════════════

install_proxymon() {
    check_os
    
    # check dependencies
    declare -A pkgs_alts
    pkgs_alts=(
        [squid]="squid squid-openssl"
        [apache2]="apache2 apache2-bin apache2-data"
    )
    
    pkgs='wget git tar ipset libnotify-bin nbtscan libcgi-session-perl libgd-perl python-is-python3 coreutils sarg php php-cli libapache2-mod-php'
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
        echo -e "${YELLOW}📦 Installing missing dependencies: $missing${NC}"
        apt-get update -qq
        apt-get install -y $missing -qq
    else
        echo -e "${GREEN}✅ All dependencies are installed${NC}"
    fi
    
    # Download and install
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
    
    # Create directory and copy files
    mkdir -p /var/www/proxymon
    if [[ -d "modules" && -f "modules/index.html" ]]; then
        cp -rf modules/* /var/www/proxymon/
    else
        echo -e "${RED}❌ modules directory or index.html not found${NC}"
        exit 1
    fi
    
    # Cleanup
    rm -rf proxymon gitfolderdl.py modules
    
    # ════════════════════════════════════════════════════════════════
    # APACHE CONFIGURATION
    # ════════════════════════════════════════════════════════════════
    
    echo -e "${YELLOW}⚙️  Configuring Apache...${NC}"
    
    # Copy virtualhost configs
    if [[ -f "/var/www/proxymon/tools/proxymon.conf" ]]; then
        cp -f /var/www/proxymon/tools/proxymon.conf /etc/apache2/sites-available/proxymon.conf
        echo -e "${GREEN}✅ Proxymon virtualhost configured${NC}"
    fi
    
    if [[ -f "/var/www/proxymon/warning/warning.conf" ]]; then
        cp -f /var/www/proxymon/warning/warning.conf /etc/apache2/sites-available/warning.conf
        echo -e "${GREEN}✅ Warning virtualhost configured${NC}"
    fi
    
    # Create apache log files
    touch /var/log/apache2/{warning_access,warning_error}.log
    chown www-data:adm /var/log/apache2/{warning_access,warning_error}.log
    
    # Add ports to Apache
    if ! grep -qxF 'Listen 0.0.0.0:18080' /etc/apache2/ports.conf && ! grep -qxF 'Listen 18080' /etc/apache2/ports.conf; then
        echo 'Listen 0.0.0.0:18080' >> /etc/apache2/ports.conf
        echo -e "${GREEN}✅ Port 18080 added to Apache${NC}"
    fi
    
    if ! grep -qxF 'Listen 0.0.0.0:18081' /etc/apache2/ports.conf && ! grep -qxF 'Listen 18081' /etc/apache2/ports.conf; then
        echo 'Listen 0.0.0.0:18081' >> /etc/apache2/ports.conf
        echo -e "${GREEN}✅ Port 18081 added to Apache${NC}"
    fi
    
    # ════════════════════════════════════════════════════════════════
    # LIGHTSQUID CONFIGURATION
    # ════════════════════════════════════════════════════════════════
    
    echo -e "${YELLOW}🔧 Configuring LightSquid...${NC}"
    
    /var/www/proxymon/lightsquid/lightparser.pl today
    echo -e "${GREEN}✅ Initial LightSquid report generated${NC}"
    
    sudo -u www-data crontab -l 2>/dev/null | {
        cat
        echo "*/10 * * * * /var/www/proxymon/lightsquid/lightparser.pl today"
    } | sudo -u www-data crontab -
    
    # ════════════════════════════════════════════════════════════════
    # SQUIDMON CONFIGURATION
    # ════════════════════════════════════════════════════════════════

    echo -e "${YELLOW}🔧 Configuring Squid Monitor...${NC}"

    read -p "Enter your Server IP for LAN (default: 192.168.0.10): " serverip
    serverip=${serverip:-192.168.0.10}
    sed -i "s/192.168.0.10/$serverip/g" /var/www/proxymon/tools/bandata.sh

    # Calculate LAN PREFIX from SERVER_IP (first 3 octets)
    LANPREFIX=$(echo "$serverip" | cut -d'.' -f1-3)
    LANPREFIX="${LANPREFIX}*"
    sed -i "s/192.168.0\*/$(echo $LANPREFIX | sed 's/\*/\\*/g')/g" /var/www/proxymon/tools/bandata.sh

    echo -e "${YELLOW}Your net interfaces are:${NC}"
    ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
    read -p "Enter LAN Net Interface (e.g: enpXsX, default: eth1): " LAN
    LAN=${LAN:-eth1}
    sed -i "s/eth1/$LAN/g" /var/www/proxymon/tools/bandata.sh

    chmod +x /var/www/proxymon/tools/bandata.sh

    # Download example ACLs if they don't exist
    echo -e "${YELLOW}📥 Downloading example ACL files...${NC}"
    mkdir -p /etc/acl

    wget -q --show-progress -N https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/blocktlds.txt -O /etc/acl/blocktlds.txt
    chmod 644 /etc/acl/blocktlds.txt
    chown root:root /etc/acl/blocktlds.txt
    echo -e "${GREEN}✅ blocktlds.txt downloaded${NC}"

    wget -q --show-progress -N https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/debugbl.txt -O /etc/acl/blocksites.txt
    chmod 644 /etc/acl/blockdomains.txt
    chown root:root /etc/acl/blockdomains.txt
    echo -e "${GREEN}✅ blockdomains.txt downloaded${NC}"

    crontab -l 2>/dev/null | {
        cat
        echo "*/12 * * * * /var/www/proxymon/tools/bandata.sh"
    } | crontab -
    echo -e "${GREEN}✅ Squid Monitor crontab added${NC}"
    
    # ════════════════════════════════════════════════════════════════
    # SARG CONFIGURATION
    # ════════════════════════════════════════════════════════════════
    
    echo -e "${YELLOW}🔧 Configuring SARG (Squid Analysis Report Generator)...${NC}"
    
    mkdir -p /var/www/proxymon/sarg/squid-reports
    
    # Backup and modify sarg.conf
    cp -f /etc/sarg/sarg.conf{,.bak} &>/dev/null
    sed -i 's|output_dir /var/lib/sarg|output_dir /var/www/proxymon/sarg/squid-reports|g' /etc/sarg/sarg.conf
    sed -i 's|^resolve_ip .*|resolve_ip no|g' /etc/sarg/sarg.conf
    sed -i 's|lastlog 0|lastlog 7|g' /etc/sarg/sarg.conf
    
    # Get hostname
    HOSTNAME=$(hostname)
    
    # Backup and modify usertab
    cp -f /etc/sarg/usertab{,.bak} &>/dev/null
    
    # Add server IP and hostname to usertab
    if ! grep -q "^$serverip" /etc/sarg/usertab; then
        echo "$serverip $HOSTNAME" >> /etc/sarg/usertab
        echo -e "${GREEN}✅ Added $serverip $HOSTNAME to usertab${NC}"
    fi
    
    # Generate initial SARG report
    echo -e "${YELLOW}🔧 Generating initial SARG report...${NC}"
    /usr/sbin/sarg-reports today &>/dev/null && sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log &> /dev/null
    echo -e "${GREEN}✅ Initial SARG report generated${NC}"
    
    sudo -u www-data crontab -l 2>/dev/null | {
        cat
        echo "@daily sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log"
    } | sudo -u www-data crontab -

    sudo -u www-data crontab -l 2>/dev/null | {
        cat
        echo '@weekly find /var/www/proxymon/sarg/squid-reports -name "2*" -mtime +30 -type d -exec rm -rf "{}" \;'
    } | sudo -u www-data crontab -
    
    # ════════════════════════════════════════════════════════════════
    # SQUID ANALYZER
    # ════════════════════════════════════════════════════════════════

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
    
    # ════════════════════════════════════════════════════════════════
    # GLOBAL CONFIGURATION
    # ════════════════════════════════════════════════════════════════
    
    echo -e "${YELLOW}⚙️  Enabling Apache modules...${NC}"
    a2enmod cgid 2>/dev/null || true
    a2enmod cgi 2>/dev/null || true
    a2enmod rewrite 2>/dev/null || true

    echo -e "${YELLOW}⚙️  Enabling Apache sites...${NC}"
    a2ensite proxymon.conf || { echo -e "${RED}❌ Failed to enable proxymon.conf${NC}"; exit 1; }
    a2ensite warning.conf || { echo -e "${RED}❌ Failed to enable warning.conf${NC}"; exit 1; }
    
    echo -e "${YELLOW}🔐 Setting permissions...${NC}"
    
    chmod -R 755 /var/www/proxymon/
    chown -R www-data:www-data /var/www/proxymon
    usermod -aG proxy www-data
    
    systemctl restart cron
    echo -e "${GREEN}✅ Cron service restarted${NC}"
    
    systemctl daemon-reload
    systemctl restart apache2

    echo -e "${GREEN}🌐 Active Apache sites:${NC}"
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
    
    # Verify installation exists
    if [[ ! -d "/var/www/proxymon" ]] && ! (crontab -l 2>/dev/null | grep -q "lightparser.pl\|bandata.sh\|sarg -l\|squid-reports"); then
        echo -e "${YELLOW}⚠️  Proxy Monitor is not installed${NC}"
        return 0
    fi
    
    # ════════════════════════════════════════════════════════════════
    # LIGHTSQUID UNINSTALL
    # ════════════════════════════════════════════════════════════════
    
    crontab -l 2>/dev/null | grep -v "lightparser.pl" | crontab -
    echo -e "${GREEN}✅ LightSquid crontab removed${NC}"
    
    # ════════════════════════════════════════════════════════════════
    # SQUIDMON UNINSTALL
    # ════════════════════════════════════════════════════════════════
    
    crontab -l 2>/dev/null | grep -v "bandata.sh" | crontab -
    echo -e "${GREEN}✅ Squid Monitor crontab removed${NC}"
    
    # ════════════════════════════════════════════════════════════════
    # SARG UNINSTALL
    # ════════════════════════════════════════════════════════════════
    
    crontab -l 2>/dev/null | grep -vi "sarg" | crontab -
    echo -e "${GREEN}✅ SARG crontab entries removed${NC}"
    
    # Restore SARG configuration files
    if [[ -f "/etc/sarg/sarg.conf.bak" ]]; then
        mv -f /etc/sarg/sarg.conf.bak /etc/sarg/sarg.conf
        echo -e "${GREEN}✅ SARG configuration restored${NC}"
    fi
    
    if [[ -f "/etc/sarg/usertab.bak" ]]; then
        mv -f /etc/sarg/usertab.bak /etc/sarg/usertab
        echo -e "${GREEN}✅ SARG usertab restored${NC}"
    fi

    # ════════════════════════════════════════════════════════════════
    # SQUID ANALYZER UNINSTALL
    # ════════════════════════════════════════════════════════════════
    
    crontab -l 2>/dev/null | grep -v "squid-analyzer" | crontab -
    echo -e "${GREEN}✅ SquidAnalyzer crontab removed${NC}"
        
    # ════════════════════════════════════════════════════════════════
    # GLOBAL UNINSTALL
    # ════════════════════════════════════════════════════════════════
    
    # Disable Apache sites
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
    
    # Remove installation directory
    if [[ -d "/var/www/proxymon" ]]; then
        rm -rf /var/www/proxymon
        echo -e "${GREEN}✅ Installation directory removed${NC}"
    fi
    
    # Remove ports from Apache
    sed -i '/Listen 0.0.0.0:18080/d' /etc/apache2/ports.conf
    sed -i '/Listen 18080/d' /etc/apache2/ports.conf
    echo -e "${GREEN}✅ Port 18080 removed from Apache${NC}"
    
    sed -i '/Listen 0.0.0.0:18081/d' /etc/apache2/ports.conf
    sed -i '/Listen 18081/d' /etc/apache2/ports.conf
    echo -e "${GREEN}✅ Port 18081 removed from Apache${NC}"
    
    # Remove Apache log files
    rm -f /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log*
    echo -e "${GREEN}✅ Apache log files removed${NC}"
    
    systemctl restart cron
    systemctl daemon-reload
    systemctl restart apache2
    
    echo -e "${GREEN}🌐 Remaining Apache sites:${NC}"
    a2query -s
    
    echo -e "${GREEN}✅ Proxy Monitor uninstalled successfully${NC}"
    notify-send "Proxy Monitor Uninstalled" "$(date)" -i checkbox 2>/dev/null || true
}

# ════════════════════════════════════════════════════════════════
# SHOW HELP
# ════════════════════════════════════════════════════════════════

show_help() {
    echo "Proxy Monitor Installation/Uninstallation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install      Install Proxy Monitor"
    echo "  uninstall    Uninstall Proxy Monitor"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Examples:"
    echo "  sudo $0              # Interactive menu"
    echo "  sudo $0 install      # Direct installation"
    echo "  sudo $0 uninstall    # Direct uninstallation"
    exit 0
}

# ════════════════════════════════════════════════════════════════
# COMMAND LINE ARGUMENT PROCESSING
# ════════════════════════════════════════════════════════════════

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
        show_help
        ;;
    "")
        # Interactive menu if no argument provided
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        show_help
        ;;
esac

# ════════════════════════════════════════════════════════════════
# INTERACTIVE MENU
# ════════════════════════════════════════════════════════════════

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

# Main loop
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
