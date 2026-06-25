#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
#  usetup.sh — uhotspot installer / updater
#  https://github.com/maravento/vault/tree/master/uhotspot
#
#  Modes:
#    sudo bash usetup.sh             Install (default)
#    sudo bash usetup.sh --update    Update scripts only (preserves config/ACLs)
#    sudo bash usetup.sh --remove    Uninstall
#    sudo bash usetup.sh --help      Usage
#
#  Run from inside the cloned repo. The script expects to find:
#    ./uhotspotd.sh
#    ./uhotspotd.service
#    ./tools/uaudit.sh
#    ./tools/ucheck.sh
#    ./tools/ureload.sh
#    ./tools/uleases.sh
#
#  Hard dependencies (auto-installed via apt when missing):
#    bash, curl, jq, iptables, ipset, cron
#
#  Hard dependency NOT auto-installed (aborts if missing):
#    pydhcpd must be installed and running.
#    pydhcp is not an apt package; install it from
#    https://github.com/maravento/vault/tree/master/pydhcp before running this script.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Paths ───────────────────────────────────────────────────────────────────
HOTSPOT_DIR="/etc/uhotspot"
TOOLS_DIR="${HOTSPOT_DIR}/tools"
CONFIG_FILE="${HOTSPOT_DIR}/uhotspot.conf"
LOG_FILE="/var/log/uhotspot.log"
LOGROTATE_FILE="/etc/logrotate.d/uhotspot"
LOGROTATE_ULEASES_FILE="/etc/logrotate.d/uleases"
LOGROTATE_UAUDIT_FILE="/etc/logrotate.d/uaudit"
UAUDIT_LOG_FILE="/var/log/uaudit.log"
UIPTABLES_STUB="${TOOLS_DIR}/uiptables.sh"
SERVICE_DEST="/etc/systemd/system/uhotspotd.service"

# ─── Repo file expectations (relative to this script) ────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_TOOLS="${SCRIPT_DIR}/tools"
REPO_UHOTSPOTD="${SCRIPT_DIR}/uhotspotd.sh"
REPO_SERVICE="${SCRIPT_DIR}/uhotspotd.service"

# ─── Required apt packages (auto-installed when missing) ─────────────────────
APT_DEPS=(curl jq iptables ipset cron)

# ─── Discovered runtime values (filled during install) ───────────────────────
DHCP_BACKEND=""    # "pydhcpd"
LOCAL_USER=""

# ─── Output helpers ──────────────────────────────────────────────────────────
info()  { printf '  \e[32m✔\e[0m %s\n'   "$*"; }
warn()  { printf '  \e[33m!\e[0m %s\n'   "$*"; }
err()   { printf '  \e[31m✗\e[0m %s\n'   "$*" >&2; }
step()  { printf '\n── %s ─────────────────────────────────────────────\n' "$*"; }
abort() { err "$*"; exit 1; }

confirm() {
    # confirm "prompt" [default y|n]  — returns 0 on yes, 1 on no
    local prompt="$1" default="${2:-n}" answer hint
    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
    read -rp "  ${prompt} ${hint}: " answer
    answer="${answer:-$default}"
    [[ "${answer,,}" =~ ^y(es)?$ ]]
}

# ─── Preflight checks ────────────────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || abort "Must run as root. Use: sudo bash $(basename "$0")"
}

check_distro() {
    local id="" ver=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        id="${ID:-}"
        ver="${VERSION_ID:-}"
    fi
    if [[ "$id" != "ubuntu" || "$ver" != "24.04" ]]; then
        warn "Tested only on Ubuntu 24.04. Detected: ${id:-unknown} ${ver:-unknown}"
        warn "Continuing at your own risk."
    else
        info "Ubuntu ${ver} detected"
    fi
}

