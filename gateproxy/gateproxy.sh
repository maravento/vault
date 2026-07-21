#!/bin/bash
# maravento.com
#
################################################################################
#
# Gateproxy
# A simple proxy/firewall server
#
################################################################################

set -Eeuo pipefail

log_file="$(dirname "$(realpath "$0")")/gateproxy.log"
: > "$log_file" 2>/dev/null || true
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}
trap 'log "ERROR: command failed at line $LINENO: $BASH_COMMAND"' ERR

## root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    log "Script $(basename "$0") is already running"
    exit 1
fi

log "gateproxy start..."
printf "\n"

# checking conflicting pre-installed packages
check_conflicts() {
    local role="$1"; shift
    local found=()
    for pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            found+=("$pkg")
        fi
    done
    if [ "${#found[@]}" -gt 0 ]; then
        log "ERROR: Conflicting $role package(s) already installed: ${found[*]}"
        log "ERROR: gateproxy installs its own $role stack. Remove them first: apt purge -y ${found[*]}"
        exit 1
    fi
}

retry_cmd() {
    local max_attempts=10
    local attempt=1
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            log "ERROR: command failed after $max_attempts attempts: $*"
            exit 1
        fi
        log "WARNING: command failed (attempt $attempt/$max_attempts), retrying in 10s: $*"
        case "$1" in
            nala|apt|apt-get)
                rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true
                ;;
        esac
        attempt=$((attempt + 1))
        sleep 10
    done
}

log "Checking for conflicting pre-installed packages..."
check_conflicts "DHCP server" isc-dhcp-server dnsmasq
check_conflicts "proxy"       squid squid3 tinyproxy privoxy 3proxy
check_conflicts "web server"  nginx lighttpd caddy
check_conflicts "syslog"      syslog-ng
check_conflicts "firewall"    firewalld
check_conflicts "IDS"         snort
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
    log "ERROR: ufw is active and will conflict with gateproxy's iptables rules."
    log "ERROR: Disable it first: ufw disable"
    exit 1
fi
log "No conflicting packages found: OK"

# LOCAL USER detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    log "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
log "Using local user: $local_user"

### CHECK SO & DESKTOP
log "Check System..."
# Get the current desktop environment in lowercase
DESKTOP_ENV=$(echo "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')
# Get the Ubuntu version number (e.g., 22.04, 24.04)
UBUNTU_VERSION=$(lsb_release -rs)
# Get the distribution ID (e.g., Ubuntu)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
log "Desktop: $DESKTOP_ENV"
log "OS: $UBUNTU_ID $UBUNTU_VERSION"

if [ "$UBUNTU_ID" != "ubuntu" ]; then
    log "ERROR: Unsupported OS $UBUNTU_ID (Ubuntu only)"
    exit 1
fi
if [ "$(printf '%s\n' "$UBUNTU_VERSION" "24.04" | sort -V | head -n1)" != "24.04" ]; then
    log "ERROR: Ubuntu $UBUNTU_VERSION below min supported 24.04"
    exit 1
elif [ "$UBUNTU_VERSION" != "24.04" ]; then
    log "WARNING: Ubuntu $UBUNTU_VERSION untested (min: 24.04)"
fi

log "Clearing apt package cache..."
apt-get clean &>/dev/null || true
rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true

### VARIABLES
SCRIPT_PATH="$(realpath "$0")"
gp_path=$(pwd)/gateproxy
zone_path=/etc/zones
mkdir -p "$zone_path" &>/dev/null
acl_path=/etc/acl
mkdir -p "$acl_path" &>/dev/null
scr_path=/etc/scr
mkdir -p "$scr_path" &>/dev/null

# PPA
file="/etc/apt/sources.list.d/ubuntu.sources"
required_components=("main" "restricted" "universe" "multiverse")
changed=0

if [ -f "$file" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^Components: ]]; then
            read -ra found <<< "${line#Components: }"

            for required in "${required_components[@]}"; do
                if ! printf '%s\n' "${found[@]}" | grep -qx "$required"; then
                    log "Missing '$required' in: $line"
                    sed -i "s|^$line|Components: ${required_components[*]}|" "$file"
                    changed=1
                    break
                fi
            done

            if [[ $changed -eq 0 ]]; then
                log "All components present in: $line"
            fi
        fi
    done < <(grep "^Components:" "$file")

    if [[ $changed -eq 1 ]]; then
        log "Updating package list. Wait..."
        retry_cmd apt update > /dev/null 2>&1
    else
        log "No changes made. No update needed."
    fi
else
    log "NOTE: $file not found, skipping component check"
fi

# DEPENDENCIES
pkgs='nala curl software-properties-common apt-transport-https aptitude net-tools plocate git git-gui gitk gist expect tcl-expect libnotify-bin gcc make perl bzip2 p7zip-full p7zip-rar rar unrar unzip zip unace cabextract arj zlib1g-dev tzdata tar coreutils dconf-editor python-is-python3'
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done
if [ -n "$unavailable" ]; then
    log "Missing dependencies not found in APT:"
    for u in $unavailable; do log "   - $u"; done
    log "Please install them manually or enable the required repositories."
    exit 1
