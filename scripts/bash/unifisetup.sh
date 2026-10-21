#!/bin/bash
# maravento.com
#
################################################################################
#
# UniFi Setup - Installer / Uninstaller / Updater for Ubuntu
# FILE: unifisetup.sh
#
# DESCRIPTION:
# Installs, updates, and removes UniFi Network Application and UniFi OS
# Server on Ubuntu, using Ubiquiti's own official release catalog to detect
# and download versions. Menu-driven with no arguments, or scriptable with
# a direct action argument. Only considers NICs with an IPv4 address
# assigned; IPv6-only interfaces are not detected.
# Status checks local installation and service state without online queries.
#
# USAGE:
# sudo ./unifisetup.sh
# sudo ./unifisetup.sh --install {network|osserver}
# sudo ./unifisetup.sh --update {network|osserver}
# sudo ./unifisetup.sh --uninstall {network|osserver}
# sudo ./unifisetup.sh --status
# sudo ./unifisetup.sh --help
#
# LOG: unifisetup.log, next to this script (rewritten on each run)
#
################################################################################

set -uo pipefail

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
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# logging
script_dir="$(cd "$(dirname "$0")" && pwd)"
log_file="${script_dir}/unifisetup.log"
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

# ------------------------------------------------------------------------------
# OWN VALUES
# ------------------------------------------------------------------------------

# validation - integer only; use directly with =~
UH_UINT='^(0|[1-9][0-9]*)$'

# Values this script declares itself -- not read from any .env
downloads_api="https://download.svc.ui.com/v1/software-downloads"
work_dir="${script_dir}/unifisetup-work"
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
            if [[ "$lan_choice" =~ $UH_UINT ]] && [ "$lan_choice" -ge 1 ] && [ "$lan_choice" -le "${#iface_list[@]}" ]; then
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
        err "/etc/os-release not found, cannot detect OS -abort"
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    if [ "${ID:-}" != "ubuntu" ]; then
        warn "Ubuntu required; detected ${ID:-unknown}"
        warn "continuing anyway -alert"
    fi

    if [ "$(printf '%s\n' "${VERSION_ID:-0}" "${min_major}.${min_minor}" | sort -V | head -n1)" != "${min_major}.${min_minor}" ]; then
        warn "untested below Ubuntu ${min_major}.${min_minor}"
        warn "Ubuntu ${VERSION_ID:-unknown} untested -alert"
    fi

    os_codename="${VERSION_CODENAME:-noble}"
    info "Ubuntu ${VERSION_ID:-unknown} (${os_codename}) detected"
}

arch_check() {
    architecture="$(dpkg --print-architecture)"
    case "${architecture}" in
        amd64) osserver_arch="x64" ;;
        arm64) osserver_arch="arm64" ;;
        *)
            err "unsupported architecture: ${architecture} -abort"
            exit 1
            ;;
    esac
}

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

