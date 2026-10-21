#!/bin/bash
# maravento.com
#
################################################################################
#
# Gateproxy
# A simple proxy/firewall server
# FILE: gpsetup.sh
#
# USAGE:
# sudo bash gpsetup.sh
#
# LOG: gpsetup.log, in the directory containing this script
#      (rewritten on each run)
#
################################################################################

set -Eeuo pipefail

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
failure_message="cannot open the installer lock"
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# The log lives in this script's own directory, not inside $gp_path: that
# folder is deleted and re-downloaded during the run, and again at the end,
# so a log kept there would not survive. Emptied at the start of every run,
# so what it holds is always the last install attempt and nothing else.
failure_message="cannot find the installer log directory"
log_file="$(dirname "$(realpath "$0")")/gpsetup.log" || { failure_status=$?; report_failure; exit "$failure_status"; }
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$(date '+%Y-%m-%d %H:%M:%S') $1"
    echo "$msg" >> "$log_file" 2>/dev/null || true
    if [[ "$1" == ERROR:* ]]; then echo "$msg" >&2; else echo "$msg"; fi
}

info() { log "INFO: $*"; }
warn() { log "WARNING: $*"; }
err() { log "ERROR: $*"; }
abort() { err "$*"; exit 1; }

# Each module clones into $gp_path, writes its own log there, and $gp_path is
# deleted at the end. Its log is appended here while the folder still exists.
dump_module_log() {
    local module_log="$1"
    local module_name="$2"
    if [ -f "$module_log" ]; then
        log "--- begin $module_name log ---"
        cat "$module_log" >> "$log_file" 2>/dev/null || true
        log "--- end $module_name log ---"
    else
        warn "$module_name log not found at $module_log -alert"
    fi
}
report_failure() {
    local failure_text="$failure_message"
    if (( ${#failure_text} <= 46 )); then
        failure_text+=" -abort"
    fi
    if declare -F err >/dev/null; then
        err "$failure_text"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $failure_text" >&2
    fi
}

failure_message="cannot initialize Gateproxy"
trap 'report_failure' ERR

log "gpsetup start..."
printf "\n"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# conflicting packages
check_conflicts() {
    local role="$1"; shift
    local found=()
    for dep_pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null | grep -q "ok installed"; then
            found+=("$dep_pkg")
        fi
    done
    if [ "${#found[@]}" -gt 0 ]; then
        for dep_pkg in "${found[@]}"; do
            warn "conflicting $role: $dep_pkg -alert"
        done
        err "remove them with apt purge -abort"
        exit 1
    fi
}

# overlapping packages
warn_overlap() {
    local feature="$1"; shift
    local dep_pkg
    for dep_pkg in "$@"; do
        if dpkg-query -W -f='${Status}' "$dep_pkg" 2>/dev/null | grep -q "ok installed"; then
            warn "$dep_pkg installed; check for $feature conflicts -alert"
        fi
    done
}

# port in use
check_port() {
    local proto="$1" port="$2" role="$3"
    if [ -n "$(ss -lnH "-${proto,,}" "sport = :$port" 2>/dev/null)" ]; then
        err "${proto^^} port $port in use by another $role"
        err "stop that service before installing -abort"
        exit 1
    fi
}

# ACL download
get_acl() {
    local source_url="$1" target_file="$2" http_code
    http_code=$(curl -k -s -o /dev/null -w '%{http_code}' -I -L --connect-timeout 5 --max-time 15 --retry 1 "$source_url")
    case "$http_code" in
        2*|405) ;;
        000) log "TIMEOUT: $source_url"; return 1 ;;
        5*)  log "BUSY: $http_code $source_url"; return 1 ;;
        404|410)   log "BROKEN: $http_code $source_url"; return 1 ;;
        *)   log "HTTP_ERROR: $http_code $source_url"; return 1 ;;
    esac
    if ! wget -q -c -N --timeout=15 --tries=1 "$source_url" -O "$target_file"; then
        log "PARTIAL: $source_url"
        return 1
    fi
    log "SAVED: $(basename "$source_url")"
}

retry_cmd() {
    local max_attempts=10
    local attempt=1
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            if [ -n "${download_url:-}" ]; then
                log "PARTIAL: $download_url"
            fi
            report_failure
            exit 1
        fi
        info "$(basename "$1"): retry $((attempt + 1))/$max_attempts"
        case "$1" in
            nala|apt|apt-get)
                rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true
                ;;
        esac
        attempt=$((attempt + 1))
        sleep 10
    done
}

download_url=""

# CRON_D
# Add or replace one line in the project's single cron.d file
cron_d_set() {
    local match="$1" line="$2"
    local cron_file="/etc/cron.d/gateproxy"
    local cron_tmp

    cron_tmp=$(mktemp) || return 1
    if [ -f "$cron_file" ]; then
        grep -vF "$match" "$cron_file" > "$cron_tmp" || {
            [ "$?" -eq 1 ] || { rm -f "$cron_tmp"; return 1; }
        }
    fi
    if [ -n "$line" ]; then
        printf '%s\n' "$line" >> "$cron_tmp" || {
            rm -f "$cron_tmp"
            return 1
        }
    fi
    if [ -s "$cron_tmp" ]; then
        if ! install -m 644 -o root -g root "$cron_tmp" "$cron_file"; then
            rm -f "$cron_tmp"
            return 1
        fi
    else
        rm -f "$cron_file"
    fi
    rm -f "$cron_tmp"
}

log "Checking for conflicting pre-installed packages..."
failure_message="cannot check conflicting packages"
check_conflicts "DHCP server" isc-dhcp-server kea-dhcp4-server udhcpd
failure_message="cannot check conflicting packages"
check_conflicts "DNS server"  bind9 pdns-recursor unbound
failure_message="cannot check conflicting packages"
check_conflicts "proxy"       squid squid3 squid-openssl
failure_message="cannot check conflicting packages"
check_conflicts "web server"  apache2 nginx lighttpd caddy
failure_message="cannot check conflicting packages"
check_conflicts "file server" samba
failure_message="cannot check conflicting packages"
check_conflicts "syslog"      syslog-ng
failure_message="cannot check conflicting packages"
check_conflicts "firewall"    firewalld fail2ban
failure_message="cannot check conflicting packages"
check_conflicts "IDS"         snort suricata evebox
failure_message="cannot check conflicting packages"
check_conflicts "web admin"   webmin ttyd
failure_message="cannot check conflicting packages"
check_conflicts "time sync"   chrony ntpsec
failure_message="cannot check conflicting packages"
check_conflicts "mail"        exim4
failure_message="cannot check the required network port"
check_port udp 67 "DHCP server"
failure_message="cannot check overlapping packages"
warn_overlap "dhcp" dnsmasq
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "^Status: active"; then
    err "ufw active; disable it before Gateproxy -abort"
    exit 1
fi
info "No conflicting packages found: OK"

# local_user detection
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
    err "no local user; create one with sudo access -abort"
    exit 1
fi
failure_message="cannot read the local user home directory"
local_home=$(getent passwd "$local_user" | cut -d: -f6) || { failure_status=$?; report_failure; exit "$failure_status"; }
if [ -z "$local_home" ] || [ ! -d "$local_home" ]; then
    err "no home directory for user $local_user -abort"
    exit 1
fi
info "Using local user: $local_user ($local_home)"

# check internet
check_internet() {
    local failure_message="cannot check internet access"
    local max_attempts="${1:-24}" attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            info "internet is available"
            return 0
        fi
        info "waiting for internet ($attempt/$max_attempts)"
        attempt=$((attempt + 1))
        failure_message="cannot wait before the next attempt"
        sleep 5
    done

    return 1
}

if ! check_internet; then
    err "no internet connection -abort"
    exit 1
fi

# CHECK SO & DESKTOP
# Check the operating system and desktop environment
log "Check System..."
# lsb_release (lsb-release package) is used below but the DEPENDENCIES block
# hasn't run yet at this point in the script -- ensure it exists here instead.
failure_message="cannot install lsb-release"
command -v lsb_release &>/dev/null || apt-get install -y lsb-release
# Get the current desktop environment in lowercase
failure_message="cannot read the desktop environment"
DESKTOP_ENV=$(echo "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]') || { failure_status=$?; report_failure; exit "$failure_status"; }
# Get the Ubuntu version number
failure_message="cannot read the Ubuntu version"
UBUNTU_VERSION=$(lsb_release -rs) || { failure_status=$?; report_failure; exit "$failure_status"; }
# Get the distribution ID
failure_message="cannot read the distribution name"
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]') || { failure_status=$?; report_failure; exit "$failure_status"; }
info "Desktop: $DESKTOP_ENV"
info "OS: $UBUNTU_ID $UBUNTU_VERSION"
if [ "$UBUNTU_ID" != "ubuntu" ]; then
    warn "unsupported OS $UBUNTU_ID, Ubuntu only -alert"
elif [ "$UBUNTU_VERSION" != "24.04" ] && [ "$UBUNTU_VERSION" != "26.04" ]; then
    warn "unsupported version $UBUNTU_VERSION -alert"
fi