fi
if [ -n "$missing" ]; then
    log "Waiting for apt/dpkg to finish..."
    apt_wait=0
    apt_wait_limit=60
    while pgrep -x apt > /dev/null 2>&1 || pgrep -x apt-get > /dev/null 2>&1 || pgrep -x dpkg > /dev/null 2>&1; do
        if [ "$apt_wait" -ge "$apt_wait_limit" ]; then
            log "ERROR: apt/dpkg did not release after $((apt_wait_limit * 5)) seconds"
            exit 1
        fi
        log "Waiting for apt/dpkg to finish... ($apt_wait/$apt_wait_limit)"
        sleep 5
        apt_wait=$((apt_wait + 1))
    done
    rm -f /var/lib/apt/lists/lock
    rm -f /var/cache/apt/archives/lock
    rm -f /var/lib/dpkg/lock
    rm -f /var/lib/dpkg/lock-frontend
    rm -rf /var/lib/apt/lists/*
    dpkg --configure -a
    log "Installing: $missing"
    apt-get -qq update
    retry_cmd apt-get -y install $missing
else
    log "Dependencies OK"
fi

### BASIC
# time
apt purge -y ntp ntpdate chrony &>/dev/null || true
retry_cmd apt install -y --reinstall systemd-timesyncd &>/dev/null
hwclock -w &>/dev/null || log "WARNING: hwclock -w failed (no RTC available?)"
systemctl enable --now systemd-timesyncd &>/dev/null || log "WARNING: systemd-timesyncd failed to start"
timedatectl set-ntp true &>/dev/null || log "WARNING: timedatectl set-ntp failed"
timedatectl status | grep -E "NTP|synchroniz" || true
# Performance Co-Pilot (PCP)
systemctl disable --now pmcd pmproxy pmlogger &>/dev/null || log "WARNING: PCP failed to disable"
# install | remove
retry_cmd apt -qq install -y apt-file
retry_cmd apt-file update
apt -qq remove -y zsys &>/dev/null || true
ubuntu-drivers autoinstall &>/dev/null || true
# configure
pro config set apt_news=false || true
DISK=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}')
[ -n "$DISK" ] && hdparm -W "$DISK" &>/dev/null || true
ifconfig lo 127.0.0.1
#systemctl disable avahi-daemon cups-browser &> /dev/null # optional
# cron
cp /etc/crontab{,.bak} &>/dev/null || true
cp /etc/apt/sources.list{,.bak} &>/dev/null || true

### CLEAN | UPDATE | FIX
echo -e "\n"
function upgrade() {
    log "Update and Clean. Wait..."
    retry_cmd nala upgrade --purge -y
    retry_cmd aptitude safe-upgrade -y
    dpkg --configure -a
    retry_cmd nala install --fix-broken -y
    systemctl daemon-reload
    sync
    updatedb
    update-desktop-database
}

upgrade

### PACKAGES
clear
echo -e "\n"
log "Check Dependencies..."

### GATEPROXY GIT
echo -e "\n"
[ -d "$gp_path" ] && rm -rf "$gp_path"
retry_cmd wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
retry_cmd python3 gitfolder.py https://github.com/maravento/vault/gateproxy

### CONFIG
echo -e "\n"
hostnamectl set-hostname "$HOSTNAME"
find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:gateproxy:$HOSTNAME:g" "{}"
# changing name user account in config files
find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:your_user:$local_user:g" "{}"

# public interface
function public_interface() {
    while true; do
        read -r -p "Enter Public Network Interface (Internet) (e.g. enpXsX): " ETH0
        if [[ "$ETH0" =~ ^[a-z][a-z0-9]{1,13}[0-9]+$ ]]; then
            find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:eth0:$ETH0:g" "{}"
            break
        else
            log "Invalid interface name. Try again."
        fi
    done
}

# local interface
function local_interface() {
    while true; do
        read -r -p "Enter Local Network Interface (e.g. enpXsX): " ETH1
        if [[ "$ETH1" =~ ^[a-z][a-z0-9]{1,13}[0-9]+$ ]]; then
            find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:eth1:$ETH1:g" "{}"
            export LAN_INTERFACE="$ETH1"
            break
        else
            log "Invalid interface name. Try again."
        fi
    done
}

function is_interfaces() {
    if ip link show eth0 &>/dev/null; then
        log "Older NIC-Ethernet Format Detected"
        log "Aborted installation. Check the Minimum Requirements"
        rm -rf "$gp_path" &>/dev/null
        exit
    else
        log "Check Net Interfaces: OK"
        log "List of Network Interfaces Detected:"
        ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}' | sed 's_: _ _'
        public_interface
        local_interface
        log "OK"
    fi
}

NETWORK_ENV="/etc/gateproxy/network.env"
mkdir -p /etc/gateproxy &>/dev/null
REUSE_NETWORK=false
if [ -f "$NETWORK_ENV" ]; then
    while true; do
        read -r -p "Reuse network data from a previous run? (y/n): " reuse_ans
        case "$reuse_ans" in
            [Yy]*) REUSE_NETWORK=true; break ;;
            [Nn]*) REUSE_NETWORK=false; break ;;
            *) log "Answer: YES (y) or NO (n)" ;;
        esac
    done
fi

if [ "$REUSE_NETWORK" = true ]; then
    source "$NETWORK_ENV"
    export LAN_INTERFACE
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:eth0:$ETH0:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:eth1:$LAN_INTERFACE:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.10:$serverip:g" "{}"
    find "$gp_path/acl" -type f -name "mac-*" -exec sed -i "s:192.168.0\.:$(echo "$serverip" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" {} \;
    find "$gp_path/acl/acl_dhcp" -type f -name "blockdhcp*" -exec sed -i "s:192.168.0\.:$(echo "$serverip" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" {} \;
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.0:$LOCALNETNEW:g" "{}"
    sed -i "s:192\.168\.0\.\*:$(echo "$LOCALNETNEW" | awk -F '.' '{OFS="."; $4="*"; print $0}'):g" "$gp_path/conf/server/wpad.pac"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.255:$BROADCASTNEW:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:255.255.255.0:$MASKNEW1:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:/24:/$MASKNEW2:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.8.8:$DNSNEW1:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.4.4:$DNSNEW2:g" "{}"
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:3128:$PORTNEW:g" "{}"
    log "Reusing saved data: $LAN_INTERFACE / $serverip"
else

is_interfaces

### START
clear
echo -e "\n"
log "    Welcome to GateProxy"
echo -e "\n"
log "    Minimum Requirements:"
log "    OS:       Ubuntu 24.04.x"
log "    CPU:      4+ cores (>= 3.0 GHz)"
log "    NIC:      2 (WAN & LAN)"
log "    RAM:      4 GB cache_mem (12+ GB RAM recommended)"
log "    Storage:  100 GB SSD for cache_dir rock"
echo -e "\n"
log "    Press ENTER to start or CTRL+C to abort"
echo -e "\n"
read -r RES
clear

echo -e "\n"
while true; do
    read -r -p "Do you want to change? Server IP 192.168.0.10? (y/n): " change_ip
    case "$change_ip" in
        [Yy]*)
            while true; do
                read -r -p "Enter IP (e.g. 192.168.0.10): " input_ip
                serveripNEW=$(echo "$input_ip" | grep -E '^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$')
                if [ "$serveripNEW" ]; then
                    serverip="$serveripNEW"

                    find "$gp_path/conf" -type f -print0 | while IFS= read -r -d '' file; do
                        sed -i "s:192.168.0.10:$serveripNEW:g" "$file"
                    done

                    find "$gp_path/acl" -type f -name "mac-*" -exec sed -i "s:192.168.0\.:$(echo "$serveripNEW" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" {} \;

                    find "$gp_path/acl/acl_dhcp" -type f -name "blockdhcp*" -exec sed -i "s:192.168.0\.:$(echo "$serveripNEW" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" {} \;

                    log "You have entered IP $serverip :OK"
                    break
                else
                    log "You have entered IP incorrect"
                fi
            done
            break
            ;;
        [Nn]*)
            serverip="192.168.0.10"
            log "Default IP: $serverip"
            break
            ;;
        *)
            log "Answer: YES (y) or NO (n)"
            ;;
    esac
done

LOCALNETNEW="$(echo "$serverip" | awk -F '.' '{OFS="."; $4="0"; print $0}')"
if [ "$LOCALNETNEW" != "192.168.0.0" ]; then
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.0:$LOCALNETNEW:g" "{}"
    sed -i "s:192\.168\.0\.\*:$(echo "$LOCALNETNEW" | awk -F '.' '{OFS="."; $4="*"; print $0}'):g" "$gp_path/conf/server/wpad.pac"
fi
log "Localnet: $LOCALNETNEW (from Server IP)"

BROADCASTNEW="$(echo "$serverip" | awk -F '.' '{OFS="."; $4="255"; print $0}')"
if [ "$BROADCASTNEW" != "192.168.0.255" ]; then
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.255:$BROADCASTNEW:g" "{}"
fi
log "Broadcast: $BROADCASTNEW (from Server IP)"

### PARAMETERS
is_ask() {
    inquiry="$1"
    iresponse="$2"
    funcion="$3"
    while true; do
        read -r -p "$inquiry: " answer
        case "$answer" in
        [Yy]*)
            # execute command yes
            while true; do
                if $funcion; then
                    break
                else
                    log "$iresponse"
                fi
            done
            break
            ;;
        [Nn]*)
            # execute command no
            log "NO"
            break
            ;;
        *)
            echo
            log "Answer: YES (y) or NO (n)"
            ;;
        esac
    done
}

# netmask
MASKNEW1="255.255.255.0"
MASKNEW2="24"

# netmask
function is_mask1() {
    read -r -p "Enter Netmask (e.g. 255.255.255.0): " MASK1
    MASKNEW1=$(echo "$MASK1" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$MASKNEW1" ]; then
        find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:255.255.255.0:$MASKNEW1:g" "{}"
        log "You have entered Netmask $MASK1 :OK"
        return 0
    else
        MASKNEW1="255.255.255.0"
        return 1
    fi
}

function is_mask2() {
    read -r -p "Enter Subnet-Mask (e.g. 24): " MASK2
    MASKNEW2=$(echo "$MASK2" | grep -E '^([1-9]|[12][0-9]|3[0-2])$')
    if [ "$MASKNEW2" ]; then
        find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:/24:/$MASKNEW2:g" "{}"
        log "You have entered Subnet-Mask $MASK2 :OK"
        return 0
    else
        return 1
    fi
}

# dns primary
function is_dns1() {
    read -r -p "Enter DNS1 (e.g. 8.8.8.8): " DNS1
    DNSNEW1=$(echo "$DNS1" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$DNSNEW1" ]; then
        find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.8.8:$DNSNEW1:g" "{}"
        log "You have entered DNS1 $DNS1 :OK"
        return 0
    else
        return 1
    fi
}

# dns secondary
function is_dns2() {
    read -r -p "Enter DNS2 (e.g. 8.8.4.4): " DNS2
    DNSNEW2=$(echo "$DNS2" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')
    if [ "$DNSNEW2" ]; then
        find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:8.8.4.4:$DNSNEW2:g" "{}"
        log "You have entered DNS2 $DNS2 :OK"
        return 0
    else
        return 1
    fi
}

# squid port
function is_port() {
    read -r -p "Enter Proxy Port (e.g. 3128): " PORT
    PORTNEW=$(echo "$PORT" | grep -E '^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$')
    if [ "$PORTNEW" ]; then
        find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:3128:$PORTNEW:g" "{}"
        log "You have entered Proxy Port $PORT :OK"
        return 0
    else
        return 1
    fi
}

echo -e "\n"
while true; do
    read -r -p "Server settings:
Mask 255.255.255.0, Network /24, DNS 8.8.8.8 8.8.4.4, Proxy Port 3128
    Do you want to change? (y/n)" answer
    case "$answer" in
    [Yy]*)
        # execute command yes
        is_ask "Do you want to change? Mask 255.255.255.0? (y/n)" "You have entered Mask incorrect" is_mask1
        is_ask "Do you want to change? Sub-Mask /24? (y/n)" "You have entered Sub-Mask incorrect" is_mask2
        is_ask "Do you want to change? DNS1 8.8.8.8? (y/n)" "You have entered DNS1 incorrect" is_dns1
        is_ask "Do you want to change? DNS2 8.8.4.4? (y/n)" "You have entered DNS2 incorrect" is_dns2
        is_ask "Do you want to change? Proxy Port Default 3128? (y/n)" "You have entered Proxy Port incorrect" is_port
        log "OK"
        break
        ;;
    [Nn]*)
        # execute command no
        log "NO"
        break
        ;;
    *)
        echo
        log "Answer: YES (y) or NO (n)"
        ;;
    esac
done

cat > "$NETWORK_ENV" <<EOF
ETH0="$ETH0"
LAN_INTERFACE="$LAN_INTERFACE"
serverip="$serverip"
LOCALNETNEW="$LOCALNETNEW"
BROADCASTNEW="$BROADCASTNEW"
MASKNEW1="$MASKNEW1"
MASKNEW2="$MASKNEW2"
DNSNEW1="${DNSNEW1:-8.8.8.8}"
DNSNEW2="${DNSNEW2:-8.8.4.4}"
PORTNEW="${PORTNEW:-3128}"
EOF
chown root:root "$NETWORK_ENV"
chmod 600 "$NETWORK_ENV"

fi

### NETPLAN
if [ "$REUSE_NETWORK" = true ] && ip -4 addr show "$LAN_INTERFACE" 2>/dev/null | grep -qF "inet $serverip/"; then
    log "Network already configured: $LAN_INTERFACE has $serverip"
else

echo -e "\n"
log "Applying network configuration..."
find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -exec mv -- {} {}.bak \; 2>/dev/null
mkdir -p /etc/cloud/cloud.cfg.d
echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
cp -f "$gp_path/conf/server/00-networkd.yaml" /etc/netplan/00-networkd.yaml
chown root:root /etc/netplan/00-networkd.yaml
chmod 600 /etc/netplan/00-networkd.yaml
if ! netplan generate 2>&1 | tee -a "$log_file"; then
    log "ERROR: netplan generate failed"
    exit 1
fi
if ! netplan apply 2>&1 | tee -a "$log_file"; then
    log "ERROR: netplan apply failed"
    exit 1
fi

log "Waiting for $LAN_INTERFACE to come up with $serverip..."
NETPLAN_WAIT=0
NETPLAN_WAIT_LIMIT=30
until ip -4 addr show "$LAN_INTERFACE" 2>/dev/null | grep -qF "inet $serverip/"; do
    if [ "$NETPLAN_WAIT" -ge "$NETPLAN_WAIT_LIMIT" ]; then
        log "ERROR: $LAN_INTERFACE did not come up with an IP."
        log "Wait a few minutes and run: sudo bash gateproxy.sh"
        exit 1
    fi
    sleep 2
    NETPLAN_WAIT=$((NETPLAN_WAIT + 1))
done
log "Network OK: $LAN_INTERFACE has $serverip"

fi

### ESSENTIAL
clear
echo -e "\n"
log "Essential Packages..."
# DISK & STORAGE MANAGEMENT
retry_cmd nala install -y gparted gnome-disk-utility qdirstat baobab
retry_cmd nala install -y --no-install-recommends smartmontools gsmartcontrol

# FILE SYSTEMS SUPPORT
retry_cmd nala install -y nfs-common ntfs-3g reiserfsprogs reiser4progs xfsprogs \
                jfsutils dosfstools e2fsprogs hfsprogs hfsutils hfsplus \
                mtools nilfs-tools f2fs-tools exfat-fuse

# FUSE & VIRTUAL FILE SYSTEMS
retry_cmd nala install -y libfuse2t64 gvfs-fuse bindfs sshfs jmtpfs

# VOLUME & QUOTA MANAGEMENT
retry_cmd nala install -y lvm2 quota attr
retry_cmd nala install -y udisks2 udisks2-btrfs udisks2-lvm2

# SYSTEM UTILITIES & MONITORING
retry_cmd nala install -y trash-cli pm-utils cpu-x btop htop lsof \
                inotify-tools dmidecode idle3 wmctrl pv tree moreutils \
                preload deborphan debconf-utils mokutil util-linux \
                linux-tools-common apparmor-utils

# PACKAGE MANAGEMENT TOOLS
retry_cmd nala install -y dpkg ppa-purge apt-utils gdebi synaptic

# TEXT & FILE UTILITIES
retry_cmd nala install -y gawk rename renameutils sharutils dos2unix colordiff \
                ripgrep yamllint

# LOGGING & SYSTEM SERVICES
retry_cmd nala install -y finger logrotate

# DRIVERS & KERNEL MODULES
retry_cmd nala install -y linux-firmware linux-headers-$(uname -r) module-assistant

# DEVELOPMENT: COMPILERS & BUILD TOOLS
retry_cmd nala install -y build-essential clang autoconf autoconf-archive autogen \
                automake dh-autoreconf pkg-config

# DEVELOPMENT: LIBRARIES & HEADERS
retry_cmd nala install -y uuid-dev libmnl-dev libssl-dev libffi-dev libpam0g-dev \
                libpcap-dev libasound2-dev libglib2.0-dev libudisks2-dev \
                liblvm2-dev python3-dev gtkhash

# PROGRAMMING: PYTHON
retry_cmd nala install -y python3-pip python3-venv python3-psutil

# PROGRAMMING: RUBY
retry_cmd nala install -y rubygems-integration rake ruby ruby-did-you-mean ruby-json \
                ruby-minitest ruby-net-telnet ruby-power-assert ruby-test-unit

# PROGRAMMING: JAVASCRIPT & WEB
retry_cmd nala install -y javascript-common libjs-jquery xsltproc

# NETWORK & CONNECTIVITY
retry_cmd nala install -y wget bind9-dnsutils conntrack i2c-tools wsdd ipset

# GEOLOCATION DATABASES
retry_cmd nala install -y geoip-database

# GRAPHICS & DISPLAY
# if there any problems, install the package: libegl-mesa0
retry_cmd nala install -y mesa-utils libfontconfig1

# RUNTIME LIBRARIES
retry_cmd nala install -y libuser gir1.2-gtop-2.0
    
# MAIL
service sendmail stop &>/dev/null || true
update-rc.d -f sendmail remove &>/dev/null || true
DEBIAN_FRONTEND=noninteractive retry_cmd nala install -y postfix
retry_cmd nala install -y mailutils

# FONTS
retry_cmd nala install -y fonts-lato fonts-liberation fonts-dejavu
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
retry_cmd nala install -y ttf-mscorefonts-installer fontconfig
fc-cache -f
    
log "OK"
sleep 1

upgrade

### SETUP ###
echo -e "\n"
log "Gateproxy Packages..."
if grep -q "^127\.0\.1\.1" /etc/hosts; then
    sed -i "/^127\.0\.1\.1/ r $gp_path/conf/server/hosts.txt" /etc/hosts
else
    log "NOTE: /etc/hosts has no 127.0.1.1 line, appending hostname entry instead"
    cat "$gp_path/conf/server/hosts.txt" >> /etc/hosts
fi
sed -i '/^\s*\(fe00::\|ff00::\|ff02::\)/ s/^/#/' /etc/hosts
grep -q "ipv6.msftncsi.com" /etc/hosts || echo "$serverip ipv6.msftncsi.com ipv6.msftconnecttest.com" | tee -a /etc/hosts >/dev/null

# ACLs SECTION
acl_mac_path="$acl_path/acl_mac"
acl_dhcp_path="$acl_path/acl_dhcp"
acl_squid_path="$acl_path/acl_squid"
acl_ipt_path="$acl_path/acl_ipt"
cp -rf "$gp_path/acl/." "$acl_path/"
# DHCP ACL files
chmod 600 "$acl_mac_path"/mac-*.txt "$acl_dhcp_path/blockdhcp.txt"
chown root:root "$acl_mac_path"/mac-*.txt "$acl_dhcp_path/blockdhcp.txt"
# Squid ACL files
chmod 644 "$acl_squid_path"/*.txt
chown root:root "$acl_squid_path"/*.txt
# IPTables ACL files
chmod 644 "$acl_ipt_path"/*.txt
chown root:root "$acl_ipt_path"/*.txt

# PHP
retry_cmd nala install -y php libapache2-mod-php php-cli php-curl

# Detect PHP version
if command -v php &>/dev/null; then
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null)
    log "PHP version detected: $PHP_VERSION"
else
    log "Error: PHP not installed"
    exit 1
fi

# Ensure php.ini exists for Apache
if [ ! -f /etc/php/$PHP_VERSION/apache2/php.ini ]; then
    if [ -f /etc/php/$PHP_VERSION/cli/php.ini ]; then
        mkdir -p /etc/php/$PHP_VERSION/apache2
        cp /etc/php/$PHP_VERSION/cli/php.ini /etc/php/$PHP_VERSION/apache2/php.ini
        log "php.ini copied to /etc/php/$PHP_VERSION/apache2/"
    else
        log "Error: php.ini not found"
        exit 1
    fi
fi

cp -f /etc/php/$PHP_VERSION/apache2/php.ini{,.bak} &>/dev/null || true
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
  
# HTTP SERVER SECTION
# apache2
retry_cmd nala install -y apache2 apache2-doc apache2-utils apache2-dev \
                apache2-suexec-pristine libaprutil1t64 libaprutil1-dev \
                libtest-fatal-perl
systemctl enable apache2.service
# To fix apache2 error: Syntax error on line 146 of /etc/apache2/apache2.conf | Cannot load /usr/lib/apache2/modules/mod_dnssd.so
#nala install -y libapache2-mod-dnssd
# To fix apache2-doc error:
retry_cmd apt -qq install -y --reinstall apache2-doc
upgrade
cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null || true
#sed -i -E 's/^([[:space:]]*)Listen[[:space:]]+([0-9]+)/\1Listen 0.0.0.0:\2/' /etc/apache2/ports.conf

cp -f /etc/apache2/mods-available/mpm_prefork.conf{,.bak} &>/dev/null || true
sed -i \
  -e 's/^\(StartServers[[:space:]]*\)5/\110/' \
  -e 's/^\(MinSpareServers[[:space:]]*\)5/\110/' \
  -e 's/^\(MaxSpareServers[[:space:]]*\)10/\115/' \
  -e 's/^\(MaxRequestWorkers[[:space:]]*\)150/\1200/' \
  -e 's/^\(MaxConnectionsPerChild[[:space:]]*\)0/\11000/' \
  /etc/apache2/mods-available/mpm_prefork.conf

# Enable modules  
a2dismod -q mpm_event || true
a2enmod -q mpm_prefork || true
a2enmod -q "php${PHP_VERSION}" || true
a2enmod -q headers mime rewrite || true

# PROXY SECTION
# squid-cache
while pgrep squid > /dev/null; do
    killall -s SIGTERM squid &>/dev/null
    sleep 5
done
nala purge -y squid* &>/dev/null || true
rm -rf /var/spool/squid* /var/log/squid* /etc/squid* &>/dev/null
rm -f /run/squid.pid &>/dev/null
#DEBIAN_FRONTEND=noninteractive nala install -y --no-install-recommends squid-openssl
retry_cmd nala install -y squid-openssl squid-langpack squid-common squidclient squid-purge
upgrade
mkdir -p /var/log/squid &>/dev/null
touch /var/log/squid/{access,cache,store,deny}.log &>/dev/null
chown proxy:proxy /var/log/squid/*.log
chmod 640 /var/log/squid/*.log
for cache_type in rock ufs; do
    mkdir -p /var/spool/squid/${cache_type} 2>/dev/null
done
chown -R proxy:proxy /var/spool/squid
chmod -R 700 /var/spool/squid
usermod -aG proxy www-data
systemctl enable squid.service
systemctl stop squid.service &>/dev/null || true
squid -z
cp -f /etc/logrotate.d/squid{,.bak} &>/dev/null || true
sed -i '/sharedscripts/a \    create 0644 proxy proxy' /etc/logrotate.d/squid
sed -i 's/rotate 2/rotate 7/' /etc/logrotate.d/squid
sed -i 's/^	daily$/	monthly/' /etc/logrotate.d/squid
# Let's Encrypt certificate for client to Squid proxy encryption (Optional)
#nala install -y certbot python3-certbot-apache
    
# ADMIN SECTION
# webmin
# https://www.maravento.com/2019/06/instalar-modulo-webmin-por-linea-de.html
retry_cmd curl -o setup-repos.sh https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh
chmod +x setup-repos.sh
echo "y" | ./setup-repos.sh
upgrade
retry_cmd nala install -y webmin
upgrade
systemctl enable webmin.service 2>/dev/null || true
log "Webmin Access: https://localhost:10000"
rm -f setup-repos.sh

# webmin modules
# Text Editor | Service Monitor | Netplan Manager
systemctl stop webmin.service 2>/dev/null || true
/usr/share/webmin/install-module.pl "$gp_path/conf/webmin/text-editor.wbm" || log "WARNING: text-editor module install failed"
find "$acl_mac_path" -maxdepth 1 -type f | tee /etc/webmin/text-editor/files &>/dev/null || true
# List of modules to install
for module in servicemon netplanmgr; do
    log "Installing $module module..."
    if wget -q -O "$gp_path/${module}.sh" "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/${module}.sh"; then
        chmod +x "$gp_path/${module}.sh"
        "$gp_path/${module}.sh" install || log "WARNING: $module module install failed"
        rm -f "$gp_path/${module}.sh"
    else
        log "Error: Failed to download ${module}.sh"
    fi
done

# Proxy Monitor
retry_cmd nala install -y rsync nbtscan libcgi-session-perl libgd-perl sarg
if (cd "$gp_path" && git clone https://github.com/maravento/proxymon); then
    if cd "$gp_path/proxymon"; then
        if [ -f proxymon.sh ]; then
            chmod +x proxymon.sh
            PROXYMON_EXPECT=$(mktemp)
            cat > "$PROXYMON_EXPECT" <<EOF
spawn ./proxymon.sh install
interact {
    -o
    "LAN interface (default:" {
        send "$LAN_INTERFACE\r"
    }
    "Server IP for LAN (default:" {
        send "$serverip\r"
    }
}
catch wait result
exit [lindex \$result 3]
EOF
            if expect -f "$PROXYMON_EXPECT"; then
                log "Sent to proxymon: serverip=$serverip lan_interface=$LAN_INTERFACE"
            else
                log "WARNING: proxymon.sh install failed. Skipping installation."
            fi
            rm -f "$PROXYMON_EXPECT"
        fi
        cd "$gp_path"
    else
        log "WARNING: Cannot enter proxymon directory. Skipping installation."
    fi
else
    log "WARNING: Failed to clone proxymon. Skipping installation."
fi

# DHCP SECTION
# pydhcp
log "Installing pydhcp..."

if (cd "$gp_path" && git clone https://github.com/maravento/pydhcp); then
    pydhcp_path="$gp_path/pydhcp"

    if [ -d "$pydhcp_path" ]; then
        if cd "$pydhcp_path"; then
            PYDHCP_EXPECT=$(mktemp)
            cat > "$PYDHCP_EXPECT" <<EOF
spawn bash pyinstall.sh
expect -re {\[([0-9]+)\][ \t]+$LAN_INTERFACE[ \t(]}
send "\$expect_out(1,string)\r"
expect "Enter DHCP server IP"
send "$serverip\r"
expect "Enter netmask"
send "$MASKNEW1\r"
expect "Enter pool start"
send "\r"
expect "Enter pool end"
send "\r"
expect eof
catch wait result
exit [lindex \$result 3]
EOF
            expect -f "$PYDHCP_EXPECT" || log "WARNING: pydhcp install failed"
            rm -f "$PYDHCP_EXPECT"

            cd "$gp_path"
            log "DHCP pool range: 220-235 (default). To modify edit /etc/pydhcp/pydhcpd.env"
        else
            log "WARNING: Cannot enter pydhcp directory. Skipping pydhcp installation."
        fi
    else
        log "WARNING: pydhcp directory not found. Skipping pydhcp installation."
    fi
else
    log "WARNING: Failed to clone pydhcp. Skipping pydhcp installation."
fi

# LOGS SECTION 
# ulog2
# https://www.maravento.com/2014/07/registros-iptables.html
chown root:root /var/log
retry_cmd nala install -y ulogd2
mkdir -p /var/log/ulog &>/dev/null
touch /var/log/ulog/syslogemu.log &>/dev/null
usermod -a -G ulog "$local_user"
(crontab -l 2>/dev/null || true; echo "#*/10 * * * * /etc/scr/banip.sh") | crontab -
log "Ulog Access: /var/log/ulog/syslogemu.log"
# rsyslog
# in case fails: nala install -y libfastjson4
retry_cmd nala install -y rsyslog
systemctl enable rsyslog.service
    
