#!/bin/bash
# maravento.com
#
################################################################################
#
# UniFi Setup - Installer / Uninstaller / Updater for Ubuntu
#
# DESCRIPTION:
# Installs, updates, and removes UniFi Network Application and UniFi OS
# Server on Ubuntu, using Ubiquiti's own official release catalog to detect
# and download versions. Menu-driven with no arguments, or scriptable with
# a direct action argument. Only considers NICs with an IPv4 address
# assigned; IPv6-only interfaces are not detected.
#
# USAGE:
# sudo ./unifisetup.sh
# sudo ./unifisetup.sh <action>
# actions: install-network, install-osserver, update-network,
#          update-osserver, uninstall-network, uninstall-osserver, status
#
# LOG: unifisetup.log, next to this script (rewritten on each run)
#
################################################################################

set -uo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# logging
script_dir="$(cd "$(dirname "$0")" && pwd)"
log_file="${script_dir}/unifisetup.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# OWN VALUES
# ------------------------------------------------------------------------------

# Values this script declares itself -- not read from any .env
downloads_api="https://download.svc.ui.com/v1/software-downloads"
work_dir="${script_dir}/.unifisetup-work"
downloads_json="${work_dir}/downloads.json"
min_major="24"
min_minor="04"

# ------------------------------------------------------------------------------
# PLATFORM
# ------------------------------------------------------------------------------

get_server_address() {
    local iface_list addr iface lan_choice i
    mapfile -t iface_list < <(ip -4 -o addr show 2>/dev/null | awk '$2 != "lo" {print $2}' | sort -u)
    if [ "${#iface_list[@]}" -le 1 ]; then
        iface="${iface_list[0]:-}"
    else
        echo "Available network interfaces:" >&2
        for i in "${!iface_list[@]}"; do
            addr="$(ip -4 -o addr show dev "${iface_list[$i]}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
            printf " [%d] %s (%s)\n" "$((i+1))" "${iface_list[$i]}" "${addr:-no IPv4}" >&2
        done
        echo "" >&2
        while true; do
            read -rp " Select LAN interface number [1-${#iface_list[@]}] [Default: 1]: " lan_choice
            lan_choice="${lan_choice:-1}"
            if [[ "$lan_choice" =~ ^[0-9]+$ ]] && [ "$lan_choice" -ge 1 ] && [ "$lan_choice" -le "${#iface_list[@]}" ]; then
                break
            fi
            echo " Invalid selection, try again." >&2
        done
        iface="${iface_list[$((lan_choice-1))]}"
    fi
    if [ -n "$iface" ]; then
        addr="$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    fi
    if [ -z "${addr:-}" ]; then
        addr="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')"
    fi
    echo "${addr:-localhost}"
}

os_check() {
    if [ ! -f /etc/os-release ]; then
        log "ERROR: /etc/os-release not found, cannot detect OS -- abort"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    if [ "${ID:-}" != "ubuntu" ]; then
        log "WARNING: Ubuntu required; detected ${ID:-unknown}"
        log "WARNING: continuing anyway -- alert"
    fi

    if [ "$(printf '%s\n' "${VERSION_ID:-0}" "${min_major}.${min_minor}" | sort -V | head -n1)" != "${min_major}.${min_minor}" ]; then
        log "WARNING: untested below Ubuntu ${min_major}.${min_minor}"
        log "WARNING: Ubuntu ${VERSION_ID:-unknown} untested -- alert"
    fi

    os_codename="${VERSION_CODENAME:-noble}"
    log "Ubuntu ${VERSION_ID:-unknown} (${os_codename}) detected"
}

arch_check() {
    architecture="$(dpkg --print-architecture)"
    case "${architecture}" in
        amd64) osserver_arch="x64" ;;
        arm64) osserver_arch="arm64" ;;
        *)
            log "ERROR: unsupported architecture: ${architecture} -- abort"
            exit 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# PREREQUISITES
# ------------------------------------------------------------------------------

ensure_prereqs() {
    local missing=()
    for pkg in curl gnupg jq ca-certificates apt-transport-https iproute2 util-linux; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log "Installing prerequisites..."
        apt-get update -qq >>"$log_file" 2>&1
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >>"$log_file" 2>&1
    fi

    mkdir -p /etc/apt/keyrings
    mkdir -p -m 700 "${work_dir}"
}

# ------------------------------------------------------------------------------
# VERSIONS
# ------------------------------------------------------------------------------

fetch_downloads_json() {
    log "Fetching official Ubiquiti release catalog..."
    if ! curl -fsSL "${downloads_api}" -o "${downloads_json}"; then
        log "ERROR: failed to fetch release catalog"
        log "ERROR: URL: ${downloads_api} -- abort"
        exit 1
    fi
}