log "Clearing apt package cache..."
apt-get clean &>/dev/null || true
rm -f /var/cache/apt/archives/*.deb 2>/dev/null || true

# PPA
# Enable the required Ubuntu repository components
file="/etc/apt/sources.list.d/ubuntu.sources"
required_components=("main" "restricted" "universe" "multiverse")
changed=0

if [ -f "$file" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^Components: ]]; then
            failure_message="cannot read Components from ubuntu.sources"
            read -ra found <<< "${line#Components: }"

            for required in "${required_components[@]}"; do
                if ! printf '%s\n' "${found[@]}" | grep -qx "$required"; then
                    info "Missing '$required' in: $line"
                    failure_message="cannot edit $(basename "$file")"
                    sed -i "s|^$line|Components: ${required_components[*]}|" "$file"
                    changed=1
                    break
                fi
            done

            if [[ $changed -eq 0 ]]; then
                info "All components present in: $line"
            fi
        fi
    done < <(grep "^Components:" "$file")

    if [[ $changed -eq 1 ]]; then
        log "Updating package list. Wait..."
        failure_message="cannot update APT package lists"
        retry_cmd apt update > /dev/null 2>&1
    else
        info "No changes made. No update needed"
    fi
else
    info "$(basename "$file") not found -skip"
fi

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

failure_message="cannot find the installer path"
SCRIPT_PATH="$(realpath "$0")" || { failure_status=$?; report_failure; exit "$failure_status"; }
failure_message="cannot find the Gateproxy working directory"
gp_path=$(pwd)/gateproxy || { failure_status=$?; report_failure; exit "$failure_status"; }
ACL_PATH=/etc/acl
failure_message="cannot create ACL directories"
mkdir -p "$ACL_PATH" &>/dev/null
SCR_PATH=/etc/scr
failure_message="cannot create Gateproxy scripts"
mkdir -p "$SCR_PATH" &>/dev/null

# validation -- one variable per thing validated; use directly with =~
UH_OCT='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
UH_CIDR='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])/(3[0-2]|[12][0-9]|[0-9])$'
UH_NETMASK='^(0\.0\.0\.0|128\.0\.0\.0|192\.0\.0\.0|224\.0\.0\.0|240\.0\.0\.0|248\.0\.0\.0|252\.0\.0\.0|254\.0\.0\.0|255\.0\.0\.0|255\.128\.0\.0|255\.192\.0\.0|255\.224\.0\.0|255\.240\.0\.0|255\.248\.0\.0|255\.252\.0\.0|255\.254\.0\.0|255\.255\.0\.0|255\.255\.128\.0|255\.255\.192\.0|255\.255\.224\.0|255\.255\.240\.0|255\.255\.248\.0|255\.255\.252\.0|255\.255\.254\.0|255\.255\.255\.0|255\.255\.255\.128|255\.255\.255\.192|255\.255\.255\.224|255\.255\.255\.240|255\.255\.255\.248|255\.255\.255\.252|255\.255\.255\.254|255\.255\.255\.255)$'
UH_DNS='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])(,(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9]))*$'
UH_UINT='^(0|[1-9][0-9]*)$'
UH_PREFIX='0.0.0.0:0 128.0.0.0:1 192.0.0.0:2 224.0.0.0:3 240.0.0.0:4 248.0.0.0:5 252.0.0.0:6 254.0.0.0:7 255.0.0.0:8 255.128.0.0:9 255.192.0.0:10 255.224.0.0:11 255.240.0.0:12 255.248.0.0:13 255.252.0.0:14 255.254.0.0:15 255.255.0.0:16 255.255.128.0:17 255.255.192.0:18 255.255.224.0:19 255.255.240.0:20 255.255.248.0:21 255.255.252.0:22 255.255.254.0:23 255.255.255.0:24 255.255.255.128:25 255.255.255.192:26 255.255.255.224:27 255.255.255.240:28 255.255.255.248:29 255.255.255.252:30 255.255.255.254:31 255.255.255.255:32'

# ------------------------------------------------------------------------------
# DEPENDENCIES
# ------------------------------------------------------------------------------

# PACKAGES
# Install the base system packages
echo -e "\n"
log "Check Dependencies..."

pkgs='nala curl wget software-properties-common apt-transport-https aptitude net-tools plocate git git-gui gitk gist expect tcl-expect libnotify-bin gcc make perl bzip2 7zip rar unrar unzip zip unace cabextract arj zlib1g-dev tzdata tar coreutils dconf-editor python-is-python3 iproute2'
failure_message="cannot collect missing package names"
missing=$(for p in $pkgs; do dpkg -s "$p" &>/dev/null || echo "$p"; done)
unavailable=""
for p in $missing; do
    apt-cache show "$p" &>/dev/null || unavailable+=" $p"
done

if [ -n "$unavailable" ]; then
    for u in $unavailable; do
        warn "'$u' is not available in APT -alert"
    done
    err "enable package repositories and retry -abort"
    exit 1
fi
if [ -n "$missing" ]; then
    log "Waiting for apt/dpkg to finish..."
    apt_wait=0
    apt_wait_limit=60
    while pgrep -x apt > /dev/null 2>&1 || pgrep -x apt-get > /dev/null 2>&1 || pgrep -x dpkg > /dev/null 2>&1; do
        if [ "$apt_wait" -ge "$apt_wait_limit" ]; then
            err "apt/dpkg lock not released -abort"
            exit 1
        fi
        info "Waiting for apt/dpkg ($apt_wait/$apt_wait_limit)"
        failure_message="cannot wait before the next attempt"
        sleep 5
        apt_wait=$((apt_wait + 1))
    done
    failure_message="cannot remove APT package lists"
    rm -f /var/lib/apt/lists/lock
    failure_message="cannot remove APT package cache"
    rm -f /var/cache/apt/archives/lock
    failure_message="cannot remove DPKG lock files"
    rm -f /var/lib/dpkg/lock
    failure_message="cannot remove DPKG lock files"
    rm -f /var/lib/dpkg/lock-frontend
    failure_message="cannot remove APT package lists"
    rm -rf /var/lib/apt/lists/*
    failure_message="cannot configure pending DPKG packages"
    dpkg --configure -a
    failure_message="cannot update APT package lists"
    apt-get -qq update
    failure_message="cannot install packages with apt-get"
    retry_cmd apt-get -y install $missing
fi

# ------------------------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------------------------

# time
failure_message="cannot install packages with apt"
retry_cmd apt install -y --reinstall systemd-timesyncd &>/dev/null
hwclock -w &>/dev/null || warn "hwclock -w failed -alert"
failure_message="cannot enable systemd-timesyncd"
systemctl enable --now systemd-timesyncd &>/dev/null || info "systemd-timesyncd failed to start"
timedatectl set-ntp true &>/dev/null || info "timedatectl set-ntp failed"
timedatectl status | grep -E "NTP|synchroniz" || true
# Performance Co-Pilot (PCP)
systemctl disable --now pmcd pmproxy pmlogger &>/dev/null || warn "PCP failed to disable -alert"
# install | remove
failure_message="cannot install packages with apt"
retry_cmd apt -qq install -y apt-file
failure_message="cannot update the apt-file package index"
retry_cmd apt-file update
apt -qq remove -y zsys &>/dev/null || true
ubuntu-drivers autoinstall &>/dev/null || true
# configure
pro config set apt_news=false || true
failure_message="cannot find a disk device"
DISK=$(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}') || { failure_status=$?; report_failure; exit "$failure_status"; }
[ -n "$DISK" ] && hdparm -W "$DISK" &>/dev/null || true
failure_message="cannot set the loopback address to 127.0.0.1"
ifconfig lo 127.0.0.1
#systemctl disable avahi-daemon cups-browser &> /dev/null # optional
cp /etc/apt/sources.list{,.bak} &>/dev/null || true

# CLEAN | UPDATE | FIX
echo -e "\n"
upgrade() {
    local failure_message="cannot update system packages"
    log "Update and Clean. Wait..."
    failure_message="cannot upgrade system packages"
    retry_cmd nala upgrade --purge -y
    failure_message="cannot upgrade system packages"
    retry_cmd aptitude safe-upgrade -y
    failure_message="cannot configure pending DPKG packages"
    dpkg --configure -a
    failure_message="cannot install packages with nala"
    retry_cmd nala install --fix-broken -y
    failure_message="cannot reload systemd configuration"
    systemctl daemon-reload
    failure_message="cannot write pending data to disk"
    sync
    failure_message="cannot update the file search database"
    updatedb
    failure_message="cannot update the desktop application index"
    command -v update-desktop-database &>/dev/null && update-desktop-database
    true
}

failure_message="cannot update system packages"
upgrade

# GATEPROXY GIT
# Download the Gateproxy project files
echo -e "\n"
[ -d "$gp_path" ] && rm -rf "$gp_path"
download_url="https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py"
failure_message="cannot download $(basename "${download_url%%\?*}")"
retry_cmd wget -qO gitfolder.py --timeout=15 --tries=1 "$download_url"
log "SAVED: gitfolder.py"
download_url=""
failure_message="cannot set permissions on gitfolder.py"
chmod +x gitfolder.py
failure_message="cannot download the Gateproxy repository"
retry_cmd python3 gitfolder.py https://github.com/maravento/vault/gateproxy

# IDENTITY
# Writes this host name, user and home into the reference config files
echo -e "\n"
failure_message="cannot set the server hostname"
hostnamectl set-hostname "$HOSTNAME"
find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:gateproxy:$HOSTNAME:g" "{}"
# changing name user account in config files
find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:your_user:$local_user:g" "{}"
# changing user home path in config files
find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:your_home:$local_home:g" "{}"

# detect interfaces
list_ifaces() {
    local failure_message="cannot list network interfaces"
    failure_message="cannot read the network interface addresses"
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

# check wired interfaces
list_wired_ifaces() {
    local iface state
    while read -r iface state; do
        [ -d "/sys/class/net/$iface/wireless" ] && continue
        printf "%s %s\n" "$iface" "$state"
    done < <(list_ifaces)
}

check_wired_interfaces() {
    local iface state connected=0

    while read -r iface state; do
        info "wired interface: $iface=$state"
        [ "$state" = "UP" ] && connected=$((connected + 1))
    done < <(list_wired_ifaces)

    if [ "$connected" -lt 2 ]; then
        err "two connected wired interfaces are required -abort"
        return 1
    fi

    return 0
}

failure_message="cannot collect network interface addresses"
mapfile -t IFACES < <(list_wired_ifaces | awk '$2 == "UP" {print $1}')
failure_message="cannot read the network interface settings"
DEFAULT_ROUTE_IF="$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')" || { failure_status=$?; report_failure; exit "$failure_status"; }

# print interface list, flagging the current default-route interface as a hint only
print_interfaces() {
    echo "Available network interfaces:"
    for i in "${!IFACES[@]}"; do
        if [ -n "$DEFAULT_ROUTE_IF" ] && [ "${IFACES[$i]}" = "$DEFAULT_ROUTE_IF" ]; then
            printf " [%d] %s (current default route -- likely WAN)\n" "$((i+1))" "${IFACES[$i]}"
        else
            printf " [%d] %s\n" "$((i+1))" "${IFACES[$i]}"
        fi
    done
}

# public interface
public_interface() {
    local failure_message="cannot select the WAN interface"
    while true; do
        failure_message="cannot display the network interfaces"
        print_interfaces
        failure_message="cannot read the WAN interface choice"
        read -r -p "Select Public Network Interface (Internet) [1-${#IFACES[@]}]: " SEL
        if [[ "$SEL" =~ $UH_UINT ]] \
           && [ "${#SEL}" -le 5 ] \
           && [ "$SEL" -ge 1 ] && [ "$SEL" -le "${#IFACES[@]}" ]; then
            CANDIDATE="${IFACES[$((SEL-1))]}"
            while true; do
                failure_message="cannot read the WAN interface confirmation"
                read -r -p "Confirm WAN (Internet) interface is '$CANDIDATE'? (y/n): " CONFIRM
                case "$CONFIRM" in
                    [Yy]) wan_iface="$CANDIDATE"; break 2 ;;
                    [Nn]) break ;;
                    *) info "Answer: YES (y) or NO (n)" ;;
                esac
            done
        else
            info "Invalid selection. Try again"
        fi
    done
    info "WAN interface: $wan_iface"
    find "$gp_path/conf" "$gp_path/scr" -type f -print0 | xargs -0 -I "{}" sed -i "s:eth0:$wan_iface:g" "{}"
}

# local interface
local_interface() {
    local failure_message="cannot select the LAN interface"
    while true; do
        failure_message="cannot display the network interfaces"
        print_interfaces
        failure_message="cannot read the LAN interface choice"
        read -r -p "Select Local Network Interface [1-${#IFACES[@]}]: " SEL
        if [[ "$SEL" =~ $UH_UINT ]] \
           && [ "${#SEL}" -le 5 ] \
           && [ "$SEL" -ge 1 ] && [ "$SEL" -le "${#IFACES[@]}" ]; then
            CANDIDATE="${IFACES[$((SEL-1))]}"
            if [ "$CANDIDATE" = "$wan_iface" ]; then
                info "Interface already assigned to WAN; choose another"
                continue
            fi
            while true; do
                failure_message="cannot read the LAN interface choice"
                read -r -p "Confirm LAN interface is '$CANDIDATE'? (y/n): " CONFIRM
                case "$CONFIRM" in
                    [Yy]) ETH1="$CANDIDATE"; break 2 ;;
                    [Nn]) break ;;
                    *) info "Answer: YES (y) or NO (n)" ;;
                esac
            done
        else
            info "Invalid selection. Try again"
        fi
    done
    info "LAN interface: $ETH1"
    find "$gp_path/conf" "$gp_path/scr" -type f -print0 | xargs -0 -I "{}" sed -i "s:eth1:$ETH1:g" "{}"
    export LAN_IF="$ETH1"
}

is_interfaces() {
    local failure_message="cannot configure the network interfaces"
    if ip link show eth0 &>/dev/null; then
        info "Older NIC-Ethernet Format Detected"
        info "Aborted installation. Check Minimum Requirements"
        failure_message="cannot remove the Gateproxy repository"
        rm -rf "$gp_path" &>/dev/null
        exit
    elif ! check_wired_interfaces; then
        exit 1
    else
        info "Check Net Interfaces: OK"
        failure_message="cannot select the WAN interface"
        public_interface
        failure_message="cannot select the LAN interface"
        local_interface
    fi
}

failure_message="cannot configure the network interfaces"
is_interfaces

# START
# Display the installation introduction and system requirements
failure_message="cannot clear the terminal"
clear
echo -e "\n"
echo "    Welcome to GateProxy"
echo -e "\n"
echo "    Minimum Requirements:"
echo "    CPU:      4+ cores (>= 3.0 GHz)"
echo "    NIC:      2 (WAN & LAN)"
echo "    RAM:      4 GB cache_mem (12+ GB RAM recommended)"
echo "    Storage:  50 GB SSD for cache_dir rock"
echo "    SO:       Ubuntu 24.04/26.04 LTS"
echo -e "\n"
echo "    Press ENTER to start or CTRL+C to abort"
echo -e "\n"
failure_message="cannot read the continue confirmation"
read -r RES
failure_message="cannot clear the terminal"
clear

echo -e "\n"
while true; do
    failure_message="cannot read the server IP answer"
    read -r -p "Do you want to change? Server IP 192.168.0.10? (y/n): " change_ip
    case "$change_ip" in
        [Yy]*)
            while true; do
                failure_message="cannot read the server IP answer"
                read -r -p "Enter IP (e.g. 192.168.0.10): " input_ip
                if [ -z "$input_ip" ]; then
                    SERVER_IP="192.168.0.10"
                    info "Using default IP $SERVER_IP"
                    break
                fi
                serveripNEW=$(printf '%s' "$input_ip" | { [[ "$input_ip" =~ $UH_IPV4 ]] && cat || true; })
                if [ -z "$serveripNEW" ]; then
                    info "You have entered IP incorrect"
                    continue
                fi
                # 192.168.137.0/24 is reserved by iptables.sh for the Windows ICS block
                # rule (see "Block Windows ICS network range"); a server IP in that
                # range would have its own LAN traffic dropped by that rule.
                if [[ "$serveripNEW" == 192.168.137.* ]]; then
                    info "IP $serveripNEW is in ICS range 192.168.137.0/24"
                    info "choose a different range"
                    continue
                fi
                SERVER_IP="$serveripNEW"

                find "$gp_path/conf" -type f -print0 | while IFS= read -r -d '' file; do
                    failure_message="cannot edit $(basename "$file")"
                    sed -i "s:192.168.0.10:$serveripNEW:g" "$file" || exit $?
                done

                find "$gp_path/acl" -type f -name "mac-*" -exec sed -i "s:192.168.0\.:$(echo "$serveripNEW" | awk -F '.' '{OFS="."; $4=""; print $0}'):g" {} \;

                info "You have entered IP $SERVER_IP :OK"
                break
            done
            break
            ;;
        [Nn]*|"")
            SERVER_IP="192.168.0.10"
            info "Default IP: $SERVER_IP"
            break
            ;;
        *)
            info "Answer: YES (y) or NO (n)"
            ;;
    esac
done

# PARAMETERS
# Collect and validate the server configuration parameters
is_ask() {
    local failure_message="cannot read server configuration answers"
    inquiry="$1"
    iresponse="$2"
    funcion="$3"
    while true; do
        failure_message="cannot read the configuration answer"
        read -r -p "$inquiry: " answer
        case "$answer" in
        [Yy]*)
            # execute command yes
            while true; do
                if $funcion; then
                    break
                else
                    info "$iresponse"
                fi
            done
            break
            ;;
        [Nn]*|"")
            # execute command no (default on empty ENTER)
            info "$inquiry: NO"
            break
            ;;
        *)
            echo
            info "Answer: YES (y) or NO (n)"
            ;;
        esac
    done
}

# netmask
SERV_MASK="255.255.255.0"
MASKNEW2="24"

# netmask -- CIDR prefix (MASKNEW2) is derived from this, not asked
# separately, so the two can never contradict each other.
is_mask1() {
    local failure_message="cannot complete is mask1"
    failure_message="cannot read the network mask answer"
    read -r -p "Enter Netmask (e.g. 255.255.255.0): " MASK1
    if [ -z "$MASK1" ]; then
        SERV_MASK="255.255.255.0"
        info "Using default Netmask $SERV_MASK"
    else
        SERV_MASK=$(printf '%s' "$MASK1" | { [[ "$MASK1" =~ $UH_NETMASK ]] && cat || true; })
        if [ -z "$SERV_MASK" ]; then
            SERV_MASK="255.255.255.0"
            return 1
        fi
        info "You have entered Netmask $MASK1 :OK"
    fi
    if [[ " $UH_PREFIX " =~ [[:space:]]${SERV_MASK//./\\.}:([0-9]+)[[:space:]] ]]; then
        MASKNEW2="${BASH_REMATCH[1]}"
    else
        warn "mask '$SERV_MASK' invalid; /24 -fallback"
        MASKNEW2=24
    fi
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:/24:/$MASKNEW2:g" "{}"
    info "Subnet-Mask derived from Netmask: /$MASKNEW2"
    return 0
}

# dns primary
is_dns1() {
    local failure_message="cannot complete is dns1"
    failure_message="cannot read the primary DNS answer"
    read -r -p "Enter DNS1 (e.g. 1.1.1.2): " DNS1
    if [ -z "$DNS1" ]; then
        DNSNEW1="1.1.1.2"
        info "Using default DNS1 $DNSNEW1"
        return 0
    fi
    DNSNEW1=$(printf '%s' "$DNS1" | { [[ "$DNS1" =~ $UH_DNS ]] && cat || true; })
    if [ "$DNSNEW1" ]; then
        failure_message="cannot edit Unbound forward.conf"
        sed -i "s:1.1.1.2:$DNSNEW1:g" "$gp_path/conf/unbound/forward.conf"
        info "You have entered DNS1 $DNS1 :OK"
        return 0
    else
        return 1
    fi
}

# dns secondary
is_dns2() {
    local failure_message="cannot complete is dns2"
    failure_message="cannot read the secondary DNS answer"
    read -r -p "Enter DNS2 (e.g. 1.0.0.2): " DNS2
    if [ -z "$DNS2" ]; then
        DNSNEW2="1.0.0.2"
        info "Using default DNS2 $DNSNEW2"
        return 0
    fi
    DNSNEW2=$(printf '%s' "$DNS2" | { [[ "$DNS2" =~ $UH_DNS ]] && cat || true; })
    if [ "$DNSNEW2" ]; then
        failure_message="cannot edit Unbound forward.conf"
        sed -i "s:1.0.0.2:$DNSNEW2:g" "$gp_path/conf/unbound/forward.conf"
        info "You have entered DNS2 $DNS2 :OK"
        return 0
    else
        return 1
    fi
}

# squid ports
is_port() {
    local proxy_answer intercept_answer
    read -r -p "Enter Squid proxy port [3128]: " proxy_answer
    proxy_answer="${proxy_answer:-3128}"
    read -r -p "Enter Squid intercept port [3129]: " intercept_answer
    intercept_answer="${intercept_answer:-3129}"
    local port_answer
    for port_answer in "$proxy_answer" "$intercept_answer"; do
        if ! [[ "$port_answer" =~ $UH_UINT ]] || [ "${#port_answer}" -gt 5 ] || [ "$port_answer" -lt 1 ] || [ "$port_answer" -gt 65535 ]; then
            return 1
        fi
    done
    if [[ "$proxy_answer" == "$intercept_answer" ]]; then
        return 1
    fi
    PORTNEW="$proxy_answer"
    INTERCEPT_PORTNEW="$intercept_answer"
    info "Squid proxy port: $PORTNEW"
    info "Squid intercept port: $INTERCEPT_PORTNEW"
}

apply_squid_ports() {
    find "$gp_path/conf" "$gp_path/scr" -type f -print0 | xargs -0 -I "{}" sed -i \
        -e 's:3128:__GATEPROXY_SQUID_PROXY_PORT__:g' \
        -e 's:3129:__GATEPROXY_SQUID_INTERCEPT_PORT__:g' \
        -e "s:__GATEPROXY_SQUID_PROXY_PORT__:$PORTNEW:g" \
        -e "s:__GATEPROXY_SQUID_INTERCEPT_PORT__:$INTERCEPT_PORTNEW:g" "{}"
}

PORTNEW=3128
INTERCEPT_PORTNEW=3129

echo -e "\n"
while true; do
    failure_message="cannot read the proxy port answer"
    read -r -p "Server settings:
Mask 255.255.255.0 (CIDR auto), DNS 1.1.1.2 1.0.0.2
Squid proxy port 3128, Squid intercept port 3129
    Do you want to change? (y/n)" answer
    case "$answer" in
    [Yy]*)
        # execute command yes
        failure_message="cannot read server configuration answers"
        is_ask "Do you want to change? Mask 255.255.255.0? (y/n)" "You have entered Mask incorrect" is_mask1
        failure_message="cannot read server configuration answers"
        is_ask "Do you want to change? DNS1 1.1.1.2? (y/n)" "You have entered DNS1 incorrect" is_dns1
        failure_message="cannot read server configuration answers"
        is_ask "Do you want to change? DNS2 1.0.0.2? (y/n)" "You have entered DNS2 incorrect" is_dns2
        failure_message="cannot read server configuration answers"
        is_ask "Change Squid ports [3128/3129]? (y/n) [n]" "Invalid Squid ports: use distinct ports 1-65535 -retry" is_port
        break
        ;;
    [Nn]*|"")
        # execute command no (default on empty ENTER)
        info "Server settings: keep defaults"
        break
        ;;
    *)
        echo
        info "Answer: YES (y) or NO (n)"
        ;;
    esac
done

failure_message="cannot apply Squid ports"
apply_squid_ports

failure_message="cannot calculate the server subnet"
SERV_SUBNET="$(python3 -c "
import ipaddress, sys
print(ipaddress.IPv4Network(f'{sys.argv[1]}/{sys.argv[2]}', strict=False).network_address)
" "$SERVER_IP" "$SERV_MASK")" || { failure_status=$?; report_failure; exit "$failure_status"; }
info "Localnet: $SERV_SUBNET (from Server IP and Netmask)"

if [ "$SERV_SUBNET" != "192.168.0.0" ]; then
    find "$gp_path/conf" -type f -print0 | xargs -0 -I "{}" sed -i "s:192.168.0.0:$SERV_SUBNET:g" "{}"
    failure_message="cannot edit wpad.pac"
    sed -i "s:192\.168\.0\.\*:$(echo "$SERV_SUBNET" | awk -F '.' '{OFS="."; $4="*"; print $0}'):g" "$gp_path/conf/wpad/wpad.pac"
fi

# wan_iface and PORTNEW (the proxy port) are substituted into conf/ with sed
# /etc/pydhcp/pydhcp.env below, once pydhcp is installed. SERVER_IP,
# SERV_SUBNET and SERV_MASK are written instead by pydhcp's own pysetup.sh,
# from the values gateproxy passes it via expect -- pydhcp.env is the single
# persistent source of truth these scripts read from. DNSNEW1/2 only feed
# forward.conf (Unbound). iptables.sh reads pydhcp's own SERV_DNS (DNS
# pydhcp hands out via DHCP), INTERFACESv4 (LAN interface) and derives its
# CIDR prefix from SERV_MASK -- no separate gateproxy keys for these,
# so there is nothing to keep in sync by hand.

# ------------------------------------------------------------------------------
# INSTALL
# ------------------------------------------------------------------------------

# NETPLAN
# Apply the selected network interface configuration
echo -e "\n"
log "Applying network configuration..."
find /etc/netplan -maxdepth 1 -type f -name '*.yaml' -not -name '*.yaml.bak' -exec mv -- {} {}.bak \; 2>/dev/null
failure_message="cannot create cloud.cfg.d"
mkdir -p /etc/cloud/cloud.cfg.d
failure_message="cannot write cloud network config"
echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
failure_message="cannot copy 00-networkd.yaml to /etc/netplan"
cp -f "$gp_path/conf/netplan/00-networkd.yaml" /etc/netplan/00-networkd.yaml
failure_message="cannot set owner of 00-networkd.yaml"
chown root:root /etc/netplan/00-networkd.yaml
failure_message="cannot set permissions on 00-networkd.yaml"
chmod 600 /etc/netplan/00-networkd.yaml
if ! netplan generate 2>&1 | tee -a "$log_file"; then
    err "netplan generate failed -abort"
    exit 1
fi
if ! netplan apply 2>&1 | tee -a "$log_file"; then
    err "netplan apply failed -abort"
    exit 1
fi

log "Waiting for $LAN_IF to come up with $SERVER_IP..."
NETPLAN_WAIT=0
NETPLAN_WAIT_LIMIT=30
until ip -4 addr show "$LAN_IF" 2>/dev/null | grep -qF "inet $SERVER_IP/"; do
    if [ "$NETPLAN_WAIT" -ge "$NETPLAN_WAIT_LIMIT" ]; then
        err "$LAN_IF: expected IP $SERVER_IP"
        err "$LAN_IF: expected IP not assigned -abort"
        exit 1
    fi
    failure_message="cannot wait before the next attempt"
    sleep 2
    NETPLAN_WAIT=$((NETPLAN_WAIT + 1))
done
info "Network OK: $LAN_IF has $SERVER_IP"

failure_message="cannot remove extra IPs from $LAN_IF"
ip -4 -o addr show dev "$LAN_IF" | awk '{print $4}' | while read -r extra_addr; do
    if [ "${extra_addr%%/*}" != "$SERVER_IP" ]; then
        failure_message="cannot read the network interface addresses"
        ip addr del "$extra_addr" dev "$LAN_IF" 2>/dev/null \
            && warn "removed $extra_addr from $LAN_IF -alert"
    fi
done

# AVAHI
# Configure the local Avahi daemon
avahi_conf="/etc/avahi/avahi-daemon.conf"
if command -v avahi-daemon &>/dev/null && [ -f "$avahi_conf" ]; then
    log "Restricting avahi-daemon to $LAN_IF..."
    failure_message="cannot edit avahi-daemon.conf"
    sed -i "s/^use-ipv6=yes/use-ipv6=no/" "$avahi_conf"
    failure_message="cannot edit avahi-daemon.conf"
    sed -i "s/^#allow-interfaces=.*/allow-interfaces=$LAN_IF/" "$avahi_conf"
    systemctl restart avahi-daemon &>/dev/null || warn "avahi-daemon restart failed -alert"