# BACKUP SECTION 
# Timeshift
retry_cmd nala install -y timeshift
# FreeFileSync
retry_cmd nala install -y libatk-adaptor libgail-common
retry_cmd wget -O "$gp_path/conf/scr/ffsupdate.sh" https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/ffsupdate.sh
chmod +x "$gp_path/conf/scr/ffsupdate.sh"
"$gp_path/conf/scr/ffsupdate.sh" || log "WARNING: ffsupdate.sh failed (FreeFileSync not installed)"
(crontab -l 2>/dev/null || true; echo "@weekly /etc/scr/ffsupdate.sh") | crontab -
log "OK"
sleep 1

echo -e "\n"
while true; do
read -r -p "Do you want to install Optional Pack?
Net Tools, fail2ban, Suricata-Evebox (y/n)" answer
    case "$answer" in
    [Yy]*)
        # execute command yes
        # Net Tools (Replace NIC and IP/CIDR)
        retry_cmd nala install -y wireless-tools     # Wireless tools: iwconfig, iwlist, iwpriv
        retry_cmd nala install -y fping              # Net diagnostics: fping -a -g 192.168.1.0/24
        retry_cmd nala install -y ethtool            # Net config: ethtool eth0
        # Net test: On server: iperf3 -s | On client: iperf3 -c serverip
        DEBIAN_FRONTEND=noninteractive retry_cmd nala install -y iperf3  2>/dev/null
        # Net Scanning (Replace NIC and IP/CIDR)
        retry_cmd nala install -y masscan            # masscan --ports 0-65535 192.168.0.0/16
        retry_cmd nala install -y nbtscan            # nbtscan 192.168.1.0/24
        retry_cmd nala install -y nast               # nast -m
        retry_cmd nala install -y arp-scan           # arp-scan --localnet
        retry_cmd nala install -y arping             # arping -I eth0 192.168.1.1
        retry_cmd nala install -y netdiscover        # netdiscover
        # Nmap
        retry_cmd nala install -y nmap python3-nmap ndiff
        # Domain/IP Scanning
        retry_cmd nala install -y traceroute         # traceroute google.com
        retry_cmd nala install -y mtr-tiny           # mtr google.com
        # fail2ban
        retry_cmd nala install -y fail2ban
        cp "$gp_path/conf/pack/jail.local" /etc/fail2ban/jail.local
        sed -i 's/^#\?allowipv6 *= *.*/allowipv6 = 0/' /etc/fail2ban/fail2ban.conf
        systemctl enable fail2ban.service
        log "Check: sudo fail2ban-client status <jail_name>"
        log "Unban all: sudo fail2ban-client unban --all"
        log "Unban Jail: sudo fail2ban-client set <jail_name> unban --all"
        # lynis
        retry_cmd nala install -y lynis
        log "Lynis Run: lynis -c -Q and log: /var/log/lynis.log"
        # fsearch
        add-apt-repository -y ppa:christian-boxdoerfer/fsearch-stable || true
        upgrade
        nala install -y fsearch || true
        # ttyd (web terminal)
        retry_cmd nala install -y ttyd
        cp -f "$gp_path/conf/pack/ttyd.service" /etc/systemd/system/ttyd.service
        sed -i "s/your_user/$local_user/g" /etc/systemd/system/ttyd.service
        systemctl daemon-reload
        systemctl enable ttyd.service
        log "ttyd Access: http://localhost:7681"
        # suricata install
        retry_cmd nala install -y suricata suricata-update jq
        sed -i "s/interface: eth[0-9]/interface: $LAN_INTERFACE/g" /etc/suricata/suricata.yaml
        if grep -q "community-id: false" /etc/suricata/suricata.yaml; then
            sed -i 's/community-id: false/community-id: true/' /etc/suricata/suricata.yaml
            log "OK: Community-ID enabled"
        fi
        # suricata disable and drop
        cp -f "$gp_path/conf/pack/"{disable,drop}.conf /etc/suricata/
        chown root:root /etc/suricata/{disable,drop}.conf
        chmod 644 /etc/suricata/{disable,drop}.conf
        # suricata update & clean
        if [ ! -f /var/log/suricata/suricatacron.log ]; then
            touch /var/log/suricata/suricatacron.log
            chown root:root /var/log/suricata/suricatacron.log
            chmod 640 /var/log/suricata/suricatacron.log
        fi        
        cp -f "$gp_path/conf/pack/"{suricataupdate,suricataclean}.sh /etc/suricata/
        chmod +x /etc/suricata/{suricataupdate,suricataclean}.sh
        # suricata ratio
        if ! grep -q "detect-thread-ratio: 0.5" /etc/suricata/suricata.yaml; then
            sed -i 's/detect-thread-ratio: 1.0/detect-thread-ratio: 0.5/' /etc/suricata/suricata.yaml
        fi
        # suricata cron
        (crontab -l 2>/dev/null || true; echo "0 2 * * * /etc/suricata/suricataupdate.sh >/dev/null 2>&1") | crontab -
        (crontab -l 2>/dev/null || true; echo "@monthly /etc/suricata/suricataclean.sh >/dev/null 2>&1") | crontab -
        # suricata check IDS
        SURICATA_SERVICE="/usr/lib/systemd/system/suricata.service"
        CORRECT_EXECSTART="ExecStart=/usr/bin/suricata -D --af-packet -c /etc/suricata/suricata.yaml --pidfile /run/suricata.pid"
        if grep -q "^ExecStart=.*--af-packet" "$SURICATA_SERVICE" && ! grep -q "^ExecStart=.*-q" "$SURICATA_SERVICE"; then
            log "OK: Suricata Mode: IDS"
        else
            log "Fixing Suricata IDS..."
            sed -i "s|^ExecStart=.*|$CORRECT_EXECSTART|" "$SURICATA_SERVICE"
            log "Suricata Mode: IDS"
        fi
        # evebox
        mkdir -p /etc/apt/keyrings
        retry_cmd curl -fsSL https://evebox.org/files/GPG-KEY-evebox -o /etc/apt/keyrings/evebox.asc
        echo "deb [signed-by=/etc/apt/keyrings/evebox.asc] https://evebox.org/files/debian stable main" | tee /etc/apt/sources.list.d/evebox.list
        upgrade
        retry_cmd nala install -y evebox
        # Configure
        cp -f "$gp_path/conf/pack/evebox.yaml" /etc/evebox/evebox.yaml
        cp -f "$gp_path/conf/pack/evebox.service" /etc/systemd/system/evebox.service
        systemctl daemon-reload
        systemctl enable suricata evebox
        log "EVEBox: http://localhost:5636"
        break
        ;;
    [Nn]*)
        # execute command no
        log "NO"
        break
        ;;
    *)
        echo
        log "Answer: YES (y) or NO (n)"
        ;;
    esac