ensure_prereqs() {
    local missing=()
    for pkg in curl gnupg jq ca-certificates apt-transport-https iproute2 util-linux; do
        dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log "Installing prerequisites..."
        apt-get update -qq >>"$log_file" 2>&1 || {
            err "cannot update package lists -abort"
            exit 1
        }
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >>"$log_file" 2>&1 || {
            err "cannot install prerequisites -abort"
            exit 1
        }
    fi

    if ! { mkdir -p /etc/apt/keyrings && mkdir -p -m 700 "${work_dir}"; }; then
        err "cannot create prerequisite directories -abort"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# VERSIONS
# ------------------------------------------------------------------------------

fetch_downloads_json() {
    log "Fetching official Ubiquiti release catalog..."
    if ! curl -fsSL "${downloads_api}" -o "${downloads_json}"; then
        err "release catalog download failed -abort"
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
        err "failed to add MongoDB repository key -abort"
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
        info "Adoptium suite requested: ${adoptium_codename}"
        warn "Adoptium suite missing; using noble -fallback"
        adoptium_codename="noble"
    fi

    curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg -o /etc/apt/keyrings/packages-adoptium.gpg --dearmor --yes >>"$log_file" 2>&1
    pipe_status=("${PIPESTATUS[@]}")
    if [ "${pipe_status[0]}" -ne 0 ] || [ "${pipe_status[1]}" -ne 0 ]; then
        err "failed to add Adoptium repository key -abort"
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
    apt-get update -qq >>"$log_file" 2>&1 || {
        err "cannot update package lists -abort"
        return 1
    }

    # Needs a populated apt cache to know if openjdk-25 is available,
    # otherwise it always falls back to Adoptium on a fresh install.
    determine_java_package "${target_version}"
    if [ "${needs_adoptium}" = "true" ]; then
        if ! ensure_adoptium_repo; then
            return 1
        fi
        apt-get update -qq >>"$log_file" 2>&1 || {
            err "cannot update package lists -abort"
            return 1
        }
    fi

    log "Installing Java runtime (${java_package})..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${java_package}" ca-certificates-java >>"$log_file" 2>&1; then
        err "failed to install ${java_package} -abort"
        return 1
    fi

    # Pin this JRE as the default "java" in PATH, instead of trusting
    # update-alternatives' auto-priority -- another JRE on this host
    # (e.g. for a different app) could otherwise end up as the default
    # that UniFi's service picks up.
    local java_bin
    java_bin="$(dpkg -L "${java_package}" 2>/dev/null | grep -E '/bin/java$' | head -n1)"
    if [ -n "${java_bin}" ]; then
        info "Setting ${java_package} as default java"
        update-alternatives --set java "${java_bin}" >>"$log_file" 2>&1 || {
            err "cannot set default Java -abort"
            return 1
        }
    else
        err "cannot locate Java binary for ${java_package} -abort"
        return 1
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
        warn "failed to refresh CA certificates -alert"
    fi

    local deb_file="${work_dir}/unifi_${target_version}_all.deb"
    log "Downloading UniFi Network ${target_version}..."
    if ! curl -fL --progress-bar -o "${deb_file}" "${target_url}"; then
        err "UniFi Network package download failed -abort"
        return 1
    fi

    log "Installing UniFi Network ${target_version}..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' "${deb_file}" >>"$log_file" 2>&1; then
        info "UniFi Network ${target_version} installed"
    else
        err "UniFi Network package installation failed -abort"
        rm -f "${deb_file}"
        return 1
    fi
    rm -f "${deb_file}"
}

action_install_network() {
    get_installed_network
    if [ -n "${installed_network_version}" ]; then
        info "UniFi Network v${installed_network_version} installed"
        err "use update instead -abort"
        return 1
    fi
    get_installed_osserver
    if [ -n "${installed_osserver_version}" ]; then
        info "UniFi OS Server version: ${installed_osserver_version}"
        err "remove UniFi OS Server first -abort"
        return 1
    fi
    get_latest_network
    if [ -z "${latest_network_version}" ]; then
        err "latest UniFi Network version unavailable -abort"
        return 1
    fi
    if install_network "${latest_network_version}" "${latest_network_url}"; then
        echo ""
        info "UniFi Network URL: https://$(get_server_address):8443"
    else
        return 1
    fi
}

action_update_network() {
    get_installed_network
    if [ -z "${installed_network_version}" ]; then
        err "UniFi Network not installed; use install -abort"
        return 1
    fi
    get_latest_network
    if [ -z "${latest_network_version}" ]; then
        err "latest UniFi Network version unavailable -abort"
        return 1
    fi
    if dpkg --compare-versions "${installed_network_version}" ge "${latest_network_version}"; then
        info "UniFi Network v${installed_network_version} is current"
        return 0
    fi
    install_network "${latest_network_version}" "${latest_network_url}"
}

# Backs up the latest UniFi autobackup (.unf), the same format UniFi itself generates
backup_network_config() {
    local autobackup_dir
    autobackup_dir="$(grep -s '^autobackup\.dir=' /usr/lib/unifi/data/system.properties 2>/dev/null | cut -d'=' -f2-)"
    autobackup_dir="${autobackup_dir:-/usr/lib/unifi/data/backup/autobackup}"

    local latest_unf candidates=""
    if [ -d "${autobackup_dir}" ]; then
        candidates="$(find "${autobackup_dir}" -type f -name '*.unf' \
            -printf '%T@ %p\n' 2>/dev/null)" || {
            err "cannot search UniFi autobackups -abort"
            return 1
        }
    fi
    latest_unf="$(printf '%s\n' "$candidates" |
        sort -nr | head -n1 | cut -d' ' -f2-)"

    if [ -z "${latest_unf}" ]; then
        warn "UniFi Network: no .unf autobackup found -alert"
        return 0
    fi

    local dest tmp_dir
    dest="${script_dir}/unifi-backup-$(basename "${latest_unf}")"
    tmp_dir="$(mktemp -d "${dest}.XXXXXX" 2>>"$log_file")" || {
        err "cannot create temporary backup directory -abort"
        return 1
    }

    if { [ ! -e "${dest}" ] ||
            cp --attributes-only -p -- "${dest}" "${tmp_dir}/backup" 2>>"$log_file"; } &&
        cp -- "${latest_unf}" "${tmp_dir}/backup" 2>>"$log_file" &&
        mv -T -- "${tmp_dir}/backup" "${dest}" 2>>"$log_file"; then
        rmdir -- "${tmp_dir}" 2>>"$log_file"
        info "Backup saved: ${dest}"
    else
        err "UniFi Network backup could not be saved -abort"
        rm -f -- "${tmp_dir}/backup"
        rmdir -- "${tmp_dir}" 2>>"$log_file"
        return 1
    fi
}