fi

# ESSENTIAL
# Install the supporting system packages
echo -e "\n"
log "Essential Packages..."
# DISK & STORAGE MANAGEMENT
# Install disk and storage management packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y --no-install-recommends smartmontools

# FILE SYSTEMS SUPPORT
# Install file system support packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y nfs-common ntfs-3g xfsprogs jfsutils dosfstools e2fsprogs hfsprogs hfsutils hfsplus mtools nilfs-tools f2fs-tools exfat-fuse

# FUSE & VIRTUAL FILE SYSTEMS
# Install FUSE and virtual file system packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y libfuse2t64 gvfs-fuse bindfs sshfs go-mtpfs

# VOLUME & QUOTA MANAGEMENT
# Install volume and quota management packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y lvm2 quota attr
failure_message="cannot install packages with nala"
retry_cmd nala install -y udisks2 udisks2-btrfs udisks2-lvm2

# SYSTEM UTILITIES & MONITORING
# Install system utilities and monitoring packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y trash-cli pm-utils btop htop lsof inotify-tools dmidecode pv tree moreutils preload debconf-utils mokutil util-linux linux-tools-common apparmor-utils

# PACKAGE MANAGEMENT TOOLS
# Install package management tools
failure_message="cannot install packages with nala"
retry_cmd nala install -y dpkg ppa-purge apt-utils