detect_local_user() {
    # Multi-strategy detection (mirrors uhotspot.sh logic).
    LOCAL_USER=""
    LOCAL_USER=$(who | awk '/\(:0\)/{print $1; exit}')
    [[ -z "$LOCAL_USER" ]] && LOCAL_USER=$(logname 2>/dev/null || true)
    [[ -z "$LOCAL_USER" ]] && LOCAL_USER="${SUDO_USER:-}"
    [[ -z "$LOCAL_USER" ]] && LOCAL_USER=$(who | awk 'NR==1{print $1}')
    [[ -z "$LOCAL_USER" ]] && LOCAL_USER=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
    if [[ -z "$LOCAL_USER" ]] || ! id "$LOCAL_USER" &>/dev/null; then
        abort "Cannot determine a valid local user"
    fi
    info "Local user: $LOCAL_USER"
}

check_repo_files() {
    [[ -r "$REPO_UHOTSPOTD" ]] || abort "Missing $(basename "$REPO_UHOTSPOTD"). Run usetup.sh from inside the cloned uhotspot repository."
    [[ -r "$REPO_SERVICE"   ]] || abort "Missing $(basename "$REPO_SERVICE"). Run usetup.sh from inside the cloned uhotspot repository."
    [[ -d "$REPO_TOOLS"     ]] || abort "Missing tools/ directory. Run usetup.sh from inside the cloned uhotspot repository."
    info "Repo files located"
}

ensure_apt_deps() {
    local missing=()
    for pkg in "${APT_DEPS[@]}"; do
        if ! command -v "$pkg" &>/dev/null && ! dpkg -s "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        info "Installing missing apt packages: ${missing[*]}"
        apt-get update -qq || abort "apt-get update failed"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" \
            || abort "apt-get install failed for: ${missing[*]}"
    else
        info "All apt dependencies already installed"
    fi
}

detect_dhcp_backend() {
    local pydhcp_active=false
    systemctl is-active --quiet pydhcpd 2>/dev/null && pydhcp_active=true

    if $pydhcp_active; then
        DHCP_BACKEND="pydhcpd"
        info "DHCP backend detected: pydhcpd"
    else
        err "pydhcpd is not active."
        err "Install and start pydhcpd from https://github.com/maravento/vault/tree/master/pydhcp"
        abort "Aborting: DHCP backend required."
    fi
}

# ─── Interactive prompts (migrated from uhotspot.sh) ─────────────────────────
ask() {
    local prompt="$1" default="$2" var="$3" answer
    if [[ -n "$default" ]]; then
        read -rp "  ${prompt} [${default}]: " answer
        answer="${answer:-$default}"
    else
        while true; do
            read -rp "  ${prompt}: " answer
            [[ -n "$answer" ]] && break
            err "This field is required."
        done
    fi
    printf -v "$var" '%s' "$answer"
}

ask_interface() {
    local prompt="$1" default="$2" var="$3" answer
    while true; do
        read -rp "  ${prompt} [${default}]: " answer
        answer="${answer:-$default}"
        if ip link show "$answer" &>/dev/null; then
            printf -v "$var" '%s' "$answer"
            break
        fi
        err "Interface '$answer' not found. Available: $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | tr '\n' ' ' || true)"
    done
}

ask_ip() {
    local prompt="$1" var="$2" answer
    while true; do
        read -rp "  ${prompt}: " answer
        if [[ "$answer" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            local valid=1
            IFS='.' read -ra octs <<< "$answer"
            for o in "${octs[@]}"; do
                (( o < 0 || o > 255 )) && valid=0 && break
            done
            [[ $valid -eq 1 ]] && printf -v "$var" '%s' "$answer" && break
        fi
        err "'$answer' is not a valid IPv4 address (e.g. 192.168.0.1)."
    done
}

ask_octet() {
    local prompt="$1" default="$2" var="$3" ref_start="${4:-0}" answer
    while true; do
        read -rp "  ${prompt} [${default}]: " answer
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= 254 )); then
            if [[ -n "$ref_start" ]] && (( answer <= ref_start )); then
                err "End octet must be greater than start octet (${ref_start})."
                continue
            fi
            printf -v "$var" '%s' "$answer"
            break
        fi
        err "'$answer' is not valid. Enter a number between 1 and 254."
    done
}

