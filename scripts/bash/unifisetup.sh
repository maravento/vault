#!/bin/bash
# maravento.com
#
################################################################################
#
# UniFi Setup - Installer / Uninstaller / Updater for Ubuntu
#
# Description:
# Installs, updates, and removes UniFi Network Application and UniFi OS
# Server on Ubuntu, using Ubiquiti's own official release catalog
# (download.svc.ui.com) to detect and download versions. No third-party
# scripts or APIs are used.
#
# Supported OS:
# Ubuntu 24.04 LTS (noble) or newer. Nothing older is supported.
#
# Products:
# - UniFi Network Application (installed via the official .deb package,
# requires MongoDB and a matching Java runtime)
# - UniFi OS Server (installed via the official Linux installer binary,
# runs rootless containers through Podman)
#
# Usage:
# sudo ./unifisetup.sh
#
# Menu-driven only, no command-line parameters are accepted:
# 1. Install UniFi Network Application
# 2. Install UniFi OS Server
# 3. Update UniFi Network Application
# 4. Update UniFi OS Server
# 5. Uninstall UniFi Network Application
# 6. Uninstall UniFi OS Server
# 7. Show status (installed vs. latest online)
# 8. Exit
#
# Log file: unifisetup.log, next to this script (truncate -s 0 unifisetup.log to clear)
# Downloads/work dir: .unifisetup-work, also next to this script
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$SCRIPT_LOCK")
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# logging
script_dir="$(cd "$(dirname "$0")" && pwd)"
log_file="${script_dir}/unifisetup.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

################################################################################
# Constants
################################################################################

DOWNLOADS_API="https://download.svc.ui.com/v1/software-downloads"
WORK_DIR="${script_dir}/.unifisetup-work"
DOWNLOADS_JSON="${WORK_DIR}/downloads.json"
MIN_MAJOR="24"
MIN_MINOR="04"

################################################################################
# OS / architecture checks
################################################################################

get_server_address() {
    local addr
    addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
    if [ -z "${addr}" ]; then
        addr="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')"
    fi
    echo "${addr:-localhost}"
}

os_check() {
    if [ ! -f /etc/os-release ]; then
        log "ERROR: /etc/os-release not found, cannot detect OS"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    if [ "${ID:-}" != "ubuntu" ]; then
        log "ERROR: This script only supports Ubuntu (detected: ${ID:-unknown})"
        exit 1
    fi

    local version_major version_minor
    version_major="$((10#$(echo "${VERSION_ID:-0}" | cut -d'.' -f1)))"
    version_minor="$((10#$(echo "${VERSION_ID:-0}" | cut -d'.' -f2)))"

    if [ "${version_major}" -lt "${MIN_MAJOR}" ] || { [ "${version_major}" -eq "${MIN_MAJOR}" ] && [ "${version_minor}" -lt "$((10#$MIN_MINOR))" ]; }; then
        log "ERROR: Requires Ubuntu ${MIN_MAJOR}.${MIN_MINOR}+ (detected ${VERSION_ID:-unknown})"
        exit 1
    fi

    os_codename="${VERSION_CODENAME:-noble}"
    log "OS check passed: Ubuntu ${VERSION_ID} (${os_codename})"
}

arch_check() {
    architecture="$(dpkg --print-architecture)"
    case "${architecture}" in
        amd64) osserver_arch="x64" ;;
        arm64) osserver_arch="arm64" ;;
        *)
            log "ERROR: Unsupported architecture: ${architecture}"
            exit 1
            ;;
    esac
}

################################################################################
# Prerequisites
################################################################################

ensure_prereqs() {
    local missing=()
    for pkg in curl gnupg jq ca-certificates apt-transport-https; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log "Installing prerequisites..."
        apt-get update -qq >>"$log_file" 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >>"$log_file" 2>&1
    fi

    mkdir -p /etc/apt/keyrings
    mkdir -p -m 700 "${WORK_DIR}"
}

################################################################################
# Ubiquiti release catalog
################################################################################

fetch_downloads_json() {
    log "Fetching official Ubiquiti release catalog..."
    if ! curl -fsSL "${DOWNLOADS_API}" -o "${DOWNLOADS_JSON}"; then
        log "ERROR: Failed to fetch release catalog."
        log "URL: ${DOWNLOADS_API}"
        exit 1
    fi
}