# TEXT & FILE UTILITIES
# Install text and file utilities
failure_message="cannot install packages with nala"
retry_cmd nala install -y rename renameutils sharutils dos2unix colordiff ripgrep yamllint

# LOGGING & SYSTEM SERVICES
# Install logging and system service packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y finger logrotate

# DRIVERS & KERNEL MODULES
# Install driver and kernel module packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y linux-firmware linux-headers-$(uname -r) module-assistant

# DEVELOPMENT: COMPILERS & BUILD TOOLS
# Install compilers and build tools
failure_message="cannot install packages with nala"
retry_cmd nala install -y build-essential autoconf autoconf-archive autogen automake dh-autoreconf pkg-config

# DEVELOPMENT: LIBRARIES & HEADERS
# Install development libraries and headers
failure_message="cannot install packages with nala"
retry_cmd nala install -y uuid-dev libmnl-dev libssl-dev libffi-dev libpam0g-dev libpcap-dev libasound2-dev libglib2.0-dev libudisks2-dev liblvm2-dev python3-dev

# PROGRAMMING: PYTHON
# Install Python runtime and development packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y python3-pip python3-venv python3-psutil

# PROGRAMMING: RUBY
# Install Ruby runtime packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y rubygems-integration rake ruby ruby-did-you-mean ruby-json ruby-minitest ruby-net-telnet ruby-power-assert ruby-test-unit

# PROGRAMMING: JAVASCRIPT & WEB
# Install JavaScript and web development packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y javascript-common libjs-jquery xsltproc

# NETWORK DEPENDENCIES
# Install network utilities used by the server
failure_message="cannot install packages with nala"
retry_cmd nala install -y bind9-dnsutils conntrack i2c-tools wsdd ipset arptables ebtables

# GEOLOCATION DATABASES
# Install the geolocation databases
failure_message="cannot install packages with nala"
retry_cmd nala install -y geoip-database

# GRAPHICS & DISPLAY
# if there any problems, install the package: libegl-mesa0
failure_message="cannot install packages with nala"
retry_cmd nala install -y libfontconfig1

# RUNTIME LIBRARIES
# Install the required runtime libraries
failure_message="cannot install packages with nala"
retry_cmd nala install -y libuser gir1.2-gtop-2.0

# MAIL
# Stop the existing mail service before configuring mail packages
service sendmail stop &>/dev/null || true
update-rc.d -f sendmail remove &>/dev/null || true
failure_message="cannot install packages with nala"
DEBIAN_FRONTEND=noninteractive retry_cmd nala install -y postfix
failure_message="cannot install packages with nala"
retry_cmd nala install -y mailutils

# FONTS
# Install the server font packages
failure_message="cannot install packages with nala"
retry_cmd nala install -y fonts-lato fonts-liberation fonts-dejavu
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
failure_message="cannot install packages with nala"
retry_cmd nala install -y ttf-mscorefonts-installer fontconfig
failure_message="cannot update the font cache"
fc-cache -f

failure_message="cannot wait before the next attempt"
sleep 1

failure_message="cannot update system packages"
upgrade

# SETUP
# Prepare the application installation directories
echo -e "\n"
log "Gateproxy Packages..."
if grep -qFw "$HOSTNAME" /etc/hosts 2>/dev/null; then
    info "$HOSTNAME already resolves in /etc/hosts -skip"
elif grep -q "^127\.0\.1\.1" /etc/hosts; then
    failure_message="cannot edit hosts"
    sed -i "/^127\.0\.1\.1/a $SERVER_IP\t$HOSTNAME" /etc/hosts
else
    info "/etc/hosts missing 127.0.1.1, appending hostname entry"
    failure_message="cannot write hosts"
    printf '%s\t%s\n' "$SERVER_IP" "$HOSTNAME" >> /etc/hosts
fi
failure_message="cannot edit hosts"
sed -i '/^\s*\(fe00::\|ff00::\|ff02::\)/ s/^/#/' /etc/hosts
failure_message="cannot write hosts"
grep -q "ipv6.msftncsi.com" /etc/hosts || echo "$SERVER_IP ipv6.msftncsi.com ipv6.msftconnecttest.com" | tee -a /etc/hosts >/dev/null