# ─── UniFi controller discovery ──────────────────────────────────────────────
DISCOVERED_URL=""
DISCOVERED_TYPE=""

discover_unifi_controller() {
    local user="$1" pass="$2" server_ip="$3"
    local ports=(8443 11443)
    local test_url http_code payload

    info "Probing ${server_ip} on ports ${ports[*]} ..."
    payload=$(jq -n --arg u "$user" --arg p "$pass" '{username: $u, password: $p}')

    for port in "${ports[@]}"; do
        test_url="https://${server_ip}:${port}"

        http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "${test_url}/api/auth/login" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --connect-timeout 3 || echo "000")
        if [[ "$http_code" == "200" ]]; then
            info "Found UniFi OS controller at ${test_url}"
            DISCOVERED_URL="$test_url"
            DISCOVERED_TYPE="unifi-os"
            return 0
        fi

        http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
            -X POST "${test_url}/api/login" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --connect-timeout 3 || echo "000")
        if [[ "$http_code" == "200" ]]; then
            info "Found classic UniFi controller at ${test_url}"
            DISCOVERED_URL="$test_url"
            DISCOVERED_TYPE="classic"
            return 0
        fi
    done

    return 1
}

# ─── Setup wizard ────────────────────────────────────────────────────────────
run_setup_wizard() {
    local CFG_WAN_IF CFG_LAN_IF CFG_SERVER_IP CFG_IP_RANGE
    local CFG_RANGE_START CFG_RANGE_END CFG_ESSID
    local CFG_UNIFI_USER CFG_UNIFI_PASS CFG_RELOAD_SCRIPT
    local found_url found_type

    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  uhotspot — Interactive Setup"
    echo "══════════════════════════════════════════════════════"

    step "Network"
    local ifaces
    ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | tr '\n' ' ' || true)
    echo "  Available interfaces: $ifaces"
    ask_interface "WAN interface" "eth0" CFG_WAN_IF
    ask_interface "LAN interface" "eth1" CFG_LAN_IF
    ask_ip        "Server IP (this machine)" CFG_SERVER_IP

    step "Hotspot IP range"
    CFG_IP_RANGE=$(echo "$CFG_SERVER_IP" | cut -d'.' -f1-3)
    echo "  Hotspot IP range base (auto-detected): $CFG_IP_RANGE"
    ask_octet "Range start (last octet)" "160" CFG_RANGE_START
    ask_octet "Range end   (last octet)" "170" CFG_RANGE_END "$CFG_RANGE_START"

    step "Hotspot SSID"
    ask "Guest SSID name (must match exactly in UniFi)" "" CFG_ESSID

    step "UniFi credentials"
    ask "UniFi admin username" "admin" CFG_UNIFI_USER
    while true; do
        read -rsp "  UniFi admin password: " CFG_UNIFI_PASS; echo ""
        [[ -n "$CFG_UNIFI_PASS" ]] && break
        err "Password cannot be empty."
    done

    step "UniFi controller discovery"
    DISCOVERED_URL=""
    DISCOVERED_TYPE=""
    if discover_unifi_controller "$CFG_UNIFI_USER" "$CFG_UNIFI_PASS" "$CFG_SERVER_IP"; then
        found_url="$DISCOVERED_URL"
        found_type="$DISCOVERED_TYPE"
    else
        warn "No UniFi controller detected automatically."
        ask "Enter controller URL manually (e.g. https://192.168.0.1:8443)" "" found_url
        echo "  Enter controller type:"
        select found_type in "unifi-os" "classic"; do
            [[ -n "$found_type" ]] && break
        done
    fi

    step "Reload script"
    echo "  Script invoked after every ACL change (must exist and be executable)."
    ask "Path to reload script" "${TOOLS_DIR}/ureload.sh" CFG_RELOAD_SCRIPT

    step "DHCP network"
    ask_mask() {
        local var="$1" default="${2:-255.255.255.0}" answer
        while true; do
            read -rp "  Subnet mask [$default]: " answer
            answer="${answer:-$default}"
            if echo "$answer" | grep -qE '^(255|254|252|248|240|224|192|128|0)(\.(255|254|252|248|240|224|192|128|0)){3}$'; then
                printf -v "$var" '%s' "$answer"; break
            fi
            err "Invalid mask, try again"
        done
    }
    ask_mask CFG_SERV_MASK "255.255.255.0"
    CFG_SERV_SUBNET=$(python3 -c "import ipaddress; net=ipaddress.IPv4Network('${CFG_SERVER_IP}/${CFG_SERV_MASK}', strict=False); print(net.network_address)")
    CFG_SERV_BROADCAST=$(python3 -c "import ipaddress; net=ipaddress.IPv4Network('${CFG_SERVER_IP}/${CFG_SERV_MASK}', strict=False); print(net.broadcast_address)")
    info "Subnet: $CFG_SERV_SUBNET  Broadcast: $CFG_SERV_BROADCAST"

    step "DNS servers"
    ask "DNS servers (comma-separated)" "8.8.8.8,1.1.1.1" CFG_SERV_DNS

    step "DHCP pool (for new/unknown clients)"
    local NET_BASE
    NET_BASE="${CFG_SERVER_IP%.*}"
    echo "  These IPs are assigned temporarily to clients not yet in any ACL list."
    ask_octet "Pool start (last octet)" "230" CFG_POOL_START
    ask_octet "Pool end   (last octet)" "239" CFG_POOL_END "$CFG_POOL_START"
    CFG_SERV_INI_RANGE_BLOCK="${NET_BASE}.${CFG_POOL_START}"
    CFG_SERV_END_RANGE_BLOCK="${NET_BASE}.${CFG_POOL_END}"

    step "Timers"
    ask "Daemon poll interval in seconds (POLL_INTERVAL)" "10" CFG_POLL_INTERVAL
    ask "DHCP pool lease cleanup interval in seconds (CLEANUP_INTERVAL)" "20" CFG_CLEANUP_INTERVAL
    ask "Grace period before blocking unknown MACs in seconds (BLOCKDHCP_GRACE_SECONDS)" "86400" CFG_GRACE_SECONDS

    step "Optional features"
    local CFG_WPAD_ENABLED="false"
    confirm "Enable WPAD/PAC proxy auto-configuration? (requires Apache2 on port 18100)" "n" && CFG_WPAD_ENABLED="true"
    local CFG_PING_CHECK="true"
    confirm "Enable pydhcpd ping-check before OFFER? (disable if strict ICMP rules)" "y" && CFG_PING_CHECK="true" || CFG_PING_CHECK="false"

    step "Managed MAC lists (optional)"
    echo "  mac-*.txt files allow specific devices to bypass the captive portal"
    echo "  automatically (corporate laptops, APs, printers, switches, etc.)."
    echo "  If enabled, the daemon authorizes those MACs in UniFi each cycle."
    echo "  Files are stored in /etc/acl/acl_mac/ and managed manually."
    local CFG_USE_MANAGED_MACS="false"
    if confirm "Enable managed MAC lists (mac-proxy, mac-unlimited, etc.)?" "n"; then
        CFG_USE_MANAGED_MACS="true"
        mkdir -p /etc/acl/acl_mac /etc/acl/acl_dhcp /etc/acl/acl_ipt
        chmod 700 /etc/acl/acl_mac /etc/acl/acl_dhcp /etc/acl/acl_ipt
        info "Directory /etc/acl/acl_mac created — add your mac-*.txt files there"
    fi

    step "Writing $CONFIG_FILE"
    cat > "$CONFIG_FILE" <<EOF