# Populates: latest_network_version, latest_network_url
get_latest_network() {
    local row
    row="$(jq -r '.downloads[] | select(.name | test("^UniFi Network Application [0-9.]+ for Debian/Ubuntu$")) | [.version, .file_url] | @tsv' "${DOWNLOADS_JSON}" | sort -k1,1V | tail -n1)"
    latest_network_version="$(echo "$row" | cut -f1)"
    latest_network_url="$(echo "$row" | cut -f2)"
}

# Populates: latest_osserver_version, latest_osserver_url
get_latest_osserver() {
    local row
    row="$(jq -r --arg arch "${osserver_arch}" '.downloads[] | select(.name | test("^UniFi OS Server [0-9.]+ for Linux \\(" + $arch + "\\)$")) | [.version, .file_url] | @tsv' "${DOWNLOADS_JSON}" | sort -k1,1V | tail -n1)"
    latest_osserver_version="$(echo "$row" | cut -f1)"
    latest_osserver_url="$(echo "$row" | cut -f2)"
}

# Populates: installed_network_version ("" if not installed)
get_installed_network() {
    installed_network_version="$(dpkg-query -W -f='${Version}' unifi 2>/dev/null | cut -d'-' -f1 || true)"
}

# Populates: installed_osserver_version ("" if not installed)
get_installed_osserver() {
    installed_osserver_version=""
    if [ -f /var/lib/uosserver/server.conf ]; then
        installed_osserver_version="$(grep -m1 -E '^(APP_VERSION|UOS_SERVER_VERSION)=' /var/lib/uosserver/server.conf 2>/dev/null | cut -d'=' -f2 || true)"
    fi
}

################################################################################
# Repositories
################################################################################

ensure_mongodb_repo() {
    if [ -f /etc/apt/sources.list.d/mongodb-org-8.0.list ]; then
        return 0
    fi
    log "Adding MongoDB 8.0 repository..."
    curl -fsSL https://pgp.mongodb.com/server-8.0.asc | gpg -o /etc/apt/keyrings/mongodb-server-8.0.gpg --dearmor --yes >>"$log_file" 2>&1
    if [ "${PIPESTATUS[0]}" -ne 0 ] || [ "${PIPESTATUS[1]}" -ne 0 ]; then
        log "ERROR: Failed to add MongoDB repository key"
        return 1
    fi
    # "noble" is intentionally fixed, not the detected codename: MongoDB only
    # publishes an apt suite per supported Ubuntu LTS, not per release. Every
    # codename this script supports (24.04+) maps to the "noble" suite until
    # MongoDB ships one for a newer LTS.
    echo "deb [ arch=amd64,arm64 signed-by=/etc/apt/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" \
        > /etc/apt/sources.list.d/mongodb-org-8.0.list
}

ensure_adoptium_repo() {
    if [ -f /etc/apt/sources.list.d/adoptium.list ]; then
        return 0
    fi
    log "Adding Adoptium (Temurin) repository..."

    # Adoptium doesn't always have a suite for a brand-new Ubuntu release
    # yet. Check its dists listing first (same check Glenn's script does)
    # and fall back to noble, our guaranteed-supported baseline, if the
    # detected codename isn't published there.
    local adoptium_codename="${os_codename}"
    if ! curl -fsSL "https://packages.adoptium.net/artifactory/deb/dists/" \
        | sed -e 's/<[^>]*>//g' -e '/^$/d' | awk '{print $1}' | sed 's#/$##' \
        | grep -iq "^${adoptium_codename}$"; then
        log "WARNING: Adoptium has no ${adoptium_codename} suite yet, using noble"
        adoptium_codename="noble"
    fi

    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg -o /etc/apt/keyrings/packages-adoptium.gpg --dearmor --yes >>"$log_file" 2>&1
    if [ "${PIPESTATUS[0]}" -ne 0 ] || [ "${PIPESTATUS[1]}" -ne 0 ]; then
        log "ERROR: Failed to add Adoptium repository key"
        return 1
    fi
    echo "deb [signed-by=/etc/apt/keyrings/packages-adoptium.gpg] https://packages.adoptium.net/artifactory/deb ${adoptium_codename} main" \
        > /etc/apt/sources.list.d/adoptium.list
}