# ACLs SECTION
acl_mac_path="$ACL_PATH/mac"
acl_squid_path="$ACL_PATH/squid"
acl_ipt_path="$ACL_PATH/ipt"
# Only files missing in $ACL_PATH are copied from the repo template -- never
# overwrite one that already exists, since it may hold real data from a
# previous install, from pydhcp (mac-*.txt is also seeded by pydhcp's own
# pysetup.sh), or edited by hand.
while IFS= read -r -d '' acl_src; do
    acl_dest="$ACL_PATH/${acl_src#"$gp_path"/acl/}"
    if [ ! -f "$acl_dest" ]; then
        failure_message="cannot create the ACL destination directory"
        mkdir -p "$(dirname "$acl_dest")"
        failure_message="cannot copy $(basename "$acl_dest")"
        cp "$acl_src" "$acl_dest"
    fi
done < <(find "$gp_path/acl" -type f -print0)
# MAC ACL files
failure_message="cannot set permissions on MAC ACL files"
chmod 600 "$acl_mac_path"/mac-*.txt
failure_message="cannot set owner of MAC ACL files"
chown root:root "$acl_mac_path"/mac-*.txt
# Squid ACL files
failure_message="cannot set permissions on Squid ACL files"
chmod 644 "$acl_squid_path"/*.txt
failure_message="cannot set owner of Squid ACL files"
chown root:root "$acl_squid_path"/*.txt
# IPTables ACL files
failure_message="cannot set permissions on firewall ACL files"
chmod 644 "$acl_ipt_path"/*.txt
failure_message="cannot set owner of firewall ACL files"
chown root:root "$acl_ipt_path"/*.txt

# DNS
# Install and configure the DNS resolver
failure_message="cannot install packages with nala"
retry_cmd nala install -y unbound
failure_message="cannot copy Unbound forward.conf"
cp -f "$gp_path/conf/unbound/forward.conf" /etc/unbound/unbound.conf.d/forward.conf
failure_message="cannot write Unbound daemon settings"
tee /etc/default/unbound >/dev/null <<'EOF'
DAEMON_OPTS=""
EOF
unbound-checkconf || warn "unbound config check failed -alert"
failure_message="cannot reload systemd configuration"
systemctl daemon-reload
failure_message="cannot enable unbound"
systemctl enable --now unbound

# PHP
# Download the PHP configuration installer
failure_message="cannot download $(basename "${download_url%%\?*}")"
retry_cmd nala install -y php libapache2-mod-php php-cli php-curl php-sqlite3

# Detect PHP version
if command -v php &>/dev/null; then
    failure_message="cannot read the PHP version"
    PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null) || { failure_status=$?; report_failure; exit "$failure_status"; }
    info "PHP version detected: $PHP_VERSION"
else
    err "PHP not installed -abort"
    exit 1
fi

# Ensure php.ini exists for Apache
if [ ! -f /etc/php/$PHP_VERSION/apache2/php.ini ]; then
    if [ -f /etc/php/$PHP_VERSION/cli/php.ini ]; then
        failure_message="cannot create the Apache PHP directory"
        mkdir -p /etc/php/$PHP_VERSION/apache2
        failure_message="cannot copy Apache php.ini"
        cp /etc/php/$PHP_VERSION/cli/php.ini /etc/php/$PHP_VERSION/apache2/php.ini
        info "php.ini copied to /etc/php/$PHP_VERSION/apache2/"
    else
        err "php.ini not found -abort"
        exit 1
    fi
fi

cp -f /etc/php/$PHP_VERSION/apache2/php.ini{,.bak} &>/dev/null || true
failure_message="cannot edit Apache php.ini"
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
failure_message="cannot install packages with nala"
retry_cmd nala install -y apache2 apache2-doc apache2-utils apache2-dev \
                apache2-suexec-pristine libaprutil1t64 libaprutil1-dev \
                libtest-fatal-perl
failure_message="cannot enable apache2.service"
systemctl enable apache2.service
#nala install -y libapache2-mod-dnssd
failure_message="cannot install packages with apt"
retry_cmd apt -qq install -y --reinstall apache2-doc
failure_message="cannot update system packages"
upgrade
cp -f /etc/apache2/ports.conf{,.bak} &>/dev/null || true

cp -f /etc/apache2/mods-available/mpm_prefork.conf{,.bak} &>/dev/null || true
failure_message="cannot edit mpm_prefork.conf"
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
while pgrep -x squid > /dev/null; do
    failure_message="cannot stop Squid processes"
    killall -s SIGTERM squid &>/dev/null
    failure_message="cannot wait before the next attempt"
    sleep 5
done
failure_message="cannot remove old Squid files"
rm -rf /var/spool/squid* /var/log/squid* /etc/squid &>/dev/null
failure_message="cannot remove squid.pid"
rm -f /run/squid.pid &>/dev/null
#DEBIAN_FRONTEND=noninteractive nala install -y --no-install-recommends squid-openssl
failure_message="cannot install packages with nala"
retry_cmd nala install -y squid-openssl squid-langpack squid-common
failure_message="cannot update system packages"
upgrade
failure_message="cannot create Squid log files"
mkdir -p /var/log/squid &>/dev/null
failure_message="cannot create Squid log files"
touch /var/log/squid/{access,cache,store,deny}.log &>/dev/null
failure_message="cannot set owner of Squid log files"
chown proxy:proxy /var/log/squid/*.log
failure_message="cannot set permissions on Squid log files"
chmod 640 /var/log/squid/*.log
for cache_type in rock ufs; do
    failure_message="cannot create Squid cache directories"
    mkdir -p /var/spool/squid/${cache_type} 2>/dev/null
done
failure_message="cannot set owner of Squid cache directories"
chown -R proxy:proxy /var/spool/squid
failure_message="cannot set permissions on Squid cache directories"
chmod -R 700 /var/spool/squid
failure_message="cannot add www-data to the proxy group"
usermod -aG proxy www-data
failure_message="cannot enable squid.service"
systemctl enable squid.service
systemctl stop squid.service &>/dev/null || true
failure_message="cannot initialize Squid cache directories"
squid -z
cp -f /etc/logrotate.d/squid{,.bak} &>/dev/null || true
failure_message="cannot edit Squid logrotate settings"
sed -i '/sharedscripts/a \    create 0644 proxy proxy' /etc/logrotate.d/squid
failure_message="cannot edit Squid logrotate settings"
sed -i 's/rotate 2/rotate 7/' /etc/logrotate.d/squid
failure_message="cannot edit Squid logrotate settings"
sed -i -E 's/^	(daily|monthly)$/	weekly/' /etc/logrotate.d/squid
# Let's Encrypt certificate for client to Squid proxy encryption (Optional)
#nala install -y certbot python3-certbot-apache

# ADMIN SECTION
# webmin
# https://www.maravento.com/2019/06/instalar-modulo-webmin-por-linea-de.html
download_url="https://raw.githubusercontent.com/webmin/webmin/master/setup-repos.sh"
failure_message="cannot download $(basename "${download_url%%\?*}")"
retry_cmd curl -o setup-repos.sh "$download_url"
log "SAVED: setup-repos.sh"
download_url=""
failure_message="cannot set permissions on setup-repos.sh"
chmod +x setup-repos.sh
echo "y" | ./setup-repos.sh
failure_message="cannot update system packages"
upgrade
failure_message="cannot install packages with nala"
retry_cmd nala install -y webmin
failure_message="cannot update system packages"
upgrade
systemctl enable webmin.service 2>/dev/null || true
info "Webmin Access: https://localhost:10000"
failure_message="cannot remove setup-repos.sh"
rm -f setup-repos.sh

# webmin modules
# Text Editor | Service Monitor | Netplan Manager
systemctl stop webmin.service 2>/dev/null || true
/usr/share/webmin/install-module.pl "$gp_path/conf/webmin/text-editor.wbm" || warn "text-editor module install failed -alert"
find "$acl_mac_path" -maxdepth 1 -type f | tee /etc/webmin/text-editor/files &>/dev/null || true
# List of modules to install
for module in servicemon netplanmgr; do
    log "Installing $module module..."
    if wget -q -O "$gp_path/${module}.sh" --timeout=15 --tries=1 "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/${module}.sh"; then
        log "SAVED: ${module}.sh"
        failure_message="cannot set permissions on ${module}.sh"
        chmod +x "$gp_path/${module}.sh"
        "$gp_path/${module}.sh" --install || warn "$module module install failed -alert"
        failure_message="cannot remove ${module}.sh"
        rm -f "$gp_path/${module}.sh"
    else
        log "PARTIAL: https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/${module}.sh"
    fi
done

# Proxy Monitor
failure_message="cannot install packages with nala"
retry_cmd nala install -y rsync nbtscan libcgi-session-perl libgd-perl sarg
if (cd "$gp_path" && git clone https://github.com/maravento/proxymon); then
    if cd "$gp_path/proxymon"; then
        if [ -f pmsetup.sh ]; then
            failure_message="cannot set permissions on pmsetup.sh"
            chmod +x pmsetup.sh
            if PROXYMON_LAN="$LAN_IF" PROXYMON_SERVER_IP="$SERVER_IP" \
                PROXYMON_SQUID_MGR_PORT="${PORTNEW:-3128}" \
                PROXYMON_SQUID_INTERCEPT_PORT="$INTERCEPT_PORTNEW" ./pmsetup.sh --install; then
                info "Sent to proxymon: SERVER_IP=$SERVER_IP lan_interface=$LAN_IF"
            else
                warn "pmsetup.sh install failed -alert"
            fi
        else
            warn "pmsetup.sh not found in proxymon repo -alert"
        fi
        dump_module_log "$gp_path/proxymon/pmsetup.log" "proxymon"
        failure_message="cannot enter the Gateproxy directory"
        cd "$gp_path"
    else
        warn "cannot enter proxymon directory -alert"
    fi
else
    warn "cannot clone proxymon -alert"
fi

echo -e "\n"
log "WPAD Config..."

# pysetup.sh below probes http://SERVER_IP:18100/wpad.pac to decide whether to
# announce DHCP option 252. The PAC must already be served when it runs, so
# this block goes before pydhcp and reloads apache2 to apply the new Listen.
failure_message="cannot create wpad"
mkdir -p /var/www/wpad
failure_message="cannot set owner of wpad"
chown www-data:www-data /var/www/wpad
failure_message="cannot copy wpad.pac"
cp -f "$gp_path/conf/wpad/wpad.pac" /var/www/wpad/wpad.pac
failure_message="cannot set owner of wpad.pac"
chown www-data:www-data /var/www/wpad/wpad.pac
failure_message="cannot set permissions on wpad.pac"
chmod 644 /var/www/wpad/wpad.pac
failure_message="cannot copy wpad.conf"
cp -f "$gp_path/conf/wpad/wpad.conf" /etc/apache2/sites-available/wpad.conf
failure_message="cannot set permissions on wpad.conf"
chmod 644 /etc/apache2/sites-available/wpad.conf
failure_message="cannot enable the wpad.conf Apache site"
a2ensite -q wpad.conf
failure_message="cannot write Apache ports.conf"
grep -qxF "Listen $SERVER_IP:18100" /etc/apache2/ports.conf || grep -qxF 'Listen 18100' /etc/apache2/ports.conf || echo "Listen $SERVER_IP:18100" >> /etc/apache2/ports.conf
apachectl -t -D DUMP_INCLUDES -S || true
systemctl reload apache2 || warn "cannot reload apache2, WPAD not served -alert"
info "WPAD-PAC: http://$SERVER_IP:18100/wpad.pac"
failure_message="cannot wait before the next attempt"
sleep 1

echo -e "\n"
# DHCP SECTION
# pydhcp
log "Installing pydhcp..."

if (cd "$gp_path" && git clone https://github.com/maravento/pydhcp); then
    pydhcp_path="$gp_path/pydhcp"

    if [ -d "$pydhcp_path" ]; then
        if cd "$pydhcp_path"; then
            failure_message="cannot create the pydhcp answer script"
            PYDHCP_EXPECT=$(mktemp) || { failure_status=$?; report_failure; exit "$failure_status"; }
            failure_message="cannot write the pydhcp answer script"
            cat > "$PYDHCP_EXPECT" <<EOF
spawn env PYDHCP_WAN_IFACE=$wan_iface bash pysetup.sh --install
expect -re {\[([0-9]+)\][ \t]+$LAN_IF[ \t(]}
send "\$expect_out(1,string)\r"
expect "Enter netmask"
send "$SERV_MASK\r"
expect "Enter pool start"
send "\r"
expect "Enter pool end"
send "\r"
expect "Enter DNS server"
send "$SERVER_IP\r"
expect "DHCP pool lease cleanup interval"
send "\r"
expect eof
catch wait result
exit [lindex \$result 3]
EOF
            expect -f "$PYDHCP_EXPECT" || warn "pydhcp install failed -alert"
            failure_message="cannot remove the pydhcp answer script"
            rm -f "$PYDHCP_EXPECT"
            dump_module_log "$pydhcp_path/pysetup.log" "pydhcp"

            failure_message="cannot enter the Gateproxy directory"
            cd "$gp_path"
            info "DHCP pool: 220-235; change it in pydhcp.env"
            info "DHCP clients will use $SERVER_IP (unbound) as DNS"

        else
            warn "cannot enter pydhcp directory -alert"
        fi
    else
        warn "pydhcp directory not found -alert"
    fi
else
    warn "cannot clone pydhcp -alert"
fi

# LOGS SECTION
# ulog2
# https://www.maravento.com/2014/07/registros-iptables.html
failure_message="cannot set owner of /var/log"
chown root:root /var/log
failure_message="cannot install packages with nala"
retry_cmd nala install -y ulogd2
failure_message="cannot create ulog"
mkdir -p /var/log/ulog &>/dev/null
failure_message="cannot create syslogemu.log"
touch /var/log/ulog/syslogemu.log &>/dev/null
failure_message="cannot add the local user to the ulog group"
usermod -a -G ulog "$local_user"
info "Ulog Access: /var/log/ulog/syslogemu.log"
# rsyslog
# in case fails: nala install -y libfastjson4
failure_message="cannot install packages with nala"
retry_cmd nala install -y rsyslog
failure_message="cannot enable rsyslog.service"
systemctl enable rsyslog.service

# BACKUP SECTION
# Timeshift
failure_message="cannot install packages with nala"
retry_cmd nala install -y timeshift
# FreeFileSync
failure_message="cannot install packages with nala"
retry_cmd nala install -y libatk-adaptor libgail-common
download_url="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/ffsupdate.sh"
failure_message="cannot download $(basename "${download_url%%\?*}")"
retry_cmd wget -O "$gp_path/scr/ffsupdate.sh" --timeout=15 --tries=1 "$download_url"
log "SAVED: ffsupdate.sh"
download_url=""
failure_message="cannot set permissions on ffsupdate.sh"
chmod +x "$gp_path/scr/ffsupdate.sh"
"$gp_path/scr/ffsupdate.sh" || warn "ffsupdate failed; FreeFileSync absent -alert"
failure_message="cannot update the project cron file"
cron_d_set "/etc/scr/ffsupdate.sh" "@weekly root /etc/scr/ffsupdate.sh"
failure_message="cannot wait before the next attempt"
sleep 1

# NET TOOLS
# Net Tools (Replace NIC and IP/CIDR)
failure_message="cannot install packages with nala"
retry_cmd nala install -y iw                 # Wireless tools: iwconfig, iwlist, iwpriv
failure_message="cannot install packages with nala"
retry_cmd nala install -y fping              # Net diagnostics: fping -a -g 192.168.0.0/24
failure_message="cannot install packages with nala"
retry_cmd nala install -y ethtool            # Net config: ethtool eth0
# Net test: On server: iperf3 -s | On client: iperf3 -c SERVER_IP
failure_message="cannot install packages with nala"
DEBIAN_FRONTEND=noninteractive retry_cmd nala install -y iperf3  2>/dev/null
# Net Scanning (Replace NIC and IP/CIDR)
failure_message="cannot install packages with nala"
retry_cmd nala install -y masscan            # masscan --ports 0-65535 192.168.0.0/16
failure_message="cannot install packages with nala"
retry_cmd nala install -y nast               # nast -m
failure_message="cannot install packages with nala"
retry_cmd nala install -y arp-scan           # arp-scan --localnet
failure_message="cannot install packages with nala"
retry_cmd nala install -y arping             # arping -I eth0 192.168.0.10
failure_message="cannot install packages with nala"
retry_cmd nala install -y netdiscover        # netdiscover
# Nmap
failure_message="cannot install packages with nala"
retry_cmd nala install -y nmap python3-nmap ndiff
# Domain/IP Scanning
failure_message="cannot install packages with nala"
retry_cmd nala install -y traceroute         # traceroute google.com
failure_message="cannot install packages with nala"
retry_cmd nala install -y mtr-tiny           # mtr google.com

# SECURITY SECTION
# fail2ban
failure_message="cannot install packages with nala"
retry_cmd nala install -y fail2ban
failure_message="cannot copy jail.local"
cp "$gp_path/conf/fail2ban/jail.local" /etc/fail2ban/jail.local
failure_message="cannot edit fail2ban.conf"
sed -i 's/^#\?allowipv6 *= *.*/allowipv6 = 0/' /etc/fail2ban/fail2ban.conf
failure_message="cannot enable fail2ban.service"
systemctl enable fail2ban.service
info "Check: sudo fail2ban-client status <jail_name>"
info "Unban all: sudo fail2ban-client unban --all"
info "Unban: fail2ban-client set <jail> unban --all"
# ttyd (web terminal)
failure_message="cannot install packages with nala"
retry_cmd nala install -y ttyd
failure_message="cannot copy ttyd.service"
cp -f "$gp_path/conf/ttyd/ttyd.service" /etc/systemd/system/ttyd.service
failure_message="cannot reload systemd configuration"
systemctl daemon-reload
failure_message="cannot enable ttyd.service"
systemctl enable ttyd.service
info "ttyd Access: http://localhost:7681"
# suricata install
systemctl mask suricata.service &>/dev/null || true
failure_message="cannot install packages with nala"
retry_cmd nala install -y suricata suricata-update jq
failure_message="cannot edit suricata.yaml"
sed -i "s/interface: eth[0-9]/interface: $LAN_IF/g" /etc/suricata/suricata.yaml
systemctl unmask suricata.service &>/dev/null || true
if grep -q "community-id: false" /etc/suricata/suricata.yaml; then
    failure_message="cannot edit suricata.yaml"
    sed -i 's/community-id: false/community-id: true/' /etc/suricata/suricata.yaml
    info "OK: Community-ID enabled"