action_uninstall_network() {
    get_installed_network
    if [ -z "${installed_network_version}" ]; then
        info "UniFi Network not installed, nothing to remove"
        return 0
    fi

    read -rp "Remove UniFi Network Application ${installed_network_version}? (y/N) " confirm
    case "$confirm" in
        [Yy]*) ;;
        *) info "Uninstall cancelled by user"; return 0 ;;
    esac

    echo "Back up current configuration (latest .unf autobackup)"
    read -rp "before removing? (y/N) " do_backup
    case "$do_backup" in
        [Yy]*) backup_network_config || return 1 ;;
    esac

    local remove_mongo="n"
    local mongo_failed="no"
    echo "MongoDB was installed as a UniFi dependency, may be shared"
    read -rp "Do you want to remove MongoDB? (y/N) " remove_mongo

    local was_active="no"
    systemctl is-active --quiet unifi && was_active="yes"
    systemctl stop unifi 2>/dev/null || true

    log "Purging unifi package..."
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq unifi >>"$log_file" 2>&1 || {
        err "cannot purge unifi package, uninstall aborted -abort"
        if [ "${was_active}" = "yes" ]; then
            systemctl start unifi >>"$log_file" 2>&1 ||
                warn "cannot restart unifi -alert"
        fi
        return 1
    }

    case "$remove_mongo" in
        [Yy]*)
            log "Purging MongoDB packages..."
            if DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq 'mongodb-org*' >>"$log_file" 2>&1; then
                rm -rf /var/lib/mongodb /etc/mongod.conf* /var/log/mongodb
                rm -f /etc/apt/sources.list.d/mongodb-org-8.0.list /etc/apt/keyrings/mongodb-server-8.0.gpg
            else
                warn "MongoDB purge failed; its data is kept -alert"
                mongo_failed="yes"
            fi
            ;;
    esac

    rm -rf /usr/lib/unifi /var/log/unifi
    apt-get autoremove -y -qq >>"$log_file" 2>&1 || true

    # Release the manual "java" pin install_network() set, so this host
    # goes back to auto-selecting a default instead of staying locked to
    # the JRE UniFi needed, now that UniFi is gone.
    info "Releasing default java pin"
    update-alternatives --auto java >>"$log_file" 2>&1 \
        || warn "cannot set Java to automatic selection -alert"

    if [ "${mongo_failed}" = "yes" ]; then
        err "UniFi Network removed; MongoDB packages remain -abort"
        return 1
    fi

    info "UniFi Network removed"
    info "Java and Adoptium repo kept; other apps may need them"
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

    ensure_osserver_prereqs || return 1

    local installer_file="${work_dir}/uosserver-${target_version}"
    log "Downloading UniFi OS Server ${target_version}..."
    info "This is a large file, it may take a while"
    if ! curl -fL --progress-bar -o "${installer_file}" "${target_url}"; then
        err "UniFi OS Server download failed -abort"
        return 1
    fi

    chmod +x "${installer_file}"

    log "Running UniFi OS Server installer..."
    if "${installer_file}" --non-interactive --force-install 200>&- >>"$log_file" 2>&1; then
        info "OS Server ${target_version} installed"
    else
        err "UniFi OS Server installer failed -abort"
        rm -f "${installer_file}"
        return 1
    fi
    rm -f "${installer_file}"
}

action_install_osserver() {
    get_installed_osserver
    if [ -n "${installed_osserver_version}" ]; then
        info "UniFi OS Server v${installed_osserver_version} installed"
        err "use update instead -abort"
        return 1
    fi
    get_installed_network
    if [ -n "${installed_network_version}" ]; then
        info "UniFi Network version: ${installed_network_version}"
        err "remove UniFi Network first -abort"
        return 1
    fi
    get_latest_osserver
    if [ -z "${latest_osserver_version}" ]; then
        err "latest UniFi OS Server version unavailable -abort"
        return 1
    fi
    if install_osserver "${latest_osserver_version}" "${latest_osserver_url}"; then
        echo ""
        info "UniFi OS Server URL: https://$(get_server_address):11443"
    else
        return 1
    fi
}