# uhotspot — auto-generated by usetup.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Edit this file to adjust any value.

# ── Network ──────────────────────────────────────────────────────────────────
WAN_IF="${CFG_WAN_IF}"
LAN_IF="${CFG_LAN_IF}"
SERVER_IP="${CFG_SERVER_IP}"
LOCAL_USER="${LOCAL_USER}"

# ── Hotspot IP range ─────────────────────────────────────────────────────────
HOTSPOT_IP_RANGE="${CFG_IP_RANGE}"
HOTSPOT_RANGE_START=${CFG_RANGE_START}
HOTSPOT_RANGE_END=${CFG_RANGE_END}

# ── Guest SSID ───────────────────────────────────────────────────────────────
HOTSPOT_ESSID="${CFG_ESSID}"

# ── UniFi Controller ─────────────────────────────────────────────────────────
UNIFI_CONTROLLER_URL="${found_url}"
UNIFI_USERNAME="${CFG_UNIFI_USER}"
UNIFI_PASSWORD="${CFG_UNIFI_PASS}"
# UniFi always creates a site named "default". If the administrator renamed it,
# edit this value to match the exact site name shown in the UniFi controller.
UNIFI_SITE="default"
UNIFI_TYPE="${found_type}"


# ── Reload script (required) ─────────────────────────────────────────────────
SERVER_RELOAD_SCRIPT="${CFG_RELOAD_SCRIPT}"