fi
# suricata disable and drop
failure_message="cannot copy Suricata drop and disable rules"
cp -f "$gp_path/conf/suricata/"{disable,drop}.conf /etc/suricata/
failure_message="cannot set owner of Suricata rule files"
chown root:root /etc/suricata/{disable,drop}.conf
failure_message="cannot set permissions on Suricata rule files"
chmod 644 /etc/suricata/{disable,drop}.conf
# suricata update & clean
if [ ! -f /var/log/suricata/suricatacron.log ]; then
    failure_message="cannot create suricatacron.log"
    touch /var/log/suricata/suricatacron.log
    failure_message="cannot set owner of suricatacron.log"
    chown root:root /var/log/suricata/suricatacron.log
    failure_message="cannot set permissions on suricatacron.log"
    chmod 640 /var/log/suricata/suricatacron.log
fi
failure_message="cannot copy Suricata scripts"
cp -f "$gp_path/conf/suricata/"{suricataupdate,suricataclean,suridata}.sh /etc/suricata/
failure_message="cannot set permissions on Suricata scripts"
chmod +x /etc/suricata/{suricataupdate,suricataclean,suridata}.sh
# suricata ratio
if ! grep -q "detect-thread-ratio: 0.5" /etc/suricata/suricata.yaml; then
    failure_message="cannot edit suricata.yaml"
    sed -i 's/detect-thread-ratio: 1.0/detect-thread-ratio: 0.5/' /etc/suricata/suricata.yaml
fi
# suricata cron
failure_message="cannot update the project cron file"
cron_d_set "/etc/suricata/suricataupdate.sh" "0 2 * * * root /etc/suricata/suricataupdate.sh >/dev/null 2>&1"
failure_message="cannot update the project cron file"
cron_d_set "/etc/suricata/suricataclean.sh" "@monthly root /etc/suricata/suricataclean.sh >/dev/null 2>&1"
failure_message="cannot update the project cron file"
cron_d_set "/etc/suricata/suridata.sh" "*/5 * * * * root /etc/suricata/suridata.sh >/dev/null 2>&1"
# suricata check IDS
SURICATA_SERVICE="/usr/lib/systemd/system/suricata.service"
CORRECT_EXECSTART="ExecStart=/usr/bin/suricata -D --af-packet -c /etc/suricata/suricata.yaml --pidfile /run/suricata.pid"
if grep -q "^ExecStart=.*--af-packet" "$SURICATA_SERVICE" && ! grep -q "^ExecStart=.*-q" "$SURICATA_SERVICE"; then
    info "OK: Suricata Mode: IDS"
else
    log "Fixing Suricata IDS..."
    failure_message="cannot edit Suricata service settings"
    sed -i "s|^ExecStart=.*|$CORRECT_EXECSTART|" "$SURICATA_SERVICE"
    info "Suricata Mode: IDS"
