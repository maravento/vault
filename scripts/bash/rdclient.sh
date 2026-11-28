#!/bin/bash
# maravento.com
#
################################################################################
#
# RustDesk Client Install
# FILE: rdclient.sh
#
# DESCRIPTION: Installs or removes the RustDesk client, and sets the keyboard
# layout that matches the system language.
#
# USAGE:
# COMMAND                ACTION
# sudo bash rdclient.sh  Run (no arguments)
#
################################################################################

set -euo pipefail

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# awk is a command, not a package: check it before its first use
command -v awk >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: awk not found -abort" >&2; exit 1; }

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
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no local user; create one with sudo access -abort" >&2
    exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: using local user: $local_user"

user_lang=$(locale | grep LANG= | cut -d= -f2 | cut -d_ -f1) || true

export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no interface with IPv4 -abort" >&2
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: no internet connection -abort" >&2
    exit 1
}

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# dependencies (network checks, before the menu)
net_checked=0
for dep in iproute2 libc-bin coreutils grep sed curl wget lsof; do
    if [[ "$(dpkg-query -W -f='${Status}' "$dep" 2>/dev/null)" != *"ok installed"* ]]; then
        if [ "$net_checked" -eq 0 ]; then
            if ! command -v ip >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing iproute2"
                apt-get install -y iproute2 >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install iproute2 -abort" >&2; exit 1; }
                # the download proves link and internet; only IPv4 is left to check
                check_ipv4_interfaces
            else
                check_ipv4_interfaces
                check_internet
            fi
            apt-get update -qq || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2; exit 1; }
            net_checked=1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: installing $dep"
        if ! apt-get install -y "$dep" >/dev/null 2>&1; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install $dep -abort" >&2
            exit 1
        fi
    fi
done

retry_cmd() {
    [ "$#" -ge 2 ] || return 2
    local retry_label="$1" retry_attempt retry_status
    shift
    for retry_attempt in 1 2 3; do
        if "$@"; then
            return 0
        else
            retry_status=$?
        fi
        [ "$retry_attempt" -lt 3 ] || return "$retry_status"
        if declare -F log >/dev/null; then
            log "INFO: $retry_label: retry $((retry_attempt + 1))/3" >&2
        else
            printf '%s INFO: %s: retry %s/3\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "$retry_label" \
                "$((retry_attempt + 1))" >&2
        fi
        sleep 5
    done
}

# RustDesk's own packages; the tools the script uses are initial dependencies
check_dependencies() {
    pkgs='libclang-dev ninja-build libayatana-appindicator3-1 libgstreamer1.0-dev libayatana-appindicator3-dev'
    missing=()
    for p in $pkgs; do
        [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == *"ok installed"* ]] || missing+=("$p")
    done
    unavailable=()
    for p in "${missing[@]}"; do
        apt-cache show "$p" &>/dev/null || unavailable+=("$p")
    done

    if [ ${#unavailable[@]} -gt 0 ]; then
        for u in "${unavailable[@]}"; do echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: dependency not found in APT: $u -alert"; done
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: install them manually or enable repos -abort" >&2
        exit 1
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing missing dependencies: ${missing[*]}"
        apt_lock_timeout=120
        apt_lock_elapsed=0
        apt_lock_files="/var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend"
        while lsof $apt_lock_files >/dev/null 2>&1; do
            if [ "$apt_lock_elapsed" -ge "$apt_lock_timeout" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: APT/DPKG locks still held after ${apt_lock_timeout}s -abort" >&2
                exit 1
            fi
            echo "   Locks still held, waiting... (${apt_lock_elapsed}s elapsed)"
            sleep 5
            apt_lock_elapsed=$((apt_lock_elapsed + 5))
        done
        if ! retry_cmd "update package lists" apt-get -qq update; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to update package lists -abort" >&2
            exit 1
        fi
        if ! retry_cmd "install packages" apt-get install -y "${missing[@]}"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install dependencies -abort" >&2
            exit 1
        fi
    fi

    # rustdesk depends on libxdo3 | libxdo4 (either one satisfies it)
    if [[ "$(dpkg-query -W -f='${Status}' libxdo3 2>/dev/null)" != *"ok installed"* ]] && [[ "$(dpkg-query -W -f='${Status}' libxdo4 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing missing dependency: libxdo3"
        if ! retry_cmd "install packages" apt-get install -y libxdo3; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install libxdo3 -abort" >&2
            exit 1
        fi
    fi
}

setup_keyboard() {
    if [ -z "$local_user" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: local user not found, keyboard setup -skip"
        return
    fi

    user_home=$(getent passwd "$local_user" | cut -d: -f6)
    xprofile_path="$user_home/.xprofile"
    local_group=$(id -gn "$local_user")

    if [ ! -f "$xprofile_path" ]; then
        touch "$xprofile_path"
        chown "$local_user:$local_group" "$xprofile_path" 2>/dev/null || true
    fi

    case "$user_lang" in
        es) kb_layout="latam" ;;
        en) kb_layout="us" ;;
        fr) kb_layout="fr" ;;
        de) kb_layout="de" ;;
        it) kb_layout="it" ;;
        pt) kb_layout="br" ;;
        ru) kb_layout="ru" ;;
        ja) kb_layout="jp" ;;
        zh) kb_layout="cn" ;;
        ko) kb_layout="kr" ;;
        ar) kb_layout="ara" ;;
        tr) kb_layout="tr" ;;
        pl) kb_layout="pl" ;;
        nl) kb_layout="nl" ;;
        sv) kb_layout="se" ;;
        no) kb_layout="no" ;;
        da) kb_layout="dk" ;;
        fi) kb_layout="fi" ;;
        cs) kb_layout="cz" ;;
        hu) kb_layout="hu" ;;
        ro) kb_layout="ro" ;;
        el) kb_layout="gr" ;;
        he) kb_layout="il" ;;
        th) kb_layout="th" ;;
        vi) kb_layout="vn" ;;
        *) kb_layout="us" ;;
    esac

    if ! grep -q "setxkbmap $kb_layout" "$xprofile_path"; then
        echo "setxkbmap $kb_layout # rdclient managed" >> "$xprofile_path"
        chown "$local_user:$local_group" "$xprofile_path" 2>/dev/null || true
    fi
}