action_update_osserver() {
    get_installed_osserver
    if [ -z "${installed_osserver_version}" ]; then
        err "OS Server not installed; use install -abort"
        return 1
    fi
    get_latest_osserver
    if [ -z "${latest_osserver_version}" ]; then
        err "latest UniFi OS Server version unavailable -abort"
        return 1
    fi
    if dpkg --compare-versions "${installed_osserver_version}" ge "${latest_osserver_version}"; then
        info "UniFi OS Server v${installed_osserver_version} is current"
        return 0
    fi
    info "OS Server current: ${installed_osserver_version}"
    info "OS Server target: ${latest_osserver_version}"
    install_osserver "${latest_osserver_version}" "${latest_osserver_url}"
}

# UniFi OS Server has no on-disk backup file to reuse: its UI generates the
# .unifi backup on demand and streams it straight to the browser, it never
# persists a copy server-side (unlike UniFi Network Application's .unf
# autobackups). So the only thing we can back up here is its persistent
# state directory, /var/lib/uosserver.
backup_osserver_config() {
    if [ ! -d /var/lib/uosserver ]; then
        warn "uosserver data dir missing; backup skipped -alert"
        return 0
    fi
    local dest tmp_dir
    dest="${script_dir}/uosserver-backup-${installed_osserver_version}-$(date +%Y%m%d%H%M%S).tar.gz"
    tmp_dir="$(mktemp -d "${dest}.XXXXXX" 2>>"$log_file")" || {
        err "cannot create temporary backup directory -abort"
        return 1
    }

    if { [ ! -e "${dest}" ] ||
            cp --attributes-only -p -- "${dest}" "${tmp_dir}/backup" 2>>"$log_file"; } &&
        tar -czf "${tmp_dir}/backup" -C /var/lib uosserver 2>>"$log_file" &&
        mv -T -- "${tmp_dir}/backup" "${dest}" 2>>"$log_file"; then
        rmdir -- "${tmp_dir}" 2>>"$log_file"
        info "Backup saved: ${dest}"
    else
        warn "UniFi OS Server backup could not be saved -alert"
        rm -f -- "${tmp_dir}/backup"
        rmdir -- "${tmp_dir}" 2>>"$log_file"
        return 1
    fi
}

action_uninstall_osserver() {
    get_installed_osserver
    if [ -z "${installed_osserver_version}" ]; then
        info "OS Server not installed, nothing to remove"
        return 0
    fi

    read -rp "Remove UniFi OS Server ${installed_osserver_version}? (y/N) " confirm
    case "$confirm" in
        [Yy]*) ;;
        *) info "Uninstall cancelled by user"; return 0 ;;
    esac

    local unit_path
    unit_path="$(systemctl show -p FragmentPath --value uosserver 2>/dev/null || true)"

    # Quiesce before the backup, recording whether it was running: a failed
    # backup below must leave the service exactly as it was found. Stopping
    # the unit stops its container, and starting it back brings the
    # container up again. The disable and
    # the container removal come after the backup.
    local was_active="no"
    systemctl is-active --quiet uosserver && was_active="yes"
    if ! systemctl stop uosserver >>"$log_file" 2>&1; then
        err "cannot stop uosserver, uninstall aborted"
        err "uosserver: run systemctl status uosserver -abort"
        return 1
    fi
    # A successful stop is not proof on its own, so the state is read back.
    # Aborting while the unit is still up leaves the service exactly as it
    # was found, so there is nothing to restore.
    if systemctl is-active --quiet uosserver; then
        err "uosserver still active after stop, uninstall aborted"
        err "uosserver: run systemctl status uosserver -abort"
        return 1
    fi

    echo "Note: UniFi OS Server does not keep a .unifi backup file on disk (UI"
    echo "generates it on demand and streams it straight to your browser)"
    echo "This backs up its persistent state directory (/var/lib/uosserver) instead,"
    echo "which is not same file format as UI's Backup button"
    read -rp "Back up /var/lib/uosserver before removing? (y/N) " do_backup
    case "$do_backup" in
        [Yy]*) backup_osserver_config || {
            err "uosserver backup failed; uninstall stopped -abort"
            if [ "${was_active}" = "yes" ]; then
                systemctl start uosserver >>"$log_file" 2>&1 ||
                    warn "cannot restart uosserver -alert"
            fi
            return 1
        } ;;
    esac

    systemctl disable --now uosserver >>"$log_file" 2>&1 || true

    if id -u uosserver >/dev/null 2>&1; then
        runuser -u uosserver -- podman stop -a 2>/dev/null || true
        runuser -u uosserver -- podman rm -fa 2>/dev/null || true
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
            warn "userdel uosserver failed, see unifisetup.log -alert"
        fi
    fi
    if getent group uosserver >/dev/null 2>&1; then
        if ! groupdel uosserver 2>>"$log_file"; then
            warn "could not remove group uosserver -alert"
        fi
    fi

    info "OS Server removed"
}