fi
# evebox
failure_message="cannot create APT keyrings"
mkdir -p /etc/apt/keyrings
download_url="https://evebox.org/files/GPG-KEY-evebox"
failure_message="cannot download $(basename "${download_url%%\?*}")"
retry_cmd curl -fsSL "$download_url" -o /etc/apt/keyrings/evebox.asc
log "SAVED: evebox.asc"
download_url=""
failure_message="cannot write APT keyrings"
echo "deb [signed-by=/etc/apt/keyrings/evebox.asc] https://evebox.org/files/debian stable main" | tee /etc/apt/sources.list.d/evebox.list
failure_message="cannot update system packages"
upgrade
failure_message="cannot install packages with nala"
retry_cmd nala install -y evebox
# Configure
failure_message="cannot copy evebox.yaml"
cp -f "$gp_path/conf/evebox/evebox.yaml" /etc/evebox/evebox.yaml
failure_message="cannot copy evebox.service"
cp -f "$gp_path/conf/evebox/evebox.service" /etc/systemd/system/evebox.service
failure_message="cannot reload systemd configuration"
systemctl daemon-reload
failure_message="cannot enable suricata evebox"
systemctl enable suricata evebox
info "EVEBox: http://localhost:5636"

# OPTIONAL PACK
# Offer the optional desktop package installation
echo -e "\n"
while true; do
    failure_message="cannot read the optional package answer"
    read -r -p "Do you want to install Optional GTK Pack?
mesa-utils, lynis, gparted, gnome-disk-utility, qdirstat, baobab,
gsmartcontrol, cpu-x, synaptic, gdebi, gtkhash, wmctrl, fsearch  (y/n)" answer
    case "$answer" in
    [Yy]*)
        # execute command yes
        info "Optional GTK Pack: YES"
        # gtk
        failure_message="cannot install packages with nala"
        retry_cmd nala install -y --no-install-recommends gsmartcontrol
        failure_message="cannot install packages with nala"
        retry_cmd nala install -y gparted gnome-disk-utility qdirstat baobab cpu-x synaptic gdebi gtkhash wmctrl mesa-utils
        # lynis
        failure_message="cannot install packages with nala"
        retry_cmd nala install -y lynis
        info "Lynis Run: lynis -c -Q and log: /var/log/lynis.log"
        # fsearch
        add-apt-repository -y ppa:christian-boxdoerfer/fsearch-stable || true
        failure_message="cannot update system packages"
        upgrade
        nala install -y fsearch || true
        break
        ;;
    [Nn]*|"")
        # execute command no (default on empty ENTER)
        info "Optional GTK Pack: NO"
        break
        ;;
    *)
        echo
        info "Answer: YES (y) or NO (n)"
        ;;
    esac
done

failure_message="cannot update system packages"
upgrade

# SHARED ###
# Samba with Shared folder, Recycle Bin and Audit
echo -e "\n"
while true; do
    failure_message="cannot read the Samba installation answer"
    read -r -p "Do you want to install Samba?
with SHARED folder, Recycle Bin and Audit (y/n)" answer

    case "$answer" in
    [Yy]*)
        info "Samba (smbstack): YES"
        if (cd "$gp_path" && git clone https://github.com/maravento/smbstack); then
            smbstack_path="$gp_path/smbstack"

            if [ -d "$smbstack_path" ]; then
                if cd "$smbstack_path"; then
                    if SMBSTACK_IFACE="$LAN_IF" bash smbsetup.sh --install; then
                        info "smbstack installed OK"
                    else
                        warn "smbsetup.sh --install failed -alert"
                    fi
                    dump_module_log "$smbstack_path/smbsetup.log" "smbstack"
                    failure_message="cannot enter the Gateproxy directory"
                    cd "$gp_path"
                else
                    warn "cannot enter smbstack directory -alert"
                fi
            else
                warn "smbstack directory not found -alert"
            fi
        else
            warn "cannot clone smbstack -alert"
        fi
        break
        ;;

    [Nn]*|"")
        # default on empty ENTER
        info "Samba (smbstack): NO"
        break
        ;;

    *)
        echo
        info "Answer: YES (y) or NO (n)"
        ;;
    esac
done

failure_message="cannot update system packages"
upgrade

# UHM ###
# UniFi Hotspot Manager (optional, requires pydhcp already installed above).
# Only prompted if a local UniFi Network controller is actually detected --
# classic (dpkg package "unifi") or unifi-os (/var/lib/uosserver, podman-based).
# gateproxy does not install UniFi/podman itself. To install UniFi Network
# self-hosted / UniFi OS Server first, use unifisetup.sh:
# https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/unifisetup.sh
echo -e "\n"
UNIFI_DETECTED_TYPE=""
if dpkg-query -W -f='${Version}' unifi >/dev/null 2>&1; then
    UNIFI_DETECTED_TYPE="classic"
elif [ -f /var/lib/uosserver/server.conf ]; then
    UNIFI_DETECTED_TYPE="unifi-os"
fi

if [ -n "$UNIFI_DETECTED_TYPE" ]; then
    info "UniFi Network controller detected ($UNIFI_DETECTED_TYPE)"
    while true; do
        failure_message="cannot read the UHM installation answer"
        read -r -p "Se ha detectado UniFi ($UNIFI_DETECTED_TYPE). Desea instalar UniFi Hotspot Manager (uhm)? (y/n)" answer

        case "$answer" in
        [Yy]*)
            info "UniFi Hotspot Manager (uhm): YES"
            if (cd "$gp_path" && git clone https://github.com/maravento/uhm); then
                uhm_path="$gp_path/uhm"

                if [ -d "$uhm_path" ]; then
                    if cd "$uhm_path"; then
                        log "Launching uhm installer (interactive)..."
                        if bash uhmsetup.sh; then
                            info "uhm installed OK"
                        else
                            warn "uhmsetup.sh failed -alert"
                        fi
                        dump_module_log "$uhm_path/uhmsetup.log" "uhm"
                        failure_message="cannot enter the Gateproxy directory"
                        cd "$gp_path"
                    else
                        warn "cannot enter uhm directory -alert"
                    fi
                else
                    warn "uhm directory not found -alert"
                fi
            else
                warn "cannot clone uhm -alert"
            fi
            break
            ;;

        [Nn]*|"")
            # default on empty ENTER
            info "UniFi Hotspot Manager (uhm): NO"
            break
            ;;

        *)
            echo
            info "Answer: YES (y) or NO (n)"
            ;;
        esac
    done
else
    info "No UniFi Network/OS controller; skipping UHM prompt"
    info "Install self-hosted UniFi Network or OS Server first:"
    info "use unifisetup.sh (check README)"
fi

failure_message="cannot update system packages"
upgrade

# ACLs ###
echo -e "\n"
# Allow IP
get_acl https://raw.githubusercontent.com/maravento/blackip/master/bipupdate/lst/allowip.txt "$ACL_PATH/squid/allowip.txt" || true
if [ ! -s "$ACL_PATH/squid/allowip.txt" ]; then
    warn "allowip.txt is empty -alert"
fi

# Block TLDs
get_acl https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/blocktlds.txt "$ACL_PATH/squid/blocktlds.txt" || true
if [ ! -s "$ACL_PATH/squid/blocktlds.txt" ]; then
    info "blocktlds.txt is empty, ACL disabled in squid.conf"
    failure_message="cannot edit squid.conf"
    sed -i '/^acl blocktlds /s/^/#/; /^http_access deny workdays blocktlds/s/^/#/' "$gp_path/conf/squid/squid.conf"
fi

# Ransomware Extensions (Squid, optional)
get_acl https://raw.githubusercontent.com/maravento/blackweb/master/fpack/rw/rwext.txt "$ACL_PATH/squid/rwext.txt" || true
if [ ! -s "$ACL_PATH/squid/rwext.txt" ]; then
    warn "rwext.txt is empty -alert"
fi

# Bad User-Agents (Squid, optional)
get_acl https://raw.githubusercontent.com/maravento/blackweb/master/fpack/ua/blockua.txt "$ACL_PATH/squid/blockua.txt" || true
if [ ! -s "$ACL_PATH/squid/blockua.txt" ]; then
    warn "blockua.txt is empty -alert"
fi

# Web3 Domains/TLDs (Squid, optional)
get_acl https://raw.githubusercontent.com/maravento/blackweb/master/fpack/web3/web3domains.txt "$ACL_PATH/squid/web3domains.txt" || true
if [ ! -s "$ACL_PATH/squid/web3domains.txt" ]; then
    warn "web3domains.txt is empty -alert"
fi
get_acl https://raw.githubusercontent.com/maravento/blackweb/master/fpack/web3/web3tld.txt "$ACL_PATH/squid/web3tld.txt" || true
if [ ! -s "$ACL_PATH/squid/web3tld.txt" ]; then
    warn "web3tld.txt is empty -alert"
fi