# Sets: java_package, needs_adoptium (true/false)
determine_java_package() {
    local major minor
    major="$(echo "$1" | cut -d'.' -f1)"
    minor="$(echo "$1" | cut -d'.' -f2)"

    if [ "$major" -gt 10 ] || { [ "$major" -eq 10 ] && [ "$minor" -ge 1 ]; }; then
        if apt-cache search --names-only '^openjdk-25-jre-headless$' | grep -q .; then
            java_package="openjdk-25-jre-headless"
            needs_adoptium="false"
        else
            java_package="temurin-25-jre"
            needs_adoptium="true"
        fi
    elif [ "$major" -eq 9 ] || [ "$major" -eq 10 ]; then
        java_package="openjdk-21-jre-headless"
        needs_adoptium="false"
    else
        java_package="openjdk-17-jre-headless"
        needs_adoptium="false"
    fi
}

################################################################################
# UniFi Network Application
################################################################################

install_network() {
    local target_version="$1"
    local target_url="$2"

    if ! ensure_mongodb_repo; then
        return 1
    fi

    log "Updating apt package lists..."
    apt-get update -qq >>"$log_file" 2>&1

    # Needs a populated apt cache to know if openjdk-25 is available,
    # otherwise it always falls back to Adoptium on a fresh install.
    determine_java_package "${target_version}"
    if [ "${needs_adoptium}" = "true" ]; then
        if ! ensure_adoptium_repo; then
            return 1
        fi
        apt-get update -qq >>"$log_file" 2>&1
    fi

    log "Installing Java runtime (${java_package})..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${java_package}" ca-certificates-java >>"$log_file" 2>&1; then
        log "ERROR: Failed to install ${java_package}"
        return 1
    fi

    # Pin this JRE as the default "java" in PATH, instead of trusting
    # update-alternatives' auto-priority -- another JRE on this host
    # (e.g. for a different app) could otherwise end up as the default
    # that UniFi's service picks up.
    local java_bin
    java_bin="$(dpkg -L "${java_package}" 2>/dev/null | grep -E '/bin/java$' | head -n1)"
    if [ -n "${java_bin}" ]; then
        log "Setting ${java_package} as the default java..."
        update-alternatives --set java "${java_bin}" >>"$log_file" 2>&1 || true
    fi

    # ca-certificates-java can leave a fresh JRE's cacerts keystore empty
    # or half-built (a known Debian/Ubuntu packaging bug), which breaks
    # UniFi's own outbound HTTPS calls. Rebuild it from scratch.
    log "Refreshing CA certificates for Java..."
    rm -f /etc/ssl/certs/java/cacerts 2>/dev/null
    if update-ca-certificates -f >>"$log_file" 2>&1; then
        mkdir -p /etc/ssl/certs/java
        printf '\xfe\xed\xfe\xed\x00\x00\x00\x02\x00\x00\x00\x00\xe2\x68\x6e\x45\xfb\x43\xdf\xa4\xd9\x92\xdd\x41\xce\xb6\xb2\x1c\x63\x30\xd7\x92' \
            > /etc/ssl/certs/java/cacerts
        if [ -x /var/lib/dpkg/info/ca-certificates-java.postinst ]; then
            /var/lib/dpkg/info/ca-certificates-java.postinst configure >>"$log_file" 2>&1 || true
        fi
    else
        log "WARNING: Failed to refresh CA certificates"
    fi

    local deb_file="${WORK_DIR}/unifi_${target_version}_all.deb"
    log "Downloading UniFi Network ${target_version}..."
    if ! curl -fL --progress-bar -o "${deb_file}" "${target_url}"; then
        log "ERROR: Failed to download package."
        log "URL: ${target_url}"
        return 1
    fi

    log "Installing UniFi Network ${target_version}..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' "${deb_file}" >>"$log_file" 2>&1; then
        log "UniFi Network ${target_version} installed"
    else
        log "ERROR: Failed to install package."
        log "File: ${deb_file}"
        rm -f "${deb_file}"
        return 1
    fi
    rm -f "${deb_file}"
}