install_rustdesk() {
    check_ipv4_interfaces
    check_internet
    check_dependencies

    ver_tag=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//' || true)
    if [ -z "$ver_tag" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to fetch latest version -abort" >&2
        exit 1
    fi

    if dpkg -l rustdesk 2>/dev/null | grep -q '^ii'; then
        installed_ver=$(dpkg -l rustdesk | grep '^ii' | awk '{print $3}')
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk installed: $installed_ver"
    else
        installed_ver=""
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk not installed"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Latest version: $ver_tag"

    if [ "$installed_ver" = "$ver_tag" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: already at latest version"
        return
    fi

    deb_file="rustdesk-${ver_tag}-x86_64.deb"
    base_url="https://github.com/rustdesk/rustdesk/releases/download/${ver_tag}"

    # Private directory: another user cannot plant the package
    deb_dir=$(mktemp -d) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create temporary directory -abort" >&2; exit 1; }
    trap 'rm -rf -- "$deb_dir"' EXIT
    if ! retry_cmd "download package" wget --tries=1 -q -O "$deb_dir/$deb_file" "${base_url}/${deb_file}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: download failed -abort" >&2
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing package..."
    dpkg_out=$(mktemp)
    if dpkg -i "$deb_dir/$deb_file" >"$dpkg_out" 2>&1; then
        setup_keyboard
        # The .deb's own postinst enables and starts rustdesk.service on its
        # own; undo that here so the package is installed but not running
        # until the user starts it manually.
        systemctl stop rustdesk 2>/dev/null || true
        systemctl disable rustdesk 2>/dev/null || true
        rm -f "$dpkg_out"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk $ver_tag installed"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: service stopped; start: sudo systemctl start rustdesk"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: start on boot: sudo systemctl enable rustdesk"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: installation failed -abort" >&2
        cat "$dpkg_out" >&2
        rm -f "$dpkg_out"
        exit 1
    fi
}

remove_rustdesk() {
    if ! dpkg -l rustdesk 2>/dev/null | grep -q '^ii'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk is not installed"
        return
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Removing RustDesk..."
    apt_out=$(mktemp)
    if apt-get remove --purge -y rustdesk >"$apt_out" 2>&1; then
        rm -f "$apt_out"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk removed"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to remove RustDesk -abort" >&2
        cat "$apt_out" >&2
        rm -f "$apt_out"
        exit 1
    fi

    # apt-get purge only removes what dpkg tracks. The client also leaves
    # per-user runtime state it creates itself (dpkg never sees it), plus
    # the .xprofile line this script added in setup_keyboard().
    if [ -n "$local_user" ]; then
        user_home=$(getent passwd "$local_user" | cut -d: -f6)
        user_uid=$(id -u "$local_user" 2>/dev/null || true)

        xprofile_path="$user_home/.xprofile"
        [ -f "$xprofile_path" ] && sed -i -E '/^setxkbmap [a-z]+ # rdclient managed$/d' "$xprofile_path"

        rm -rf "$user_home/.local/share/logs/RustDesk"
        [ -n "$user_uid" ] && rm -rf "/tmp/RustDesk-service" "/tmp/RustDesk-$user_uid"

        if [ -d "$user_home/.config/rustdesk" ]; then
            if read -rp "Also delete saved profiles/connections at $user_home/.config/rustdesk? (y/n): " user_response &&
                [[ "$user_response" =~ ^[Yy]$ ]]; then
                rm -rf "$user_home/.config/rustdesk"
            fi
        fi

        if [ -d "$user_home/Videos/RustDesk" ]; then
            if read -rp "Also delete recordings at $user_home/Videos/RustDesk? (y/n): " user_response &&
                [[ "$user_response" =~ ^[Yy]$ ]]; then
                rm -rf "$user_home/Videos/RustDesk"
            fi
        fi
    fi
}

show_menu() {
    echo ""
    echo "==== RustDesk Client Manager ===="
    echo "1. Install / Update RustDesk Client"
    echo "2. Remove RustDesk Client"
    echo "3. Exit"
    echo -n "Select an option [3]: "
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: rdclient start..."

show_menu
read -r option
echo ""
if [ -z "$option" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no option selected, exit -skip"
    option=3
fi

case $option in
    1)
        install_rustdesk
        ;;
    2)
        remove_rustdesk
        ;;
    3)
        ;;
    *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: rdclient done"