done

upgrade

### SHARED ###
# Samba with Shared folder, Recycle Bin and Audit
echo -e "\n"
while true; do
    read -r -p "Do you want to install Samba?
with SHARED folder, Recycle Bin and Audit (y/n)" answer

    case "$answer" in
    [Yy]*)
        if (cd "$gp_path" && git clone https://github.com/maravento/smbstack); then
            smbstack_path="$gp_path/smbstack"

            if [ -d "$smbstack_path" ]; then
                if cd "$smbstack_path"; then
                    SMB_EXPECT=$(mktemp)
                    cat > "$SMB_EXPECT" <<EOF
spawn bash smbinstall.sh --install
interact {
    -o
    "Enter Samba server IP/network (e.g. 192.168.1.0/24): " {
        send "$LOCALNETNEW/$MASKNEW2\r"
    }
    "Enter network interface: " {
        send "$LAN_INTERFACE\r"
    }
}
catch wait result
exit [lindex \$result 3]
EOF
                    if expect -f "$SMB_EXPECT"; then
                        log "smbstack installed OK"
                    else
                        log "WARNING: smbinstall.sh --install failed. Skipping Samba installation."
                    fi
                    rm -f "$SMB_EXPECT"
                    cd "$gp_path"
                else
                    log "WARNING: Cannot enter smbstack directory. Skipping Samba installation."
                fi
            else
                log "WARNING: smbstack directory not found. Skipping Samba installation."
            fi
        else
            log "WARNING: Failed to clone smbstack. Skipping Samba installation."
        fi
        break
        ;;

    [Nn]*)
        log "NO"
        break
        ;;

    *)
        echo
        log "Answer: YES (y) or NO (n)"
        ;;
    esac
