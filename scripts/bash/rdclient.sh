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
# USAGE: sudo bash rdclient.sh
#
################################################################################

set -euo pipefail

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
echo "Using local user: $local_user"

user_lang=$(locale | grep LANG= | cut -d= -f2 | cut -d_ -f1) || true

export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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

retry_cmd() {
    local max_attempts=10
    local attempt=1
    local retry_name retry_failure retry_arg
    retry_name="$(basename "$1")"
    retry_failure="$retry_name failed"
    case "$retry_name" in
        apt-get)
            for retry_arg in "$@"; do
                case "$retry_arg" in
                    install) retry_failure="package installation failed"; break ;;
                    update) retry_failure="package list update failed"; break ;;
                esac
            done
            ;;
        curl|wget) retry_failure="$retry_name download failed" ;;
    esac
    until "$@"; do
        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: $retry_failure -abort" >&2
            exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: $retry_name: retry $((attempt + 1))/$max_attempts"
        attempt=$((attempt + 1))
        sleep 10
    done
}

check_dependencies() {
    if [[ "$(dpkg-query -W -f='${Status}' curl 2>/dev/null)" != *"ok installed"* ]]; then
        if ! retry_cmd apt-get -qq update; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to update package lists while preparing curl -abort"
            exit 1
        fi
        if ! retry_cmd apt-get install -y curl; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install curl -abort"
            exit 1
        fi
    fi

    pkgs='libclang-dev ninja-build libayatana-appindicator3-1 libgstreamer1.0-dev libayatana-appindicator3-dev wget'
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: install them manually, or enable required repos -abort"
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
        if ! retry_cmd apt-get -qq update; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to update package lists -abort"
            exit 1
        fi
        if ! retry_cmd apt-get install -y "${missing[@]}"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install dependencies -abort"
            exit 1
        fi
    fi

    # rustdesk depends on libxdo3 | libxdo4 (either one satisfies it)
    if [[ "$(dpkg-query -W -f='${Status}' libxdo3 2>/dev/null)" != *"ok installed"* ]] && [[ "$(dpkg-query -W -f='${Status}' libxdo4 2>/dev/null)" != *"ok installed"* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Installing missing dependency: libxdo3"
        if ! retry_cmd apt-get install -y libxdo3; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install libxdo3 -abort"
            exit 1
        fi
    fi
}

setup_keyboard() {
    if [ -z "$local_user" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: could not detect local user, skipping keyboard setup -skip"
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
        echo "setxkbmap $kb_layout" >> "$xprofile_path"
        chown "$local_user:$local_group" "$xprofile_path" 2>/dev/null || true
    fi
}

install_rustdesk() {
    check_ipv4_interfaces
    check_internet
    check_dependencies

    ver_tag=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//' || true)
    if [ -z "$ver_tag" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to fetch latest version -abort"
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
        echo "OK: You already have latest version. Nothing to do"
        return
    fi

    deb_file="rustdesk-${ver_tag}-x86_64.deb"
    base_url="https://github.com/rustdesk/rustdesk/releases/download/${ver_tag}"

    cd /tmp
    if ! retry_cmd wget -q "${base_url}/${deb_file}"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: download failed -abort"
        rm -f "$deb_file"
        exit 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Installing package..."
    dpkg_out=$(mktemp)
    if dpkg -i "./$deb_file" >"$dpkg_out" 2>&1; then
        setup_keyboard
        # The .deb's own postinst enables and starts rustdesk.service on its
        # own; undo that here so the package is installed but not running
        # until the user starts it manually.
        systemctl stop rustdesk 2>/dev/null || true
        systemctl disable rustdesk 2>/dev/null || true
        rm -f "$deb_file" "$dpkg_out"
        echo "OK: RustDesk $ver_tag installed successfully"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Service stopped. To start it now: sudo systemctl start rustdesk"
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: To start it on every boot: sudo systemctl enable rustdesk"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: installation failed -abort"
        cat "$dpkg_out" >&2
        rm -f "$deb_file" "$dpkg_out"
        exit 1
    fi
}

remove_rustdesk() {
    if ! dpkg -l rustdesk 2>/dev/null | grep -q '^ii'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: RustDesk is not installed"
        return
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') Removing RustDesk..."
    apt_out=$(mktemp)
    if apt-get remove --purge -y rustdesk >"$apt_out" 2>&1; then
        rm -f "$apt_out"
        echo "OK: RustDesk removed successfully"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to remove RustDesk -abort"
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
        [ -f "$xprofile_path" ] && sed -i '/^setxkbmap /d' "$xprofile_path"

        rm -rf "$user_home/.local/share/logs/RustDesk"
        [ -n "$user_uid" ] && rm -rf "/tmp/RustDesk-service" "/tmp/RustDesk-$user_uid"

        if [ -d "$user_home/.config/rustdesk" ]; then
            read -rp "Also delete saved profiles/connections at $user_home/.config/rustdesk? (y/n): " user_response
            [[ "$user_response" =~ ^[Yy]$ ]] && rm -rf "$user_home/.config/rustdesk"
        fi

        if [ -d "$user_home/Videos/RustDesk" ]; then
            read -rp "Also delete recordings at $user_home/Videos/RustDesk? (y/n): " user_response
            [[ "$user_response" =~ ^[Yy]$ ]] && rm -rf "$user_home/Videos/RustDesk"
        fi
    fi
}

show_menu() {
    echo "================================"
    echo "   RUSTDESK CLIENT MANAGER"
    echo "================================"
    echo "1. Install / Update RustDesk Client"
    echo "2. Remove RustDesk Client"
    echo "3. Exit"
    echo "================================"
    echo -n "Select an option: "
}

# ------------------------------------------------------------------------------
# MENU
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: rdclient start..."

show_menu
read -r option

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
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort"
        exit 1
        ;;
esac

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: rdclient done"