# ── Managed MAC lists (optional) ─────────────────────────────────────────────
# Set to true if you use mac-*.txt files in /etc/acl/acl_mac/ to allow
# specific devices to bypass the captive portal without a voucher.
MANAGED_MACS_ENABLED="${CFG_USE_MANAGED_MACS}"

# ── DHCP network (read by uleases.sh and uiptables.sh) ───────────────────────
SERV_DHCP="${CFG_SERVER_IP}"
SERV_MASK="${CFG_SERV_MASK}"
SERV_SUBNET="${CFG_SERV_SUBNET}"
SERV_BROADCAST="${CFG_SERV_BROADCAST}"
SERV_DNS="${CFG_SERV_DNS}"

# ── DHCP pool (temporary IPs for new/unknown clients) ────────────────────────
SERV_INI_RANGE_BLOCK="${CFG_SERV_INI_RANGE_BLOCK}"
SERV_END_RANGE_BLOCK="${CFG_SERV_END_RANGE_BLOCK}"

# ── Paths (read by uleases.sh) ───────────────────────────────────────────────
ACL_PATH=/etc/acl
ACL_MAC_PATH=/etc/acl/acl_mac
ACL_DHCP_PATH=/etc/acl/acl_dhcp
ACL_MAC_PROXY=/etc/acl/acl_mac/mac-proxy.txt
ACL_MAC_TRANSPARENT=/etc/acl/acl_mac/mac-transparent.txt
ACL_MAC_UNLIMITED=/etc/acl/acl_mac/mac-unlimited.txt
ACL_MAC_HOTSPOT=/etc/uhotspot/mac-hotspot.txt
ACL_GUEST_PENDING=/etc/uhotspot/guest-pending.txt
ACL_BLOCK_FILE=/etc/acl/acl_dhcp/blockdhcp.txt
ACL_GRACE_FILE=/etc/acl/acl_dhcp/gracedhcp.txt

# ── Daemon & DHCP timers ─────────────────────────────────────────────────────
POLL_INTERVAL=${CFG_POLL_INTERVAL}
CLEANUP_INTERVAL=${CFG_CLEANUP_INTERVAL}
AUTHORIZED_LEASE_TIME=2592000
BLOCKDHCP_GRACE_SECONDS=${CFG_GRACE_SECONDS}

# ── Optional features ─────────────────────────────────────────────────────────
UNIFI_HOTSPOT_ENABLED=true
WPAD_ENABLED="${CFG_WPAD_ENABLED}"
PING_CHECK_ENABLED="${CFG_PING_CHECK}"
EOF
    chown root:root "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    info "Config saved to $CONFIG_FILE (mode 600)"
}