# ------------------------------------------------------------------------------
# STATUS
# ------------------------------------------------------------------------------

action_status() {
    local unit label properties load_state active_state key value query_status
    local installed

    if [ "$(dpkg-query -W -f='${db:Status-Status}' systemd 2>/dev/null)" != installed ]; then
        err "dependency 'systemd' is not installed -abort"
        return 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        err "systemctl command not found -abort"
        return 1
    fi

    for unit in unifi.service uosserver.service; do
        installed=0
        case "$unit" in
            unifi.service)
                label="UniFi Network"
                if [ "$(dpkg-query -W -f='${db:Status-Status}' unifi 2>/dev/null)" = installed ]; then
                    installed=1
                fi
                ;;
            uosserver.service)
                label="UniFi OS Server"
                [ -f /var/lib/uosserver/server.conf ] && installed=1
                ;;
        esac

        query_status=0
        properties="$(systemctl show "$unit" --property=LoadState --property=ActiveState 2>/dev/null)" || query_status=$?
        load_state=""
        active_state=""
        while IFS='=' read -r key value; do
            case "$key" in
                LoadState) load_state="$value" ;;
                ActiveState) active_state="$value" ;;
            esac
        done <<< "$properties"

        if [ "$load_state" = not-found ]; then
            if [ "$installed" -eq 1 ]; then
                echo "$label: not running ($unit not found)"
            else
                echo "$label: not installed"
            fi
            continue
        fi
        if [ "$query_status" -ne 0 ]; then
            err "cannot read $unit state -abort"
            return 1
        fi
        case "$load_state" in
            loaded|masked|error|bad-setting) ;;
            *)
                err "$unit: cannot determine unit load state -abort"
                return 1
                ;;
        esac
        case "$active_state" in
            active|reloading) echo "$label: running" ;;
            inactive|maintenance) echo "$label: not running" ;;
            failed) echo "$label: not running (failed)" ;;
            activating) echo "$label: starting" ;;
            deactivating) echo "$label: stopping" ;;
            *)
                err "$unit: cannot determine service state -abort"
                return 1
                ;;
        esac
    done
}

run_action() {
    if [ "$1" != action_status ]; then
        ensure_prereqs
        fetch_downloads_json
    fi
    "$1"
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
        echo "7. Show local installation and service status"
        echo "8. Exit"
        echo ""
        read -rp "Select an option (1-8): " choice || return 1
        case "$choice" in
            1) run_action action_install_network || exit 1; break ;;
            2) run_action action_install_osserver || exit 1; break ;;
            3) run_action action_update_network || exit 1; break ;;
            4) run_action action_update_osserver || exit 1; break ;;
            5) run_action action_uninstall_network || exit 1; break ;;
            6) run_action action_uninstall_osserver || exit 1; break ;;
            7) run_action action_status || exit 1; break ;;
            8) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

action="${1:-}"
component="${2:-}"
case "$action:$component" in
    :|--status:|--help:|-h:) ;;
    --install:network|--install:osserver|--update:network|--update:osserver|--uninstall:network|--uninstall:osserver) ;;
    *)
        echo "Usage: $0 [--install|--update|--uninstall] {network|osserver}"
        echo "       $0 [--status|--help]"
        exit 1
        ;;
esac
if [ "$action" = --help ] || [ "$action" = -h ]; then
    echo "Usage: $0 [--install|--update|--uninstall] {network|osserver}"
    echo "       $0 [--status|--help]"
    echo "Without arguments, opens the interactive menu"
    exit 0
fi

# Start
log "unifisetup start..."

os_check
arch_check

case "$action:$component" in
    --install:network) run_action action_install_network || exit 1 ;;
    --install:osserver) run_action action_install_osserver || exit 1 ;;
    --update:network) run_action action_update_network || exit 1 ;;
    --update:osserver) run_action action_update_osserver || exit 1 ;;
    --uninstall:network) run_action action_uninstall_network || exit 1 ;;
    --uninstall:osserver) run_action action_uninstall_osserver || exit 1 ;;
    --status:) run_action action_status || exit 1 ;;
    :) menu || exit 1 ;;
esac

log "unifisetup done at: $(date '+%Y-%m-%d %H:%M:%S')"