# Populates: latest_network_version, latest_network_url
get_latest_network() {
    local row
    row="$(jq -r '.downloads[] | select(.name | test("^UniFi Network Application [0-9.]+ for Debian/Ubuntu$")) | [.version, .file_url] | @tsv' "${downloads_json}" | sort -k1,1V | tail -n1)"
    latest_network_version="$(echo "$row" | cut -f1)"
    latest_network_url="$(echo "$row" | cut -f2)"
}

# Populates: latest_osserver_version, latest_osserver_url
get_latest_osserver() {
    local row
    row="$(jq -r --arg arch "${osserver_arch}" '.downloads[] | select(.name | test("^UniFi OS Server [0-9.]+ for Linux \\(" + $arch + "\\)$")) | [.version, .file_url] | @tsv' "${downloads_json}" | sort -k1,1V | tail -n1)"
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

# ------------------------------------------------------------------------------
# REPOSITORIES
# ------------------------------------------------------------------------------

ensure_mongodb_repo() {
    local pipe_status
    if [ -f /etc/apt/sources.list.d/mongodb-org-8.0.list ]; then
        return 0
    fi
    log "Adding MongoDB 8.0 repository..."
    curl -fsSL https://pgp.mongodb.com/server-8.0.asc | gpg -o /etc/apt/keyrings/mongodb-server-8.0.gpg --dearmor --yes >>"$log_file" 2>&1
    pipe_status=("${PIPESTATUS[@]}")
    if [ "${pipe_status[0]}" -ne 0 ] || [ "${pipe_status[1]}" -ne 0 ]; then
        log "WARNING: failed to add MongoDB repository key -- alert"
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
    local adoptium_codename="${os_codename}" pipe_status
    if ! curl -fsSL "https://packages.adoptium.net/artifactory/deb/dists/" \
        | sed -e 's/<[^>]*>//g' -e '/^$/d' | awk '{print $1}' | sed 's#/$##' \
        | grep -iq "^${adoptium_codename}$"; then
        log "Adoptium suite requested: ${adoptium_codename}"
        log "WARNING: Adoptium suite missing; using noble -- fallback"
        adoptium_codename="noble"
    fi

    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg -o /etc/apt/keyrings/packages-adoptium.gpg --dearmor --yes >>"$log_file" 2>&1
    pipe_status=("${PIPESTATUS[@]}")
    if [ "${pipe_status[0]}" -ne 0 ] || [ "${pipe_status[1]}" -ne 0 ]; then
        log "WARNING: failed to add Adoptium repository key -- alert"
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

# ------------------------------------------------------------------------------
# NETWORK
# ------------------------------------------------------------------------------

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
        log "WARNING: failed to install ${java_package} -- alert"
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
        log "WARNING: failed to refresh CA certificates -- alert"
    fi

    local deb_file="${work_dir}/unifi_${target_version}_all.deb"
    log "Downloading UniFi Network ${target_version}..."
    if ! curl -fL --progress-bar -o "${deb_file}" "${target_url}"; then
        log "WARNING: failed to download package"
        log "WARNING: URL: ${target_url} -- alert"
        return 1
    fi

    log "Installing UniFi Network ${target_version}..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' "${deb_file}" >>"$log_file" 2>&1; then
        log "UniFi Network ${target_version} installed"
    else
        log "WARNING: failed to install package"
        log "WARNING: file: ${deb_file} -- alert"
        rm -f "${deb_file}"
        return 1
    fi
    rm -f "${deb_file}"
}

action_install_network() {
    get_installed_network
    if [ -n "${installed_network_version}" ]; then
        log "UniFi Network v${installed_network_version} installed."
        log "Use update instead."
        return 1
    fi
    get_installed_osserver
    if [ -n "${installed_osserver_version}" ]; then
        log "WARNING: OS Server (v${installed_osserver_version}) present, can't coexist"
        log "WARNING: remove UniFi OS Server first -- alert"
        return 1
    fi
    get_latest_network
    if [ -z "${latest_network_version}" ]; then
        log "WARNING: latest UniFi Network version unavailable -- alert"
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
        log "WARNING: latest UniFi Network version unavailable -- alert"
        return 1
    fi
    if dpkg --compare-versions "${installed_network_version}" ge "${latest_network_version}"; then
        log "UniFi Network v${installed_network_version} is current"
        return 0
    fi
    log "Updating UniFi Network:"
    log "${installed_network_version} -> ${latest_network_version}"
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
        log "WARNING: no UniFi autobackup (.unf) found, skipping backup"
        log "WARNING: looked in: ${autobackup_dir} -- alert"
        return 1
    fi

    local dest
    dest="${script_dir}/unifi-backup-$(basename "${latest_unf}")"
    if cp "${latest_unf}" "${dest}" 2>>"$log_file"; then
        log "Backup saved: ${dest}"
    else
        log "WARNING: failed to create backup"
        log "WARNING: path: ${dest} -- alert"
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
    echo "MongoDB was installed as a UniFi dependency, may be shared"
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
    log "Java and Adoptium repo remain; other apps may need them"
    log "in case another app on this host depends on them."
    log "The 'java' alternative was reset to auto-selection."
}

# ------------------------------------------------------------------------------
# OS SERVER
# ------------------------------------------------------------------------------

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

    local installer_file="${work_dir}/uosserver-${target_version}"
    log "Downloading UniFi OS Server ${target_version}..."
    log "This is a large file, it may take a while."
    if ! curl -fL --progress-bar -o "${installer_file}" "${target_url}"; then
        log "WARNING: failed to download package"
        log "WARNING: URL: ${target_url} -- alert"
        return 1
    fi

    chmod +x "${installer_file}"

    log "Running UniFi OS Server installer..."
    if "${installer_file}" --non-interactive --force-install 200>&- >>"$log_file" 2>&1; then
        log "OS Server ${target_version} installed"
    else
        log "WARNING: UniFi OS Server installer failed -- alert"
        rm -f "${installer_file}"
        return 1
    fi
    rm -f "${installer_file}"
}