action_install_network() {
    get_installed_network
    if [ -n "${installed_network_version}" ]; then
        log "UniFi Network already installed (v${installed_network_version})."
        log "Use update instead."
        return 1
    fi
    get_installed_osserver
    if [ -n "${installed_osserver_version}" ]; then
        log "ERROR: OS Server (v${installed_osserver_version}) present; can't coexist."
        log "Remove UniFi OS Server first."
        return 1
    fi
    get_latest_network
    if [ -z "${latest_network_version}" ]; then
        log "ERROR: Could not fetch latest UniFi Network version"
        return 1
    fi
    if install_network "${latest_network_version}" "${latest_network_url}"; then
        echo ""
        echo "UniFi Network Application is available at: https://$(get_server_address):8443"
    fi
}

action_update_network() {
    get_installed_network
    if [ -z "${installed_network_version}" ]; then
        log "UniFi Network not installed. Use install instead."
        return 1
    fi
    get_latest_network
    if [ -z "${latest_network_version}" ]; then
        log "ERROR: Could not fetch latest UniFi Network version"
        return 1
    fi
    if dpkg --compare-versions "${installed_network_version}" ge "${latest_network_version}"; then
        log "UniFi Network already up to date (v${installed_network_version})"
        return 0
    fi
    log "Updating UniFi Network: ${installed_network_version} -> ${latest_network_version}"
    install_network "${latest_network_version}" "${latest_network_url}"
}

# Backs up the latest UniFi autobackup (.unf), the same format UniFi itself generates
backup_network_config() {
    local autobackup_dir
    autobackup_dir="$(grep -s '^autobackup\.dir' /usr/lib/unifi/data/system.properties 2>/dev/null | cut -d'=' -f2)"
    autobackup_dir="${autobackup_dir:-/usr/lib/unifi/data/backup/autobackup}"

    local latest_unf
    latest_unf="$(find "${autobackup_dir}" -type f -name '*.unf' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | awk '{print $2}')"

    if [ -z "${latest_unf}" ]; then
        log "WARNING: No UniFi autobackup (.unf) found, skipping backup"
        log "Looked in: ${autobackup_dir}"
        return 1
    fi

    local dest
    dest="${script_dir}/unifi-backup-$(basename "${latest_unf}")"
    if cp "${latest_unf}" "${dest}" 2>>"$log_file"; then
        log "Backup saved: ${dest}"
    else
        log "WARNING: Failed to create backup."
        log "Path: ${dest}"
        rm -f "${dest}"
        return 1
    fi
}

action_uninstall_network() {
    get_installed_network
    if [ -z "${installed_network_version}" ]; then
        log "UniFi Network not installed, nothing to remove"
        return 0
    fi

    read -rp "Remove UniFi Network Application ${installed_network_version}? (y/N) " confirm
    case "$confirm" in
        [Yy]*) ;;
        *) log "Uninstall cancelled by user"; return 0 ;;
    esac

    echo "Back up the current configuration (latest .unf autobackup)"
    read -rp "before removing? (y/N) " do_backup
    case "$do_backup" in
        [Yy]*) backup_network_config ;;
    esac

    local remove_mongo="n"
    echo "WARNING:"
    echo "MongoDB was installed as a UniFi dependency, may be shared."
    read -rp "Do you want to remove MongoDB? (y/N) " remove_mongo

    systemctl stop unifi 2>/dev/null || true

    log "Purging unifi package..."
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq unifi >>"$log_file" 2>&1 || true

    case "$remove_mongo" in
        [Yy]*)
            log "Purging MongoDB packages..."
            DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq 'mongodb-org*' >>"$log_file" 2>&1 || true
            rm -rf /var/lib/mongodb /etc/mongod.conf* /var/log/mongodb
            rm -f /etc/apt/sources.list.d/mongodb-org-8.0.list /etc/apt/keyrings/mongodb-server-8.0.gpg
            ;;
    esac

    rm -rf /usr/lib/unifi /var/log/unifi
    apt-get autoremove -y -qq >>"$log_file" 2>&1 || true

    # Release the manual "java" pin install_network() set, so this host
    # goes back to auto-selecting a default instead of staying locked to
    # the JRE UniFi needed, now that UniFi is gone.
    log "Releasing the default java pin..."
    update-alternatives --auto java >>"$log_file" 2>&1 || true

    log "UniFi Network removed"
    log "Java runtime and the Adoptium repo, if added, were left in place"
    log "in case another app on this host depends on them."
    log "The 'java' alternative was reset to auto-selection."
}