# ─── Filesystem layout ───────────────────────────────────────────────────────
deploy_directories() {
    mkdir -p "$HOTSPOT_DIR" "$TOOLS_DIR"
    chmod 700 "$HOTSPOT_DIR"
    chmod 700 "$TOOLS_DIR"
    info "Directories created"
}

deploy_scripts() {
    install -m 755 -o root -g root "$REPO_UHOTSPOTD" "${HOTSPOT_DIR}/uhotspotd.sh"
    install -m 755 -o root -g root "${REPO_TOOLS}/"*.sh "${TOOLS_DIR}/"
    info "Scripts deployed to ${HOTSPOT_DIR}"
}

deploy_uiptables_stub() {
    if [[ -f "$UIPTABLES_STUB" ]]; then
        info "uiptables.sh already exists — leaving untouched"
        return 0
    fi
    cat > "$UIPTABLES_STUB" <<'STUB'
#!/bin/bash
# /etc/uhotspot/tools/uiptables.sh
#
# Firewall rules for uhotspot. Invoked by ureload.sh after every ACL change.
#
# This file is a STUB. Copy the reference rules from the uhotspot README into
# this file and adapt the variables (wan, lan, wan_ip) to your network.
#
# The script must do two things:
#   1. Flush and repopulate the ipsets `macpending` and `machotspot` from the
#      ACL files at /etc/uhotspot/guest-pending.txt and /etc/uhotspot/mac-hotspot.txt
#   2. Apply (idempotently) the iptables rules that consume those ipsets.
#
# Without this script populated, ACL changes will not reach the firewall and
# the captive portal will not work.

echo "uiptables.sh: not configured. Edit /etc/uhotspot/tools/uiptables.sh." >&2
exit 1
STUB
    chown root:root "$UIPTABLES_STUB"
    chmod 750 "$UIPTABLES_STUB"
    warn "Stub created at $UIPTABLES_STUB — YOU MUST EDIT IT (see README)"
}