# Blackweb
if (cd "$gp_path" && get_acl https://raw.githubusercontent.com/maravento/blackweb/master/blackweb.tar.gz blackweb.tar.gz && [ -f blackweb.tar.gz ]); then
    (cd "$gp_path" && cat blackweb.tar.gz* | tar xzf -)
    failure_message="cannot copy blackweb.txt"
    cp "$gp_path/blackweb.txt" "$ACL_PATH/squid/blackweb.txt"
else
    warn "blackweb.tar.gz not available -alert"
fi
failure_message="cannot remove blackweb download files"
rm -f "$gp_path"/blackweb.*
failure_message="cannot wait before the next attempt"
sleep 1

# ADD CONFIG ###
echo -e "\n"
log "Applying Config..."
# squid
cp -f /etc/squid/squid.conf{,.bak} &>/dev/null || true
failure_message="cannot copy squid.conf"
cp -f "$gp_path/conf/squid/squid.conf" /etc/squid/squid.conf
failure_message="cannot set owner of squid.conf"
chown root:root /etc/squid/squid.conf
failure_message="cannot set permissions on squid.conf"
chmod 644 /etc/squid/squid.conf
failure_message="cannot restart squid.service"
systemctl restart squid.service
# scripts
# Download external scripts to project scr folder
scripts=(
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackusb/linux/blackusb.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/cleaner.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/filereport.sh"
    "https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/hwclock.sh"
)
for url in "${scripts[@]}"; do
    failure_message="cannot read the downloaded filename"
    fname=$(basename "$url") || { failure_status=$?; report_failure; exit "$failure_status"; }

    if wget -q -O "$gp_path/scr/$fname" --timeout=15 --tries=1 "$url"; then
        log "SAVED: $fname"
    else
        log "PARTIAL: $url"
    fi
done

# scripts
failure_message="cannot copy Gateproxy scripts"
cp -fr "$gp_path/scr/"* "$SCR_PATH"
failure_message="cannot set owner of Gateproxy scripts"
chown -R root:root "$SCR_PATH"/*
find "$SCR_PATH" -name "*.sh" -exec chmod +x {} \;
# Default: leave /tmp and shared-memory mounts unchanged; see README.
# Read-only shared memory is independent of the two /tmp alternatives.
#echo 'none /run/shm tmpfs defaults,ro 0 0' | tee -a /etc/fstab &> /dev/null # Optional
# Choose at most one /tmp recipe before running the installer.
#echo 'tmpfs /tmp tmpfs defaults,size=30%,nofail,noatime,mode=1777 0 0' | tee -a /etc/fstab &> /dev/null # Optional
#failure_message="cannot write fstab"
#grep -qxF 'tmpfs /tmp tmpfs defaults,size=2G,nofail,noatime,mode=1777 0 0' /etc/fstab || \
#    echo 'tmpfs /tmp tmpfs defaults,size=2G,nofail,noatime,mode=1777 0 0' >> /etc/fstab # Optional
failure_message="cannot wait before the next attempt"
sleep 1

echo -e "\n"
log "Proxy Apache Config..."

cp -f /etc/apache2/sites-available/000-default.conf{,.bak} &>/dev/null || true
failure_message="cannot edit 000-default.conf"
sed -i "s_\(#LogLevel info ssl:warn\)_\1\n\tLogLevel warn_" /etc/apache2/sites-available/000-default.conf
# httpoxy (CVE-2016-5387): a client-supplied "Proxy:" header reaches PHP and
# CGI as HTTP_PROXY, and many HTTP libraries obey it. Apache does not strip it
# on its own, and mod_headers is enabled above. This is the only directive
# worth injecting here: everything else apache2 already ships enabled, or it
# only reorders DirectoryIndex.
grep -qE '^[[:space:]]*RequestHeader unset Proxy early[[:space:]]*$' /etc/apache2/sites-available/000-default.conf \
    || sed -i '0,/DocumentRoot/s|^\([[:space:]]*DocumentRoot.*\)|\1\n\n\tRequestHeader unset Proxy early|' \
       /etc/apache2/sites-available/000-default.conf
failure_message="cannot wait before the next attempt"
sleep 1

echo -e "\n"
log "Adding Parameters..."
failure_message="cannot write syslogemu.log"
grep -qxF '*.none    /var/log/ulog/syslogemu.log' /etc/rsyslog.conf || \
    echo '*.none    /var/log/ulog/syslogemu.log' | tee -a /etc/rsyslog.conf >/dev/null

# backup conf files
cp -f /etc/security/limits.conf{,.bak} &>/dev/null || true
cp -f /etc/systemd/system.conf{,.bak} &>/dev/null || true
cp -f /etc/systemd/user.conf{,.bak} &>/dev/null || true
cp -f /etc/hosts{,.bak} &>/dev/null || true

# adding parameters
failure_message="cannot write limits.conf"
grep -qxF 'root    hard    nofile  65535' /etc/security/limits.conf || tee -a /etc/security/limits.conf >/dev/null <<EOT
*       soft    nproc   65535
*       hard    nproc   65535
*       soft    nofile  65535
*       hard    nofile  65535
root    soft    nproc   65535
root    hard    nproc   65535
root    soft    nofile  65535
root    hard    nofile  65535
EOT
failure_message="cannot write system optimization settings"
cat > /etc/sysctl.d/99-system-optimization.conf <<'EOT'
# System optimization
vm.swappiness = 10
net.ipv4.tcp_congestion_control = bbr
EOT
failure_message="cannot write system.conf"
grep -qxF "DefaultLimitNOFILE=65535" /etc/systemd/system.conf || echo "DefaultLimitNOFILE=65535" | tee -a /etc/systemd/system.conf >/dev/null
failure_message="cannot write user.conf"
grep -qxF "DefaultLimitNOFILE=65535" /etc/systemd/user.conf || echo "DefaultLimitNOFILE=65535" | tee -a /etc/systemd/user.conf >/dev/null
sysctl --system >/dev/null || info "some sysctl parameters failed to apply"

log "Apache Config..."
cp -f /etc/apache2/apache2.conf{,.bak} &>/dev/null || true
#echo 'RequestReadTimeout header=10-20,MinRate=500 body=20,MinRate=500' | tee -a /etc/apache2/apache2.conf # optional

# Hardening
if [ -f /etc/apache2/conf-available/security.conf ]; then
    failure_message="cannot copy Apache security.conf"
    cp -f /etc/apache2/conf-available/security.conf{,.bak} &>/dev/null
else
    failure_message="cannot create Apache security.conf"
    touch /etc/apache2/conf-available/security.conf
fi
failure_message="cannot edit Apache security.conf"
sed -i "s/^#*\s*ServerSignature.*/ServerSignature Off/" /etc/apache2/conf-available/security.conf
failure_message="cannot edit Apache security.conf"
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
        failure_message="cannot edit Apache security.conf"
        sed -i "s|^#*\s*Header set $name.*|Header set $name \"$value\"|" /etc/apache2/conf-available/security.conf
    else
        failure_message="cannot write Apache security.conf"
        echo "Header set $name \"$value\"" >> /etc/apache2/conf-available/security.conf
    fi
done
failure_message="cannot write Apache security.conf"
grep -q "^FileETag None" /etc/apache2/conf-available/security.conf || \
    echo 'FileETag None' >> /etc/apache2/conf-available/security.conf

failure_message="cannot write Apache security.conf"
grep -q "^Header unset ETag" /etc/apache2/conf-available/security.conf || \
    echo 'Header unset ETag' >> /etc/apache2/conf-available/security.conf

failure_message="cannot write Apache security.conf"
grep -q "^Timeout" /etc/apache2/conf-available/security.conf || \
    echo 'Timeout 60' >> /etc/apache2/conf-available/security.conf
failure_message="cannot edit apache2.conf"
sed -i 's/Options -Indexes FollowSymLinks/Options -Indexes +FollowSymLinks/g' /etc/apache2/apache2.conf
a2enconf -q security || true
failure_message="cannot wait before the next attempt"
sleep 1

# APACHE PASSWORD
# Create the Apache authentication password file
echo -e "\n"
log "Create Apache Password: /var/www/..."
echo -e "\n"
until htpasswd -c /etc/apache2/.htpasswd "$local_user"; do
    info "Passwords did not match or were empty. Try again"
done

# APACHE CONFIG
# Validate Apache configuration and set web directory permissions
apache2ctl configtest || true
failure_message="cannot set permissions on Apache web directories"
chmod -R 755 /var/www/html /var/www/wpad
failure_message="cannot set owner of Apache web directories"
chown -R www-data:www-data /var/www/html /var/www/wpad
apachectl -t -D DUMP_INCLUDES -S || true
failure_message="cannot wait before the next attempt"
sleep 1

# CRONTAB
# Register the project startup and maintenance tasks
echo -e "\n"
log "Add Crontab Tasks..."
failure_message="cannot update the project cron file"
cron_d_set "systemctl daemon-reload" "@reboot root systemctl daemon-reload"
failure_message="cannot update the project cron file"
cron_d_set "/etc/scr/hwclock.sh" "@reboot root /etc/scr/hwclock.sh"
failure_message="cannot update the project cron file"
cron_d_set "/etc/scr/blackusb.sh" "@reboot root /etc/scr/blackusb.sh --off"
failure_message="cannot update the project cron file"
cron_d_set "/etc/scr/serviceswatch.sh" "*/5 * * * * root /etc/scr/serviceswatch.sh"
failure_message="cannot update the project cron file"
cron_d_set "/etc/scr/cleaner.sh" "@weekly root /etc/scr/cleaner.sh"
failure_message="cannot wait before the next attempt"
sleep 1

# ENDING ###
# Disable NFS (Network File System) / NIS (Network Information Service)
if systemctl list-unit-files | grep -q '^rpcbind'; then
    systemctl stop rpcbind.service rpcbind.socket &>/dev/null || true
    systemctl disable rpcbind.service rpcbind.socket &>/dev/null || true
    systemctl mask rpcbind.service rpcbind.socket &>/dev/null || true
fi

# Restart Daemon
failure_message="cannot restart the systemd manager"
systemctl daemon-reexec &>/dev/null
# Update initramfs (optional)
#update-initramfs -u -k all
# create alias "upgrade"
failure_message="cannot update the desktop application index"
sudo -u "$local_user" bash -c "grep -q '^alias upgrade=' '${local_home}/.bashrc' 2>/dev/null || printf '%s\n' 'alias upgrade=\"sudo nala upgrade --purge -y && sudo aptitude -y safe-upgrade && sudo sync && sudo dpkg --configure -a && sudo nala install --fix-broken -y && sudo systemctl daemon-reload && sudo updatedb && sudo update-desktop-database && sudo snap refresh\"' >> ${local_home}/.bashrc"
failure_message="cannot add server alias to .bashrc"
sudo -u "$local_user" bash -c "grep -q '^alias server=' '${local_home}/.bashrc' 2>/dev/null || printf '%s\n' 'alias server=\"sudo /etc/scr/serverboot.sh\"' >> ${local_home}/.bashrc"
failure_message="cannot add cleaner alias to .bashrc"
sudo -u "$local_user" bash -c "grep -q '^alias cleaner=' '${local_home}/.bashrc' 2>/dev/null || printf '%s\n' 'alias cleaner=\"sudo /etc/scr/cleaner.sh\"' >> ${local_home}/.bashrc"
# IPv4 priority
failure_message="cannot edit gai.conf"
sed -i 's/^#\s*precedence ::ffff:0:0\/96\s\+100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf
# snap
snap unset system proxy.http || true
snap unset system proxy.https || true
failure_message="cannot refresh snap packages"
retry_cmd snap refresh snapd
failure_message="cannot reload systemd configuration"
systemctl daemon-reload
systemctl restart snapd || true
failure_message="cannot refresh snap packages"
retry_cmd snap refresh
# logs
failure_message="cannot set permissions on /var/log"
chmod 755 /var/log
failure_message="cannot set owner of /var/log"
chown root:syslog /var/log

failure_message="cannot update system packages"
upgrade

echo -e "\n"
echo "Done. Press ENTER to Reboot"
echo "after reboot, run:"
echo "systemctl list-units --type service --state running,failed"
failure_message="cannot read the continue confirmation"
read -r RES
failure_message="cannot restart the systemd manager"
systemctl daemon-reexec
failure_message="cannot reload systemd configuration"
systemctl daemon-reload
failure_message="cannot update CA certificates"
update-ca-certificates -f
systemctl reload apache2 || true
failure_message="cannot edit journald.conf"
sed -i '/^#\?SystemMaxUse=$/s/.*/SystemMaxUse=50M/' /etc/systemd/journald.conf
failure_message="cannot clean old journal files"
journalctl --vacuum-size=50M
a2query -s || true
#apt -qq -y remove --purge `deborphan --guess-all` # optional
#dpkg -l | grep "^rc" | cut -d " " -f 3 | xargs dpkg --purge &> /dev/null # optional
failure_message="cannot enter the requested directory"
cd /
failure_message="cannot remove gitfolder.py"
rm -f "$(dirname "$gp_path")/gitfolder.py"
failure_message="cannot remove the Gateproxy repository"
rm -rf "$gp_path"
(sleep 2 && rm -- "$SCRIPT_PATH") &

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

log "gpsetup done at: $(date '+%Y-%m-%d %H:%M:%S')"
failure_message="cannot reboot the server"
reboot