################################################################################
# UniFi OS Server
################################################################################

ensure_osserver_prereqs() {
    local pkgs=(podman slirp4netns uidmap dbus libpam-systemd)
    local missing=()
    for pkg in "${pkgs[@]}"; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log "Installing UniFi OS Server prerequisites..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >>"$log_file" 2>&1
    fi
}

install_osserver() {
    local target_version="$1"
    local target_url="$2"

    ensure_osserver_prereqs

    local installer_file="${WORK_DIR}/uosserver-${target_version}"
    log "Downloading UniFi OS Server ${target_version}..."
    log "This is a large file, it may take a while."
    if ! curl -fL --progress-bar -o "${installer_file}" "${target_url}"; then
        log "ERROR: Failed to download package."
        log "URL: ${target_url}"
        return 1
    fi

    chmod +x "${installer_file}"

    log "Running UniFi OS Server installer..."
    if "${installer_file}" --non-interactive --force-install 200>&- >>"$log_file" 2>&1; then
        log "OS Server ${target_version} installed"
    else
        log "ERROR: UniFi OS Server installer failed"
        rm -f "${installer_file}"
        return 1
    fi
    rm -f "${installer_file}"
}

action_install_osserver() {
    get_installed_osserver
    if [ -n "${installed_osserver_version}" ]; then
        log "OS Server already installed (v${installed_osserver_version})."
        log "Use update instead."
        return 1
    fi
    get_installed_network
    if [ -n "${installed_network_version}" ]; then
        log "ERROR: Network (v${installed_network_version}) present; can't coexist."
        log "Remove UniFi Network first."
        return 1
    fi
    get_latest_osserver
    if [ -z "${latest_osserver_version}" ]; then
        log "ERROR: Could not fetch latest UniFi OS Server version"
        return 1
    fi
    if install_osserver "${latest_osserver_version}" "${latest_osserver_url}"; then
        echo ""
        echo "UniFi OS Server is available at: https://$(get_server_address):11443"
    fi
}

action_update_osserver() {
    get_installed_osserver
    if [ -z "${installed_osserver_version}" ]; then
        log "OS Server not installed. Use install instead."
        return 1
    fi
    get_latest_osserver
    if [ -z "${latest_osserver_version}" ]; then
        log "ERROR: Could not fetch latest UniFi OS Server version"
        return 1
    fi
    if dpkg --compare-versions "${installed_osserver_version}" ge "${latest_osserver_version}"; then
        log "OS Server already up to date (v${installed_osserver_version})"
        return 0
    fi
    log "Updating OS Server: ${installed_osserver_version} -> ${latest_osserver_version}"
    install_osserver "${latest_osserver_version}" "${latest_osserver_url}"
}

# UniFi OS Server has no on-disk backup file to reuse: its UI generates the
# .unifi backup on demand and streams it straight to the browser, it never
# persists a copy server-side (unlike UniFi Network Application's .unf
# autobackups). So the only thing we can back up here is its persistent
# state directory, /var/lib/uosserver.
backup_osserver_config() {
    if [ ! -d /var/lib/uosserver ]; then
        log "WARNING: /var/lib/uosserver not found, skipping backup"
        return 1
    fi
    local dest
    dest="${script_dir}/uosserver-backup-${installed_osserver_version}-$(date +%Y%m%d%H%M%S).tar.gz"
    if tar -czf "${dest}" -C /var/lib uosserver 2>>"$log_file"; then
        log "Backup saved: ${dest}"
    else
        log "WARNING: Failed to create backup."
        log "Path: ${dest}"
        rm -f "${dest}"
        return 1
    fi
}