action_install_osserver() {
    get_installed_osserver
    if [ -n "${installed_osserver_version}" ]; then
        log "UniFi OS Server v${installed_osserver_version} installed."
        log "Use update instead."
        return 1
    fi
    get_installed_network
    if [ -n "${installed_network_version}" ]; then
        log "WARNING: Network (v${installed_network_version}) present, can't coexist"
        log "WARNING: remove UniFi Network first -- alert"
        return 1
    fi
    get_latest_osserver
    if [ -z "${latest_osserver_version}" ]; then
        log "WARNING: latest UniFi OS Server version unavailable -- alert"
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
        log "WARNING: latest UniFi OS Server version unavailable -- alert"
        return 1
    fi
    if dpkg --compare-versions "${installed_osserver_version}" ge "${latest_osserver_version}"; then
        log "UniFi OS Server v${installed_osserver_version} is current"
        return 0
    fi
    log "OS Server current: ${installed_osserver_version}"
    log "INFO: OS Server target: ${latest_osserver_version}"
    install_osserver "${latest_osserver_version}" "${latest_osserver_url}"
}

# UniFi OS Server has no on-disk backup file to reuse: its UI generates the
# .unifi backup on demand and streams it straight to the browser, it never
# persists a copy server-side (unlike UniFi Network Application's .unf
# autobackups). So the only thing we can back up here is its persistent
# state directory, /var/lib/uosserver.
backup_osserver_config() {
    if [ ! -d /var/lib/uosserver ]; then
        log "WARNING: uosserver data dir missing; backup skipped -- alert"
        return 1
    fi
    local dest
    dest="${script_dir}/uosserver-backup-${installed_osserver_version}-$(date +%Y%m%d%H%M%S).tar.gz"
    if tar -czf "${dest}" -C /var/lib uosserver 2>>"$log_file"; then
        log "Backup saved: ${dest}"
    else
        log "WARNING: failed to create backup"
        log "WARNING: path: ${dest} -- alert"
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
            log "WARNING: userdel uosserver failed, see unifisetup.log -- alert"
        fi
    fi
    if getent group uosserver >/dev/null 2>&1; then
        if ! groupdel uosserver 2>>"$log_file"; then
            log "WARNING: could not remove group uosserver -- alert"
        fi
    fi

    log "OS Server removed"
}

# ------------------------------------------------------------------------------
# STATUS
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

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
            8) log "unifisetup done at: $(date '+%Y-%m-%d %H:%M:%S')"; exit 0 ;;
            *) echo "Invalid option" ;;
        esac
        echo ""
        read -n1 -rsp "Press any key to continue..."
    done
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

action="${1:-}"
case "$action" in
    ""|install-network|install-osserver|update-network|update-osserver|uninstall-network|uninstall-osserver|status) ;;
    *)
        echo "Unknown action: $action"
        echo "See the header comments for usage."
        exit 1
        ;;
esac

# Start
log "unifisetup start..."

os_check
arch_check
ensure_prereqs
fetch_downloads_json

case "$action" in
    install-network) action_install_network ;;
    install-osserver) action_install_osserver ;;
    update-network) action_update_network ;;
    update-osserver) action_update_osserver ;;
    uninstall-network) action_uninstall_network ;;
    uninstall-osserver) action_uninstall_osserver ;;
    status) action_status ;;
    *) menu ;;
esac