done
log "OK"

upgrade

### ACLs ###
echo -e "\n"
log "Downloading ACLs..."
# Allow IP
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackip/master/bipupdate/lst/allowip.txt -O "$acl_path/acl_squid/allowip.txt" || true
if [ ! -s "$acl_path/acl_squid/allowip.txt" ]; then
    log "WARNING: allowip.txt download failed"
fi

# Block Patterns
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/source/squid/blockpatterns.txt -O "$acl_path/acl_squid/blockpatterns.txt" || true
if [ ! -s "$acl_path/acl_squid/blockpatterns.txt" ]; then
    log "WARNING: blockpatterns.txt download failed"
fi

# Block TLDs
wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/blocktlds.txt -O "$acl_path/acl_squid/blocktlds.txt" || true
if [ ! -s "$acl_path/acl_squid/blocktlds.txt" ]; then
    log "WARNING: blocktlds.txt download failed, disabling ACL in squid.conf"
    sed -i '/^acl blocktlds /s/^/#/; /^http_access deny workdays blocktlds/s/^/#/' "$gp_path/conf/server/squid.conf"
fi

# Blackweb
if (cd "$gp_path" && wget -q --show-progress -c -N https://raw.githubusercontent.com/maravento/blackweb/master/blackweb.tar.gz && [ -f blackweb.tar.gz ]); then
    (cd "$gp_path" && cat blackweb.tar.gz* | tar xzf -)
    cp "$gp_path/blackweb.txt" "$acl_path/acl_squid/blackweb.txt"
else
    log "WARNING: blackweb.tar.gz download failed"
fi
rm -f "$gp_path"/blackweb.*
log "OK"
sleep 1

### ADD CONFIG ###
echo -e "\n"
log "Applying Config..."
# squid
cp -f /etc/squid/squid.conf{,.bak} &>/dev/null || true
cp -f "$gp_path/conf/server/squid.conf" /etc/squid/squid.conf
chown root:root /etc/squid/squid.conf
chmod 644 /etc/squid/squid.conf
systemctl restart squid.service
# scripts
# Download external scripts to project scr folder
scripts=(
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackusb/linux/blackusb.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/cleaner.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/filereport.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/hwclock.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/lock.sh"
)
for url in "${scripts[@]}"; do
    fname=$(basename "$url")

    if wget -q -O "$gp_path/conf/scr/$fname" "$url"; then
        log "Downloaded: $fname"
    else
        log "WARNING: Failed to download $fname. Skipping."
    fi
done

# scripts
cp -fr "$gp_path/conf/scr/"* "$scr_path"
chown -R root:root "$scr_path"/*
find "$scr_path" -name "*.sh" -exec chmod +x {} \;
# Choose your security level: "Secure Share Memory" (optional)
#echo 'none /run/shm tmpfs defaults,ro 0 0' | tee -a /etc/fstab &> /dev/null
#echo 'tmpfs /tmp tmpfs defaults,size=30%,nofail,noatime,mode=1777 0 0' | tee -a /etc/fstab &> /dev/null
# alternative
grep -qxF 'tmpfs /tmp tmpfs defaults,size=2G,nofail,noatime,mode=1777 0 0' /etc/fstab || \
    echo 'tmpfs /tmp tmpfs defaults,size=2G,nofail,noatime,mode=1777 0 0' >> /etc/fstab
log "OK"
sleep 1

echo -e "\n"
log "Proxy Apache Config..."

cp -f /etc/apache2/sites-available/000-default.conf{,.bak} &>/dev/null || true
sed -i "s_\(#LogLevel info ssl:warn\)_\1\n\tLogLevel warn_" /etc/apache2/sites-available/000-default.conf
add_txt="$gp_path/conf/server/000-add.txt"
sed -i "/DocumentRoot/{
    s/\(DocumentRoot.*\)/\1/g
    r $add_txt
}" /etc/apache2/sites-available/000-default.conf

mkdir -p /var/www/wpad
chown www-data:www-data /var/www/wpad
cp -f "$gp_path/conf/server/wpad.pac" /var/www/wpad/wpad.pac
chown www-data:www-data /var/www/wpad/wpad.pac
chmod 644 /var/www/wpad/wpad.pac
cp -f "$gp_path/conf/server/wpad.conf" /etc/apache2/sites-available/wpad.conf
chmod 644 /etc/apache2/sites-available/wpad.conf
a2ensite -q wpad.conf
grep -qxF "Listen $serverip:18100" /etc/apache2/ports.conf || grep -qxF 'Listen 18100' /etc/apache2/ports.conf || echo "Listen $serverip:18100" >> /etc/apache2/ports.conf
apachectl -t -D DUMP_INCLUDES -S || true
log "WPAD-PAC: http://$serverip:18100/wpad.pac"
log "OK"
sleep 1

echo -e "\n"
log "Adding Parameters..."
grep -qxF '*.none    /var/log/ulog/syslogemu.log' /etc/rsyslog.conf || \
    echo '*.none    /var/log/ulog/syslogemu.log' | tee -a /etc/rsyslog.conf >/dev/null

# backup conf files
cp -f /etc/security/limits.conf{,.bak} &>/dev/null || true
cp -f /etc/systemd/system.conf{,.bak} &>/dev/null || true
cp -f /etc/systemd/user.conf{,.bak} &>/dev/null || true
cp -f /etc/sysctl.conf{,.bak} &>/dev/null || true
cp -f /etc/hosts{,.bak} &>/dev/null || true

# adding parameters
tee -a /etc/security/limits.conf >/dev/null <<EOT
*       soft    nproc   65535
*       hard    nproc   65535
*       soft    nofile  65535
*       hard    nofile  65535
root    soft    nproc   65535
root    hard    nproc   65535
root    soft    nofile  65535
root    hard    nofile  65535
EOT
tee -a /etc/sysctl.conf >/dev/null <<EOT
# System optimization
vm.swappiness = 10
net.ipv4.tcp_congestion_control = bbr
EOT
echo "DefaultLimitNOFILE=65535" | tee -a /etc/systemd/system.conf >/dev/null
echo "DefaultLimitNOFILE=65535" | tee -a /etc/systemd/user.conf >/dev/null
sysctl -p || log "WARNING: some sysctl parameters failed to apply"

log "Apache Config..."
cp -f /etc/apache2/apache2.conf{,.bak} &>/dev/null || true
#echo 'RequestReadTimeout header=10-20,MinRate=500 body=20,MinRate=500' | tee -a /etc/apache2/apache2.conf # optional
cp -f "$gp_path/conf/server/servername.conf" /etc/apache2/conf-available/servername.conf
a2enconf servername

# Hardening
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
a2enconf -q security || true
log "OK"
sleep 1

# APACHE PASSWORD
echo -e "\n"
log "Create Apache Password: /var/www/..."
echo -e "\n"
until htpasswd -c /etc/apache2/.htpasswd "$local_user"; do
    log "Passwords did not match or were empty. Try again."
done

# APACHE CONFIG
apache2ctl configtest || true
chmod -R 755 /var/www
chown -R www-data:www-data /var/www
apachectl -t -D DUMP_INCLUDES -S || true
log "OK"
sleep 1

# CRONTAB
echo -e "\n"
log "Add Crontab Tasks..."
(crontab -l 2>/dev/null || true; echo "@reboot systemctl daemon-reload
@reboot /etc/scr/hwclock.sh
@reboot /etc/scr/lock.sh
@reboot /etc/scr/blackusb.sh off
*/5 * * * * /etc/scr/serviceswatch.sh
@weekly /etc/scr/cleaner.sh") | sort -u | crontab -
log "OK"
sleep 1

### ENDING ###
# Disable NFS (Network File System) / NIS (Network Information Service)
if systemctl list-unit-files | grep -q '^rpcbind'; then
    systemctl stop rpcbind.service rpcbind.socket &>/dev/null || true
    systemctl disable rpcbind.service rpcbind.socket &>/dev/null || true
    systemctl mask rpcbind.service rpcbind.socket &>/dev/null || true
fi

# Restart Daemon
systemctl daemon-reexec &>/dev/null
# Update initramfs (optional)
#update-initramfs -u -k all
# create alias "upgrade"
sudo -u "$local_user" bash -c "printf '%s\n' 'alias upgrade=\"sudo nala upgrade --purge -y && sudo aptitude -y safe-upgrade && sudo sync && sudo dpkg --configure -a && sudo nala install --fix-broken -y && sudo systemctl daemon-reload && sudo updatedb && sudo update-desktop-database && sudo snap refresh\"' >> /home/${local_user}/.bashrc"
sudo -u "$local_user" bash -c "printf '%s\n' 'alias server=\"sudo /etc/scr/serverboot.sh\"' >> /home/${local_user}/.bashrc"
sudo -u "$local_user" bash -c "printf '%s\n' 'alias cleaner=\"sudo /etc/scr/cleaner.sh\"' >> /home/${local_user}/.bashrc"
# IPv4 priority
sed -i 's/^#\s*precedence ::ffff:0:0\/96\s\+100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
# snap
snap unset system proxy.http || true
snap unset system proxy.https || true
retry_cmd snap refresh snapd
systemctl daemon-reload
systemctl restart snapd || true
retry_cmd snap refresh
# logs
chmod 755 /var/log
chown root:syslog /var/log

upgrade

clear
echo -e "\n"
log "Done. Press ENTER to Reboot"
log "after reboot, run:"
log "systemctl list-units --type service --state running,failed"
read -r RES
systemctl daemon-reexec
systemctl daemon-reload
update-ca-certificates -f
systemctl reload apache2 || true
sed -i '/^#\?SystemMaxUse=$/s/.*/SystemMaxUse=50M/' /etc/systemd/journald.conf
journalctl --vacuum-size=50M
a2query -s || true
#apt -qq -y remove --purge `deborphan --guess-all` # optional
#dpkg -l | grep "^rc" | cut -d " " -f 3 | xargs dpkg --purge &> /dev/null # optional
rm -f gitfolder.py
rm -rf "$gp_path"
(sleep 2 && rm -- "$SCRIPT_PATH") &

log "gateproxy done at: $(date)"
reboot
