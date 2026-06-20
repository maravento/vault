#!/bin/bash
# maravento.com
#
################################################################################
#
# Proxy Monitor module installation/uninstallation script
#
################################################################################

set -e
trap 'echo "Error on line $LINENO"; exit 1' ERR

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
mkdir -p /var/lock
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

    pkgs='wget git ipset nbtscan libcgi-session-perl libgd-perl coreutils sarg php libapache2-mod-php php-cli php-curl fonts-lato fonts-liberation fonts-dejavu'
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
        echo -e "${RED}Missing dependencies: $missing${NC}"
        echo -e "${YELLOW}Please install manually with:${NC}"
        echo -e "apt-get install $missing"
        echo -e "${YELLOW}After installation, if apache2-doc has issues, run:${NC}"
        echo -e "apt -qq install -y --reinstall apache2-doc"
        exit 1
    else
        echo -e "${GREEN}All dependencies are installed${NC}"
    fi
}

check_apache_config() {
    if command -v php >/dev/null 2>&1; then
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    else
        echo -e "${RED}PHP is not installed${NC}"
        exit 1
    fi

    if [[ ! "$PHP_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Could not determine PHP version (got '$PHP_VERSION'). Is PHP working correctly?${NC}"
        exit 1
    fi
    
    config_errors=""

    if [ ! -f /etc/apache2/mods-available/mpm_prefork.conf ]; then
        config_errors+="/etc/apache2/mods-available/mpm_prefork.conf not found\n"
    fi

    if [ ! -f /etc/php/$PHP_VERSION/apache2/php.ini ]; then
        if [ -f /etc/php/$PHP_VERSION/cli/php.ini ]; then
            mkdir -p /etc/php/$PHP_VERSION/apache2
            cp /etc/php/$PHP_VERSION/cli/php.ini /etc/php/$PHP_VERSION/apache2/php.ini
            echo -e "${GREEN}php.ini copied to /etc/php/$PHP_VERSION/apache2/${NC}"
        else
            config_errors+="php.ini not found\n"
        fi
    fi

    if ! apache2ctl -M 2>/dev/null | grep -q "mpm_prefork"; then
        config_errors+="mpm_prefork module is not enabled\n"
    fi

    if ! apache2ctl -M 2>/dev/null | grep -qE "php[0-9.]*_module"; then
        config_errors+="php module is not enabled\n"
    fi

    if [[ -n "$config_errors" ]]; then
        echo -e "${RED}$config_errors${NC}"
        exit 1
    else
        echo -e "${GREEN}Apache and PHP configuration is valid${NC}"
    fi
}

check_squid_traffic() {
    if [ ! -f /var/log/squid/access.log ]; then
        echo -e "${RED}/var/log/squid/access.log not found${NC}"
        exit 1
    fi

    log_lines=$(wc -l < /var/log/squid/access.log 2>/dev/null || echo 0)

    if [ "$log_lines" -eq 0 ]; then
        echo -e "${RED}access.log is empty (0 lines)${NC}"
        exit 1
    fi

    log_entries=$(grep -cE "TCP_(HIT|MISS|TUNNEL|DENIED|ERROR)" /var/log/squid/access.log 2>/dev/null || echo 0)

    if [ "$log_entries" -eq 0 ]; then
        echo -e "${RED}No valid traffic found ($log_lines lines, 0 valid)${NC}"
        exit 1
    else
        echo -e "${GREEN}Squid traffic: $log_lines lines, $log_entries valid entries${NC}"
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
# REPOSITORY STRUCTURE CHECK
# ════════════════════════════════════════════════════════════════

check_repo() {
    local missing=0
    if [ ! -d "modules" ] || [ -z "$(ls -A "modules" 2>/dev/null)" ]; then
        missing=1
    fi
    if [ "$missing" -eq 1 ]; then
        echo ""
        echo "ERROR: Repository files not found. Run:"
        echo ""
        echo "  wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py"
        echo "  chmod +x gitfolder.py"
        echo "  python3 gitfolder.py https://github.com/maravento/vault/proxymon"
        echo ""
        exit 1
    fi
}

# ════════════════════════════════════════════════════════════════
# PROXYMON ENV CONFIGURATION
# ════════════════════════════════════════════════════════════════

create_proxymon_env() {
    local env_file="/etc/proxymon/proxymon.env"
    mkdir -p /etc/proxymon

    if [ -f "$env_file" ]; then
        echo -e "${GREEN}$env_file already exists — skipping configuration${NC}"
        # Warn if a newer version of this script expects variables
        # not present in an existing env file (version drift).
        local required_vars="LAN SERVER_IP RANGE REPORT_PATH ACL_PATH ACL_MAC_PATH ACL_SQUID_PATH ACL_BANDATA_PATH ALLOW_LIST BLOCK_LIST_DAY BLOCK_LIST_WEEK BLOCK_LIST_MONTH MAX_BANDWIDTH_DAY MAX_BANDWIDTH_WEEK MAX_BANDWIDTH_MONTH UNIFI_HOTSPOT_ENABLED HOTSPOT_PATH UPDATE_REALNAME"
        local missing=""
        for var in $required_vars; do
            grep -q "^${var}=" "$env_file" || missing="$missing $var"
        done
        if [ -n "$missing" ]; then
            echo -e "${YELLOW}WARNING: $env_file is missing variables expected by this version:${NC}"
            echo -e "${YELLOW}  $missing${NC}"
            echo -e "${YELLOW}  Add them manually, or remove $env_file and re-run install to regenerate.${NC}"
        fi
        return 0
    fi

    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}    Bandata Configuration${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    printf "\n"

    # LAN interface
    echo -e "${YELLOW}Available network interfaces:${NC}"
    ip -o link | awk '$2 != "lo:" {print "  " $2, $(NF-2)}' | sed 's_: _ _'
    _lan_default=$(ip -o link | awk -F': ' '$2 != "lo" {print $2; exit}')
    _lan_default=${_lan_default:-eth0}
    while true; do
        read -rp "LAN interface (default: $_lan_default): " _lan
        _lan=${_lan:-$_lan_default}
        if [ -e "/sys/class/net/$_lan" ]; then
            break
        fi
        echo -e "${RED}Interface '$_lan' not found on this system. Try again.${NC}"
    done

    # Server IP
    while true; do
        read -rp "Server IP for LAN (default: 192.168.0.10): " _serverip
        _serverip=${_serverip:-192.168.0.10}
        if [[ "$_serverip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
            valid=true
            for octet in "${BASH_REMATCH[@]:1}"; do
                if [ "$octet" -gt 255 ]; then valid=false; fi
            done
            [ "$valid" = true ] && break
        fi
        echo -e "${RED}'$_serverip' is not a valid IPv4 address. Try again.${NC}"
    done

    # Derive range from server IP (first 3 octets + *)
    # NOTE: assumes a /24 subnet. For non-standard subnets, edit RANGE
    # manually in /etc/proxymon/proxymon.env after installation.
    _range="$(echo "$_serverip" | cut -d'.' -f1-3)*"

    # Bandwidth limits — validate with numfmt (accepts e.g. 500M, 1G, 1.5G)
    read_bandwidth() {
        local prompt="$1" default="$2" result
        while true; do
            read -rp "$prompt" result
            result=${result:-$default}
            if LC_ALL=C numfmt --from=iec "${result/,/.}" >/dev/null 2>&1; then
                echo "$result"
                return
            fi
            echo -e "${RED}'$result' is not a valid size (e.g. 500M, 1G, 1.5G). Try again.${NC}" >&2
        done
    }
    _bw_day=$(read_bandwidth "Max bandwidth per day   (default: 1G): " "1G")
    _bw_week=$(read_bandwidth "Max bandwidth per week  (default: 5G): " "5G")
    _bw_month=$(read_bandwidth "Max bandwidth per month (default: 20G): " "20G")

    # Unifi Hotspot — only ask if /etc/uhotspot exists
    _hotspot_enabled=false
    _hotspot_path="/etc/uhotspot"
    if [ -d "/etc/uhotspot" ]; then
        read -rp "Se ha detectado Unifi Hotspot. ¿Desea activarlo en Bandata? (y/n, default: n): " _hs
        if [[ "$_hs" =~ ^[Yy]$ ]]; then
            _hotspot_enabled=true
        fi
    fi

    # Auto-update Lightsquid realname
    read -rp "Actualizar hostnames en Lightsquid automáticamente? (y/n, default: n): " _realname
    if [[ "$_realname" =~ ^[Yy]$ ]]; then
        _update_realname=true
    else
        _update_realname=false
    fi

    cat > "$env_file" << ENVEOF
# proxymon.env — Bandata configuration
# Generated by proxymon.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Edit manually if needed. Re-run proxymon.sh install to regenerate.

# Network
LAN=${_lan}
SERVER_IP=${_serverip}
RANGE=${_range}

# Paths (defaults — edit only if your setup differs)
LIGHTSQUID_DIR=/var/www/proxymon/lightsquid
REPORT_PATH=$LIGHTSQUID_DIR/report
REALNAME_CFG=$LIGHTSQUID_DIR/realname.cfg
SKIPUSERS_CFG=$LIGHTSQUID_DIR/skipuser.cfg
ACL_PATH=/etc/acl
ACL_MAC_PATH=$ACL_PATH/acl_mac
ACL_SQUID_PATH=$ACL_PATH/acl_squid
ACL_BANDATA_PATH=$ACL_PATH/acl_bandata
ALLOW_LIST=$ACL_BANDATA_PATH/allowdata.txt
BLOCK_LIST_DAY=$ACL_BANDATA_PATH/banday.txt
BLOCK_LIST_WEEK=$ACL_BANDATA_PATH/banweek.txt
BLOCK_LIST_MONTH=$ACL_BANDATA_PATH/banmonth.txt

# Bandwidth limits
MAX_BANDWIDTH_DAY=${_bw_day}
MAX_BANDWIDTH_WEEK=${_bw_week}
MAX_BANDWIDTH_MONTH=${_bw_month}

# Unifi Hotspot
UNIFI_HOTSPOT_ENABLED=${_hotspot_enabled}
HOTSPOT_PATH=${_hotspot_path}

# Lightsquid realname auto-update
UPDATE_REALNAME=${_update_realname}
ENVEOF

    chmod 640 "$env_file"
    chown root:root "$env_file"
    echo -e "${GREEN}$env_file created${NC}"
    printf "\n"
}

# ════════════════════════════════════════════════════════════════
# INSTALL FUNCTION
# ════════════════════════════════════════════════════════════════

install_proxymon() {
    check_repo
    mkdir -p /var/www/proxymon
    cp -rf modules/* /var/www/proxymon/
    
    echo -e "${YELLOW}Configuring Apache...${NC}"
    
    if [[ -f "/var/www/proxymon/tools/proxymon.conf" ]]; then
        cp -f /var/www/proxymon/tools/proxymon.conf /etc/apache2/sites-available/proxymon.conf
        echo -e "${GREEN}Proxymon virtualhost configured${NC}"
    fi
    
    if [[ -f "/var/www/proxymon/warning/warning.conf" ]]; then
        cp -f /var/www/proxymon/warning/warning.conf /etc/apache2/sites-available/warning.conf
        echo -e "${GREEN}Warning virtualhost configured${NC}"
    fi
    
    [ -f /etc/apache2/ports.conf.bak ] || cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    for port in 18080 18081; do
        if ! grep -qxF "Listen 0.0.0.0:$port" /etc/apache2/ports.conf 2>/dev/null && \
           ! grep -qxF "Listen $port" /etc/apache2/ports.conf 2>/dev/null; then
            echo "Listen 0.0.0.0:$port" >> /etc/apache2/ports.conf
            echo -e "${GREEN}Port $port added to Apache${NC}"
        fi
    done
    
    echo -e "${YELLOW}Configuring Squid Monitor...${NC}"
    create_proxymon_env

    echo -e "${YELLOW}Configuring LightSquid...${NC}"
    /var/www/proxymon/lightsquid/lightparser.pl today
    echo -e "${GREEN}Initial LightSquid report generated${NC}"

    echo -e "${YELLOW}Configuring ACL directories and files...${NC}"
    # Load env to get ACL paths defined by create_proxymon_env()
    # Verify ownership/permissions before sourcing — this file is executed
    # as root, so it must not be writable by anyone other than root.
    _env_file="/etc/proxymon/proxymon.env"
    _env_owner=$(stat -c '%U' "$_env_file" 2>/dev/null)
    _env_perms=$(stat -c '%a' "$_env_file" 2>/dev/null)
    _env_group_digit="${_env_perms: -2:1}"
    _env_other_digit="${_env_perms: -1}"
    if [ "$_env_owner" != "root" ] || [[ "$_env_group_digit" =~ [2367] ]] || [[ "$_env_other_digit" =~ [2367] ]]; then
        echo -e "${RED}ERROR: $_env_file has unsafe owner/permissions (owner=$_env_owner perms=$_env_perms).${NC}"
        echo -e "${RED}Expected owner root with no group/other write access. Refusing to source it.${NC}"
        exit 1
    fi
    source "$_env_file"

    # Create ACL directories
    mkdir -p "$ACL_PATH" "$ACL_MAC_PATH" "$ACL_SQUID_PATH" "$ACL_BANDATA_PATH"
    chmod 755 "$ACL_PATH" "$ACL_MAC_PATH" "$ACL_SQUID_PATH" "$ACL_BANDATA_PATH"
    chown root:root "$ACL_PATH" "$ACL_MAC_PATH" "$ACL_SQUID_PATH" "$ACL_BANDATA_PATH"
    echo -e "${GREEN}ACL directories created${NC}"

    # Create ACL files
    touch "$ALLOW_LIST" "$BLOCK_LIST_DAY" "$BLOCK_LIST_WEEK" "$BLOCK_LIST_MONTH"
    chmod 644 "$ALLOW_LIST" "$BLOCK_LIST_DAY" "$BLOCK_LIST_WEEK" "$BLOCK_LIST_MONTH"
    chown root:root "$ALLOW_LIST" "$BLOCK_LIST_DAY" "$BLOCK_LIST_WEEK" "$BLOCK_LIST_MONTH"
    echo -e "${GREEN}ACL files created${NC}"

    # Create LightSquid report directory if it does not exist
    mkdir -p "$REPORT_PATH"
    chmod 755 "$REPORT_PATH"
    chown www-data:www-data "$REPORT_PATH"
    echo -e "${GREEN}LightSquid report directory ready${NC}"

    echo -e "${YELLOW}Downloading ACL lists...${NC}"
    wget -q --show-progress -N https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/blocktlds.txt -O "$ACL_SQUID_PATH/blocktlds.txt"
    chmod 644 "$ACL_SQUID_PATH/blocktlds.txt"
    chown root:root "$ACL_SQUID_PATH/blocktlds.txt"
    echo -e "${GREEN}blocktlds.txt downloaded${NC}"

    wget -q --show-progress -N https://raw.githubusercontent.com/maravento/blackweb/refs/heads/master/bwupdate/lst/debugbl.txt -O "$ACL_SQUID_PATH/blockdomains.txt"
    chmod 644 "$ACL_SQUID_PATH/blockdomains.txt"
    chown root:root "$ACL_SQUID_PATH/blockdomains.txt"
    echo -e "${GREEN}blockdomains.txt downloaded${NC}"

    crontab -l 2>/dev/null | {
        grep -v "bandata.sh"
        echo "*/5 * * * * /var/www/proxymon/tools/bandata.sh >> /var/log/bandata.log 2>&1"
    } | crontab -
    echo -e "${GREEN}Squid Monitor crontab added${NC}"
    
    echo -e "${YELLOW}Configuring SARG...${NC}"
    mkdir -p /var/www/proxymon/sarg/squid-reports
    
    [ -f /etc/sarg/sarg.conf.bak ] || cp -f /etc/sarg/sarg.conf{,.bak} &>/dev/null
    sed -i 's|output_dir /var/lib/sarg|output_dir /var/www/proxymon/sarg/squid-reports|g' /etc/sarg/sarg.conf
    sed -i 's|^resolve_ip .*|resolve_ip no|g' /etc/sarg/sarg.conf
    sed -i 's|lastlog 0|lastlog 7|g' /etc/sarg/sarg.conf
    
    HOSTNAME=$(hostname)
    [ -f /etc/sarg/usertab.bak ] || cp -f /etc/sarg/usertab{,.bak} &>/dev/null

    if [ -n "$SERVER_IP" ]; then
        if ! grep -q "^$SERVER_IP" /etc/sarg/usertab; then
            echo "$SERVER_IP $HOSTNAME" >> /etc/sarg/usertab
            echo -e "${GREEN}Added $SERVER_IP $HOSTNAME to usertab${NC}"
        fi
    else
        echo -e "${RED}SERVER_IP not set in proxymon.env — skipping usertab entry${NC}"
    fi
    
    echo -e "${YELLOW}🔧 Generating Initial SARG Report...${NC}"
    timeout 30 /usr/bin/sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log > /dev/null 2>&1 || true
    echo -e "${GREEN}Initial SARG report generated${NC}"
    
    echo -e "${YELLOW}Configuring SquidAnalyzer...${NC}"
    chmod -R 755 /var/www/proxymon/squidanalyzer
    chown -R www-data:www-data /var/www/proxymon/squidanalyzer
    
    mkdir -p /var/www/proxymon/squidanalyzer/output
    rm -rf /var/www/proxymon/squidanalyzer/output/* 2>/dev/null

    cd /var/www/proxymon/squidanalyzer || exit 1
    sudo -u www-data perl -I. ./squid-analyzer -c etc/squidanalyzer.conf -d &> /dev/null
    cd - > /dev/null

    # ── Consolidated www-data crontab update (single atomic write) ──
    # All www-data cron entries (LightSquid, SARG daily/weekly, SquidAnalyzer)
    # are rewritten together to avoid leaving the crontab in a partial
    # state if the installer is interrupted between operations.
    sudo -u www-data crontab -l 2>/dev/null | {
        grep -v "lightparser.pl" \
            | grep -v "sarg.*sarg.conf.*access.log" \
            | grep -v "find.*sarg.*squid-reports" \
            | grep -v "squid-analyzer"
        echo "*/10 * * * * /var/www/proxymon/lightsquid/lightparser.pl today"
        echo "@daily /usr/bin/sarg -f /etc/sarg/sarg.conf -l /var/log/squid/access.log"
        echo '@weekly find /var/www/proxymon/sarg/squid-reports -name "2*" -mtime +30 -type d -exec rm -rf "{}" \;'
        echo '0 2 * * * cd /var/www/proxymon/squidanalyzer && perl -I. ./squid-analyzer -c etc/squidanalyzer.conf'
    } | sudo -u www-data crontab -
    echo -e "${GREEN}www-data crontab entries updated (LightSquid, SARG, SquidAnalyzer)${NC}"
    
    echo -e "${YELLOW} Updating Prefork MPM...${NC}"
    [ -f /etc/apache2/mods-available/mpm_prefork.conf.bak ] || cp -f /etc/apache2/mods-available/mpm_prefork.conf{,.bak} &>/dev/null
    sed -i \
      -e 's/^\(StartServers[[:space:]]*\)5/\110/' \
      -e 's/^\(MinSpareServers[[:space:]]*\)5/\110/' \
      -e 's/^\(MaxSpareServers[[:space:]]*\)10/\115/' \
      -e 's/^\(MaxRequestWorkers[[:space:]]*\)150/\1200/' \
      -e 's/^\(MaxConnectionsPerChild[[:space:]]*\)0/\11000/' \
    /etc/apache2/mods-available/mpm_prefork.conf

    echo -e "${YELLOW} Updating PHP...${NC}"
    [ -f /etc/php/$PHP_VERSION/apache2/php.ini.bak ] || cp -f /etc/php/$PHP_VERSION/apache2/php.ini{,.bak} &>/dev/null
    sed -i \
      -e 's/^\s*;*\s*max_execution_time\s*=.*/max_execution_time = 120/' \
      -e 's/^\s*max_input_time\s*=.*/max_input_time = 120/' \
      -e 's/^;\s*max_input_time\s*=.*/max_input_time = 120/' \
      -e 's/^\s*;*\s*memory_limit\s*=.*/memory_limit = 1024M/' \
      -e 's/^\s*;*\s*post_max_size\s*=.*/post_max_size = 64M/' \
      -e 's/^\s*;*\s*upload_max_filesize\s*=.*/upload_max_filesize = 64M/' \
      -e 's/^\s*;*\s*opcache.memory_consumption\s*=.*/opcache.memory_consumption = 256/' \
      -e 's/^\s*;*\s*realpath_cache_size\s*=.*/realpath_cache_size = 16M/' \
      -e 's/^\s*;*\s*allow_url_fopen\s*=.*/allow_url_fopen = On/' \
     /etc/php/$PHP_VERSION/apache2/php.ini
     
    # Hardening
    echo -e "${YELLOW} Updating Apache2 Security...${NC}"
    if [ -f /etc/apache2/conf-available/security.conf ]; then
        [ -f /etc/apache2/conf-available/security.conf.bak ] || cp -f /etc/apache2/conf-available/security.conf{,.bak} &>/dev/null
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
    [ -f /etc/apache2/apache2.conf.bak ] || cp -f /etc/apache2/apache2.conf{,.bak} &>/dev/null
    sed -i -E '/^[[:space:]]*#/!s/^([[:space:]]*Options[[:space:]]+)(-?Indexes[[:space:]]+)?FollowSymLinks[[:space:]]*$/\1-Indexes +FollowSymLinks/' /etc/apache2/apache2.conf
    a2enmod headers &>/dev/null
    a2enconf security &>/dev/null
     
    echo -e "${YELLOW}Configuring SquidAI...${NC}"
    mkdir -p /etc/proxymon
    if [ ! -f /etc/proxymon/.env ]; then
        cat > /etc/proxymon/.env << 'EOF'
# SquidAI — LLM Provider Configuration
# ─────────────────────────────────────────────────────────────────
# Uncomment ONE provider block and fill in your credentials.
# Leave LLM_MODEL empty if the model is already part of the URL.
# LLM_API_KEY can be left empty for local providers (Ollama, LM Studio).
#
# LLM_RESPONSE_FORMAT tells the worker how to read the response:
#   openai  → choices[0].message.content  (most cloud providers)
#   ollama  → message.content             (Ollama)
#   gemini  → passthrough, no transform   (Google Gemini)
# ─────────────────────────────────────────────────────────────────

# ── Active provider (uncomment one block below) ──────────────────
LLM_URL=
LLM_API_KEY=
LLM_MODEL=
LLM_RESPONSE_FORMAT=openai

# ─────────────────────────────────────────────────────────────────
# PROVIDER EXAMPLES — copy the values above and replace
# ─────────────────────────────────────────────────────────────────

# Cloudflare Workers AI (model goes in the URL, no LLM_MODEL needed)
# LLM_URL=https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/ai/run/@cf/meta/llama-3.1-8b-instruct-fast
# LLM_API_KEY=your_token
# LLM_RESPONSE_FORMAT=openai

# OpenAI
# LLM_URL=https://api.openai.com/v1/chat/completions
# LLM_API_KEY=sk-...
# LLM_MODEL=gpt-4o-mini
# LLM_RESPONSE_FORMAT=openai

# Groq (fast inference, free tier available)
# LLM_URL=https://api.groq.com/openai/v1/chat/completions
# LLM_API_KEY=gsk_...
# LLM_MODEL=llama-3.1-8b-instant
# LLM_RESPONSE_FORMAT=openai

# OpenRouter (access to many models, free tier available)
# LLM_URL=https://openrouter.ai/api/v1/chat/completions
# LLM_API_KEY=sk-or-...
# LLM_MODEL=mistralai/mistral-7b-instruct
# LLM_RESPONSE_FORMAT=openai

# Together AI
# LLM_URL=https://api.together.xyz/v1/chat/completions
# LLM_API_KEY=your_key
# LLM_MODEL=meta-llama/Llama-3-8b-chat-hf
# LLM_RESPONSE_FORMAT=openai

# Ollama (local, no API key required)
# LLM_URL=http://localhost:11434/api/chat
# LLM_API_KEY=
# LLM_MODEL=llama3.1
# LLM_RESPONSE_FORMAT=ollama

# LM Studio (local, OpenAI-compatible)
# LLM_URL=http://localhost:1234/v1/chat/completions
# LLM_API_KEY=lm-studio
# LLM_MODEL=
# LLM_RESPONSE_FORMAT=openai

# Google Gemini
# LLM_URL=https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=YOUR_KEY
# LLM_API_KEY=
# LLM_MODEL=
# LLM_RESPONSE_FORMAT=gemini
EOF
    fi
    chmod 640 /etc/proxymon/.env
    chown root:www-data /etc/proxymon/.env
    chmod 750 /etc/proxymon
    chown root:www-data /etc/proxymon
    echo -e "${GREEN}SquidAI config directory created: /etc/proxymon/${NC}"
    echo -e "${YELLOW}Edit /etc/proxymon/.env and set your LLM credentials${NC}"

    echo -e "${YELLOW} Setting Permissions...${NC}"
    find /var/www/proxymon -type d -exec chmod 755 {} +
    find /var/www/proxymon -type f -exec chmod 644 {} +
    find /var/www/proxymon -type f -name "*.cgi" -exec chmod +x {} +
    chmod +x /var/www/proxymon/tools/bandata.sh
    chmod +x /var/www/proxymon/lightsquid/lightparser.pl
    chown -R www-data:www-data /var/www/proxymon
    if getent group proxy >/dev/null; then
        usermod -aG proxy www-data
    else
        echo -e "${RED}ERROR: group 'proxy' not found (expected to be created by the squid package).${NC}"
        echo -e "${RED}Ensure squid is installed before running this step.${NC}"
        exit 1
    fi
    chown root:root /etc/squid/squid.conf
    chmod 644 /etc/squid/squid.conf
    
    echo -e "${YELLOW} Setting Logs...${NC}"
    touch /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log
    chown root:adm /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log
    chmod 640 /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log

    shopt -s nullglob
    squid_logs=(/var/log/squid/*.log)
    if [ ${#squid_logs[@]} -gt 0 ]; then
        chown proxy:proxy "${squid_logs[@]}"
        chmod 640 "${squid_logs[@]}"
    else
        echo -e "${YELLOW}No /var/log/squid/*.log files found yet — skipping permissions${NC}"
    fi
    shopt -u nullglob
    
    echo -e "${YELLOW} Enabling Apache Modules...${NC}"
    a2dismod mpm_event 2>/dev/null || true
    # mod_cgid requires a threaded MPM (worker/event) and is incompatible
    # with mpm_prefork enabled below. Use mod_cgi instead.
    a2dismod cgid 2>/dev/null || true

    for mod in mpm_prefork "php$PHP_VERSION" cgi rewrite; do
        if a2enmod "$mod" 2>/dev/null; then
            continue
        fi
        # Fallback for systems where the module is registered as plain "php"
        if [[ "$mod" == "php$PHP_VERSION" ]] && a2enmod php 2>/dev/null; then
            continue
        fi
        echo -e "${RED}ERROR: failed to enable Apache module '$mod'. Is it installed?${NC}"
        exit 1
    done
    
    echo -e "${YELLOW} Enabling Apache Sites...${NC}"
    a2ensite proxymon.conf || { echo -e "${RED}Failed to enable proxymon.conf${NC}"; exit 1; }
    a2ensite warning.conf || { echo -e "${RED}Failed to enable warning.conf${NC}"; exit 1; }
    
    echo -e "${GREEN} Restarting Cron...${NC}"
    systemctl restart cron
        
    echo -e "${YELLOW} Restarting Apache2...${NC}"
    systemctl daemon-reload
    if ! apachectl -t -D DUMP_INCLUDES -S &>/dev/null; then
        echo -e "${RED}Apache configuration test failed. Aborting before restart.${NC}"
        echo -e "${RED}Run 'apachectl -t' to see the error and fix the configuration manually.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Apache configuration OK${NC}"
    systemctl restart apache2

    echo -e "${GREEN} Check Active Apache sites:${NC}"
    a2query -s
    
    echo -e "${GREEN}Proxy Monitor installed successfully${NC}"
    echo -e "${GREEN}Access Proxy Monitor: http://localhost:18080${NC}"
    echo -e "${GREEN}Access Warning Portal: http://localhost:18081${NC}"
}

# ════════════════════════════════════════════════════════════════
# UNINSTALL FUNCTION
# ════════════════════════════════════════════════════════════════

uninstall_proxymon() {
    echo -e "${YELLOW} Uninstalling Proxy Monitor...${NC}"
    
    if [[ ! -d "/var/www/proxymon" ]]; then
        if ! (sudo crontab -l 2>/dev/null | grep -q "bandata.sh") && \
           ! (sudo -u www-data crontab -l 2>/dev/null | grep -q "lightparser.pl\|sarg\|squid-analyzer") && \
           [[ ! -d "/etc/proxymon" ]]; then
            echo -e "${YELLOW} Proxy Monitor is not installed${NC}"
            return 0
        fi
    fi
    
    # ── Consolidated www-data crontab cleanup (single atomic write) ──
    if sudo -u www-data crontab -l 2>/dev/null \
        | grep -v "lightparser.pl" \
        | grep -v "sarg.*sarg.conf.*access.log" \
        | grep -v "find.*sarg.*squid-reports" \
        | grep -v "squid-analyzer" \
        | sudo -u www-data crontab - 2>/dev/null; then
        echo -e "${GREEN}LightSquid, SARG and SquidAnalyzer crontab entries removed${NC}"
    else
        echo -e "${YELLOW}WARNING: failed to update www-data crontab — entries may remain${NC}"
    fi

    if crontab -l 2>/dev/null | grep -v "bandata.sh" | crontab - 2>/dev/null; then
        echo -e "${GREEN}Squid Monitor crontab removed${NC}"
    else
        echo -e "${YELLOW}WARNING: failed to update root crontab — bandata.sh entry may remain${NC}"
    fi

    if [[ -f "/etc/sarg/sarg.conf.bak" ]]; then
        mv -f /etc/sarg/sarg.conf.bak /etc/sarg/sarg.conf
        echo -e "${GREEN}SARG configuration restored${NC}"
    fi
    
    if [[ -f "/etc/sarg/usertab.bak" ]]; then
        mv -f /etc/sarg/usertab.bak /etc/sarg/usertab
        echo -e "${GREEN}SARG usertab restored${NC}"
    fi

    if [[ -f "/etc/apache2/mods-available/mpm_prefork.conf.bak" ]]; then
        mv -f /etc/apache2/mods-available/mpm_prefork.conf.bak /etc/apache2/mods-available/mpm_prefork.conf
        echo -e "${GREEN}mpm_prefork configuration restored${NC}"
    fi

    PHP_VERSION=""
    if command -v php >/dev/null 2>&1; then
        PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || true)
    fi
    if [[ -n "$PHP_VERSION" && -f "/etc/php/$PHP_VERSION/apache2/php.ini.bak" ]]; then
        mv -f "/etc/php/$PHP_VERSION/apache2/php.ini.bak" "/etc/php/$PHP_VERSION/apache2/php.ini"
        echo -e "${GREEN}php.ini restored${NC}"
    fi

    if [[ -f "/etc/apache2/conf-available/security.conf.bak" ]]; then
        mv -f /etc/apache2/conf-available/security.conf.bak /etc/apache2/conf-available/security.conf
        echo -e "${GREEN}security.conf restored${NC}"
    fi

    if [[ -f "/etc/apache2/apache2.conf.bak" ]]; then
        mv -f /etc/apache2/apache2.conf.bak /etc/apache2/apache2.conf
        echo -e "${GREEN}apache2.conf restored${NC}"
    fi
        
    if [[ -f "/etc/apache2/sites-available/proxymon.conf" ]]; then
        a2dissite proxymon.conf 2>/dev/null || true
        rm -f /etc/apache2/sites-available/proxymon.conf
        echo -e "${GREEN}Proxymon site disabled${NC}"
    fi
    
    if [[ -f "/etc/apache2/sites-available/warning.conf" ]]; then
        a2dissite warning.conf 2>/dev/null || true
        rm -f /etc/apache2/sites-available/warning.conf
        echo -e "${GREEN}Warning site disabled${NC}"
    fi
    
    if [[ -d "/var/www/proxymon" ]]; then
        rm -rf /var/www/proxymon
        echo -e "${GREEN}Installation directory removed${NC}"
    fi

    if [[ -d "/etc/proxymon" ]]; then
        read -p "Remove /etc/proxymon/ (contains LLM credentials)? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /etc/proxymon
            echo -e "${GREEN}SquidAI config directory removed${NC}"
        else
            echo -e "${YELLOW} /etc/proxymon kept — remove manually if needed${NC}"
        fi
    fi

    if [[ -d "/etc/acl" ]]; then
        read -p "Remove /etc/acl/ (contains Bandata ACLs, allowlists and MAC registrations)? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /etc/acl
            echo -e "${GREEN}/etc/acl removed${NC}"
        else
            echo -e "${YELLOW} /etc/acl kept — remove manually if needed${NC}"
        fi
    fi
    
    cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null
    sed -i '/Listen 0.0.0.0:18080/d' /etc/apache2/ports.conf
    sed -i '/Listen 18080/d' /etc/apache2/ports.conf
    echo -e "${GREEN}Port 18080 removed from Apache${NC}"
    
    sed -i '/Listen 0.0.0.0:18081/d' /etc/apache2/ports.conf
    sed -i '/Listen 18081/d' /etc/apache2/ports.conf
    echo -e "${GREEN}Port 18081 removed from Apache${NC}"
    
    rm -f /var/log/apache2/{warning_access,warning_error,proxymon_access,proxymon_error}.log*
    echo -e "${GREEN}Proxymon log files removed${NC}"
    
    systemctl restart cron
    systemctl daemon-reload
    systemctl restart apache2
    
    echo -e "${GREEN} Remaining Apache sites:${NC}"
    a2query -s
    
    echo -e "${GREEN}Proxy Monitor uninstalled successfully${NC}"
}

# ════════════════════════════════════════════════════════════════
# MAIN
# ════════════════════════════════════════════════════════════════

case "${1:-}" in
    install)
        run_initial_checks
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
                    run_initial_checks
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