install_logrotate() {
    if [[ -f "$LOGROTATE_FILE" ]]; then
        info "logrotate config already present at $LOGROTATE_FILE"
    else
        cat > "$LOGROTATE_FILE" <<EOF
${LOG_FILE} {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 640 root adm
}
EOF
        chown root:root "$LOGROTATE_FILE"
        chmod 644 "$LOGROTATE_FILE"
        info "logrotate config installed at $LOGROTATE_FILE"
    fi


    if [[ -f "$LOGROTATE_UAUDIT_FILE" ]]; then
        info "logrotate config already present at $LOGROTATE_UAUDIT_FILE"
    else
        cat > "$LOGROTATE_UAUDIT_FILE" <<EOF
${UAUDIT_LOG_FILE} {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
        chown root:root "$LOGROTATE_UAUDIT_FILE"
        chmod 644 "$LOGROTATE_UAUDIT_FILE"
        info "logrotate config installed at $LOGROTATE_UAUDIT_FILE"
    fi
}

register_cron() {
    # uhotspotd runs as a systemd service — no cron entry needed for it.
    # Only the hourly ureload.sh trigger is registered here.
    local ureload_path="${HOTSPOT_DIR}/tools/ureload.sh"
    local expected_hourly="@hourly UHOTSPOT_RELOAD_ACTIVE=1 flock -w 60 /var/lock/uhotspot.lock -c '${ureload_path}'"
    local current
    current=$(crontab -l 2>/dev/null || true)
    local changed=0

    if echo "$current" | grep -qF "$expected_hourly"; then
        info "Cron entry (ureload @hourly) already present"
    elif echo "$current" | grep -qF "$ureload_path"; then
        warn "Crontab contains entries for $ureload_path in a different format — review manually"
    else
        current=$(printf '%s\n%s\n' "$current" "$expected_hourly")
        info "Cron entry registered: $expected_hourly"
        changed=1
    fi

    (( changed )) && echo "$current" | crontab -
}

final_sanity_check() {
    step "Sanity check"
    local issues=0

    if [[ ! -x "$UIPTABLES_STUB" ]] || grep -q "not configured" "$UIPTABLES_STUB" 2>/dev/null; then
        warn "uiptables.sh is not configured — ACL changes will not reach the firewall"
        (( issues++ ))
    fi

    if (( issues == 0 )); then
        info "All checks passed."
    else
        warn "${issues} issue(s) need attention before uhotspot is fully functional."
    fi
}

# ─── Install mode ────────────────────────────────────────────────────────────
do_install() {
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  uhotspot — installer"
    echo "══════════════════════════════════════════════════════"

    step "Preflight"
    check_root
    check_distro
    detect_local_user
    check_repo_files

    step "Dependencies"
    ensure_apt_deps
    detect_dhcp_backend

    step "Filesystem layout"
    deploy_directories
    deploy_scripts
    deploy_uiptables_stub

    run_setup_wizard

    step "Logrotate"
    install_logrotate

    step "Systemd service"
    install_systemd_service

    step "Cron"
    register_cron

    final_sanity_check

    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  uhotspot installed."
    echo ""
    echo "  Next steps:"
    echo "    1. Edit ${UIPTABLES_STUB} with the firewall rules from the README."
    echo "    2. Check service: systemctl status uhotspotd"
    echo "    3. Check logs: tail -f ${LOG_FILE}"
    echo "══════════════════════════════════════════════════════"
    echo ""
}

# ─── Update mode ─────────────────────────────────────────────────────────────
do_update() {
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  uhotspot — update"
    echo "══════════════════════════════════════════════════════"

    step "Preflight"
    check_root
    check_distro
    check_repo_files

    if [[ ! -d "$HOTSPOT_DIR" || ! -f "${HOTSPOT_DIR}/uhotspotd.sh" ]]; then
        abort "uhotspot not installed. Run without --update first."
    fi

    step "DHCP backend"
    detect_dhcp_backend

    step "Backup"
    local backup_dir
    backup_dir="/etc/uhotspot.bak/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -p "${HOTSPOT_DIR}/uhotspotd.sh" "$backup_dir/" 2>/dev/null || true
    cp -p "${TOOLS_DIR}/"*.sh "$backup_dir/" 2>/dev/null || true
    info "Current scripts backed up to $backup_dir"

    step "Deploy updated scripts"
    deploy_scripts

    step "Systemd service"
    install -m 644 -o root -g root "$REPO_SERVICE" "$SERVICE_DEST"
    systemctl daemon-reload
    systemctl restart uhotspotd && info "uhotspotd restarted" || warn "Could not restart uhotspotd — check: systemctl status uhotspotd"

    step "Cron"
    register_cron

    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  Update complete."
    echo ""
    echo "  Preserved (not modified):"
    echo "    - ${CONFIG_FILE}"
    echo "    - ${UIPTABLES_STUB}"
    echo "    - ACL data files (*.txt)"
    echo "    - Logrotate config"
    echo ""
    echo "  Cron entries reconciled (missing entries added; existing ones untouched)"
    echo ""

    echo "  Backup: $backup_dir"
    echo "══════════════════════════════════════════════════════"
    echo ""
}

# ─── Remove mode ─────────────────────────────────────────────────────────────
do_remove() {
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  uhotspot — uninstaller"
    echo "══════════════════════════════════════════════════════"
    check_root

    echo ""
    echo "  The following actions will be offered (each with confirmation):"
    echo "    • Remove cron entries pointing to ${HOTSPOT_DIR}/uhotspot.sh and ${HOTSPOT_DIR}/tools/ureload.sh"
    echo "    • Remove ${LOGROTATE_FILE}"
    echo "    • Remove ${HOTSPOT_DIR} (includes config.conf, ACLs, uiptables.sh)"
    echo "    • Remove ${LOG_FILE} and rotated logs"
    echo ""
    confirm "Proceed with uninstall?" "n" || { info "Aborted by user."; exit 0; }

    # Systemd service
    step "Systemd service"
    if systemctl is-active --quiet uhotspotd 2>/dev/null || systemctl is-enabled --quiet uhotspotd 2>/dev/null; then
        if confirm "Stop and disable uhotspotd.service?" "y"; then
            systemctl disable --now uhotspotd 2>/dev/null || true
            info "uhotspotd.service disabled and stopped"
        else
            warn "uhotspotd.service preserved"
        fi
    fi
    if [[ -f "$SERVICE_DEST" ]]; then
        if confirm "Remove $SERVICE_DEST?" "y"; then
            rm -f "$SERVICE_DEST"
            systemctl daemon-reload
            info "Service file removed"
        else
            warn "Service file preserved"
        fi
    fi

    # Cron entries
    step "Cron"
    local ureload_path="${HOTSPOT_DIR}/tools/ureload.sh"
    if crontab -l 2>/dev/null | grep -qF "$ureload_path"; then
        if confirm "Remove cron entries for $ureload_path?" "y"; then
            crontab -l 2>/dev/null | grep -vF "$ureload_path" | crontab - || true
            info "Cron entries removed"
        else
            warn "Cron entries preserved"
        fi
    else
        info "No cron entries found"
    fi

    # Logrotate
    step "Logrotate"
    for lf in "$LOGROTATE_FILE" "$LOGROTATE_ULEASES_FILE" "$LOGROTATE_UAUDIT_FILE"; do
        [[ -f "$lf" ]] && rm -f "$lf" && info "Removed $lf" || true
    done
    info "Logrotate configs removed"

    # /etc/uhotspot
    step "$HOTSPOT_DIR"
    if [[ -d "$HOTSPOT_DIR" ]]; then
        echo "  This will delete:"
        echo "    - $CONFIG_FILE (credentials)"
        echo "    - ${HOTSPOT_DIR}/mac-hotspot.txt, guest-pending.txt, guest-wellknow.txt (ACLs)"
        echo "    - $UIPTABLES_STUB (YOUR firewall script — back it up first if needed)"
        echo "    - All other contents of $HOTSPOT_DIR"
        if confirm "Remove $HOTSPOT_DIR entirely?" "n"; then
            rm -rf -- "$HOTSPOT_DIR"
            info "Removed $HOTSPOT_DIR"
        else
            warn "$HOTSPOT_DIR preserved"
        fi
    else
        info "$HOTSPOT_DIR does not exist"
    fi

    # Logs
    step "Logs"
    if compgen -G "${LOG_FILE}*" >/dev/null; then
        if confirm "Remove ${LOG_FILE} and rotated archives?" "n"; then
            rm -f -- "${LOG_FILE}" "${LOG_FILE}".*
            info "Logs removed"
        else
            warn "Logs preserved"
        fi
    else
        info "No log files found"
    fi

    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  Uninstall complete."
    echo ""
    echo "  IMPORTANT: Firewall rules and ipsets (macpending, machotspot)"
    echo "  were NOT touched. Flush them manually if needed:"
    echo "    sudo ipset destroy macpending 2>/dev/null"
    echo "    sudo ipset destroy machotspot 2>/dev/null"
    echo "    # then flush related iptables rules"
    echo "══════════════════════════════════════════════════════"
    echo ""
}

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: sudo bash $(basename "$0") [OPTION]

Modes:
  (none)         Install uhotspot (default).
  --update       Update scripts only (preserves config, ACLs, cron, firewall).
  --remove       Uninstall uhotspot (interactive, with confirmations).
  --help, -h     Show this help.

Run from inside the cloned uhotspot repository. See the README for details.
EOF
}

# ─── Dispatch ────────────────────────────────────────────────────────────────
main() {
    case "${1:-}" in
        ""|install)
            do_install
            ;;
        --update|update)
            do_update
            ;;
        --remove|remove|--uninstall|uninstall)
            do_remove
            ;;
        --help|-h|help)
            usage
            ;;
        *)
            err "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