action_uninstall_osserver() {
    get_installed_osserver
    if [ -z "${installed_osserver_version}" ]; then
        log "OS Server not installed, nothing to remove"
        return 0
    fi

    read -rp "Remove UniFi OS Server ${installed_osserver_version}? (y/N) " confirm
    case "$confirm" in
        [Yy]*) ;;
        *) log "Uninstall cancelled by user"; return 0 ;;
    esac

    local unit_path
    unit_path="$(systemctl show -p FragmentPath --value uosserver 2>/dev/null || true)"

    # Stop everything first so the backup below (and the removal after it)
    # sees a quiescent state, not a live container writing to it mid-tar.
    systemctl disable --now uosserver 2>/dev/null || true

    if id -u uosserver >/dev/null 2>&1; then
        runuser -u uosserver -- podman stop -a 2>/dev/null || true
        runuser -u uosserver -- podman rm -fa 2>/dev/null || true
    fi

    echo "Note: UniFi OS Server does not keep a .unifi backup file on disk (the UI"
    echo "generates it on demand and streams it straight to your browser)."
    echo "This backs up its persistent state directory (/var/lib/uosserver) instead,"
    echo "which is not the same file format as the UI's Backup button."
    read -rp "Back up /var/lib/uosserver before removing? (y/N) " do_backup
    case "$do_backup" in
        [Yy]*) backup_osserver_config ;;
    esac

    if id -u uosserver >/dev/null 2>&1; then
        # Rootless podman keeps a "systemd --user" instance alive via
        # linger, so containers survive without a login session. That
        # instance holds the uosserver UID open until it's torn down,
        # which blocks userdel below.
        loginctl disable-linger uosserver 2>/dev/null || true
        loginctl terminate-user uosserver 2>/dev/null || true
        sleep 2
        pkill -u uosserver 2>/dev/null || true
        sleep 1
        pkill -9 -u uosserver 2>/dev/null || true
    fi

    if [ -n "${unit_path}" ] && [ -f "${unit_path}" ]; then
        rm -f "${unit_path}"
    fi
    systemctl daemon-reload

    rm -rf /var/lib/uosserver

    if id -u uosserver >/dev/null 2>&1; then
        if ! userdel -r uosserver 2>>"$log_file"; then
            log "WARNING: Could not remove user uosserver, check ${log_file}"
        fi
    fi
    if getent group uosserver >/dev/null 2>&1; then
        if ! groupdel uosserver 2>>"$log_file"; then
            log "WARNING: Could not remove group uosserver"
        fi
    fi

    log "OS Server removed"
}

################################################################################
# Status
################################################################################

action_status() {
    get_installed_network
    get_latest_network
    get_installed_osserver
    get_latest_osserver

    echo ""
    echo "==========================================="
    echo "UniFi Network Application"
    echo "==========================================="
    echo "Installed: ${installed_network_version:-not installed}"
    echo "Latest online: ${latest_network_version:-unknown}"
    if [ -n "${installed_network_version}" ] && [ -n "${latest_network_version}" ] && dpkg --compare-versions "${installed_network_version}" lt "${latest_network_version}"; then
        echo "Update available"
    fi
    echo ""
    echo "==========================================="
    echo "UniFi OS Server"
    echo "==========================================="
    echo "Installed: ${installed_osserver_version:-not installed}"
    echo "Latest online: ${latest_osserver_version:-unknown}"
    if [ -n "${installed_osserver_version}" ] && [ -n "${latest_osserver_version}" ] && dpkg --compare-versions "${installed_osserver_version}" lt "${latest_osserver_version}"; then
        echo "Update available"
    fi
    echo ""
}

################################################################################
# Menu
################################################################################

menu() {
    while true; do
        clear
        echo ""
        echo "==========================================="
        echo "UniFi Setup"
        echo "==========================================="
        echo "1. Install UniFi Network Application"
        echo "2. Install UniFi OS Server"
        echo "3. Update UniFi Network Application"
        echo "4. Update UniFi OS Server"
        echo "5. Uninstall UniFi Network Application"
        echo "6. Uninstall UniFi OS Server"
        echo "7. Show status (installed vs. latest online)"
        echo "8. Exit"
        echo ""
        read -rp "Select an option (1-8): " choice
        case "$choice" in
            1) action_install_network ;;
            2) action_install_osserver ;;
            3) action_update_network ;;
            4) action_update_osserver ;;
            5) action_uninstall_network ;;
            6) action_uninstall_osserver ;;
            7) action_status ;;
            8) log "unifisetup done at: $(date)"; exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        echo ""
        read -n1 -rsp "Press any key to continue..."
    done
}

################################################################################
# Main
################################################################################

if [ -n "${1:-}" ]; then
    echo "This script does not accept parameters."
    echo "See the header comments for usage."
    exit 1
fi

# Start
log "unifisetup start..."

os_check
arch_check
ensure_prereqs
fetch_downloads_json
menu
