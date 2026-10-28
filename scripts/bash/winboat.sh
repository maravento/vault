#!/bin/bash
# maravento.com
#
################################################################################
#
# Winboat (Install | Remove)
# FILE: winboat.sh
#
# DESCRIPTION:
# Installs or removes Winboat, a Windows-in-a-container runner that uses
# FreeRDP strictly as an RDP client -- it does not bypass Windows RDP
# session limits.
#
# USAGE: sudo bash winboat.sh [--install|--uninstall|--help]
#
################################################################################

set -uo pipefail

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

# dependencies
for dep in wget curl util-linux iproute2 libc-bin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: winboat start..."

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

# Function to install Winboat
install_winboat() {
    check_ipv4_interfaces
    check_internet
    echo "=== Installing Winboat ==="
    printf "\n"

    # Step 1: Install Docker + Portainer
    echo "$(date '+%Y-%m-%d %H:%M:%S') [1/4] Installing Docker + Portainer..."
    if ! command -v docker &> /dev/null; then
        docker_script=$(mktemp /tmp/docker.XXXXXX.sh)
        if ! wget --timeout=30 --show-progress https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/docker.sh -O "$docker_script"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/docker.sh"
            exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: docker.sh"
        chmod +x "$docker_script"
        if ! "$docker_script" --install; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: docker.sh --install failed -abort"
            rm -f "$docker_script"
            exit 1
        fi
        rm "$docker_script"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') Docker is already installed. Skipping..."
    fi
    printf "\n"

    # Step 2: Install FreeRDP
    echo "$(date '+%Y-%m-%d %H:%M:%S') [2/4] Installing FreeRDP3..."

    # Check and remove Ubuntu repository version if installed (conflicts with Flatpak)
    if dpkg -l | grep -q freerdp3-x11; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Found freerdp3-x11 from Ubuntu repository. Removing to avoid conflicts..."
        if ! apt-get purge -y freerdp3-x11; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot purge freerdp3-x11 -abort" >&2
            exit 1
        fi
        apt-get autoremove -y || true
        echo "Ubuntu repository version removed"
    fi

    # Install FreeRDP from Flatpak (fixes bugs present in Ubuntu 24.04 repository version)
    if ! flatpak list 2>/dev/null | grep -q "com.freerdp.FreeRDP"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Installing Flatpak if not present..."
        if ! apt-get update; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: apt-get update failed -fallback"
        fi
        if ! apt-get install -y flatpak; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install flatpak -abort"
            exit 1
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') Adding Flathub repository..."
        flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

        echo "$(date '+%Y-%m-%d %H:%M:%S') Installing FreeRDP from Flatpak..."
        if ! flatpak install --system -y flathub com.freerdp.FreeRDP; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to install FreeRDP from Flatpak -abort"
            exit 1
        fi
        echo "FreeRDP3 installed successfully from Flatpak"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') FreeRDP3 (Flatpak) is already installed. Skipping..."
    fi
    printf "\n"

    # Step 3: Install Winboat
    echo "$(date '+%Y-%m-%d %H:%M:%S') [3/4] Installing Winboat..."
    if ! command -v winboat &> /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: Fetching latest Winboat release..."
        deb_url=$(curl -sL https://api.github.com/repos/TibixDev/winboat/releases/latest | grep -oP '"browser_download_url": "\K[^"]*\.deb')

        if [ -z "$deb_url" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: could not fetch Winboat download URL -abort"
            exit 1
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') Downloading Winboat..."
        winboat_deb=$(mktemp /tmp/winboat.XXXXXX.deb)
        if ! wget -q --timeout=30 --show-progress \
                "$deb_url" -O "$winboat_deb"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to download Winboat package -abort"
            rm -f "$winboat_deb"
            exit 1
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') Installing Winboat package..."
        dpkg -i "$winboat_deb" || true
        if ! apt-get install -f -y; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: failed to resolve Winboat dependencies -abort"
            rm -f "$winboat_deb"
            exit 1
        fi
        rm -f "$winboat_deb"

        if ! command -v winboat &> /dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Winboat is not installed after setup -abort"
            exit 1
        fi
        echo "Winboat installed successfully!"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') Winboat is already installed. Skipping..."
    fi
    printf "\n"

    # Step 4: Offer reboot
    echo "[4/4] Installation completed!"
    printf "\n"
    read -p "Do you want to reboot the system now? (y/n): " reboot_choice
    case $reboot_choice in
        [Yy]*)
            echo "$(date '+%Y-%m-%d %H:%M:%S') Rebooting system..."
            reboot
            ;;
        *)
            echo "Reboot skipped. Please reboot manually to complete installation"
            ;;
    esac
}

# Function to remove Winboat
uninstall_winboat() {
    local purge_failed=0
    local cleanup_failed=0
    echo "=== Uninstalling Winboat ==="
    printf "\n"

    echo "This will remove:"
    echo "  - Winboat application"
    echo "  - Docker containers and volumes"
    echo "  - Configuration files (.winboat, .config/winboat)"
    echo "  - Work directory (/home/$local_user/winboat) if exists"
    printf "\n"
    read -p "Do you want to continue? (y/n): " confirm_removal
    case $confirm_removal in
        [Yy]*)
            echo "$(date '+%Y-%m-%d %H:%M:%S') Proceeding with uninstallation..."
            ;;
        *)
            echo "Uninstallation cancelled"
            return
            ;;
    esac
    printf "\n"

    # Step 1: Stop Winboat processes
    echo "$(date '+%Y-%m-%d %H:%M:%S') [1/5] Stopping Winboat processes..."
    pkill -x winboat 2>/dev/null || true
    pkill -f xfreerdp3 2>/dev/null || true
    sleep 2
    printf "\n"

    # Step 2: Stop and remove Winboat Docker containers
    echo "$(date '+%Y-%m-%d %H:%M:%S') [2/5] Removing Winboat Docker containers..."
    if ! winboat_containers=$(docker ps -a --filter "name=WinBoat" --format "{{.ID}}" 2>/dev/null); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot list containers -alert"
        cleanup_failed=1
        winboat_containers=""
    fi
    if [ -n "$winboat_containers" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Found Winboat containers, stopping and removing..."
        docker stop $winboat_containers 2>/dev/null || true
        docker rm $winboat_containers 2>/dev/null || true
        if remaining=$(docker ps -a --filter "name=WinBoat" --format "{{.ID}}" 2>/dev/null); then
            if [ -n "$remaining" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Winboat containers pending -alert"
                cleanup_failed=1
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Winboat containers removed"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot verify containers -alert"
            cleanup_failed=1
        fi
    else
        echo "No Winboat containers found"
    fi

    # Remove Winboat Docker volumes
    if winboat_volumes_all=$(docker volume ls --format "{{.Name}}" 2>/dev/null); then
        winboat_volumes=$(echo "$winboat_volumes_all" | grep -i winboat || true)
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot list volumes -alert"
        cleanup_failed=1
        winboat_volumes=""
    fi
    if [ -n "$winboat_volumes" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Found Winboat volumes, removing..."
        echo "$winboat_volumes" | xargs -r docker volume rm 2>/dev/null || true
        if volumes_now=$(docker volume ls --format "{{.Name}}" 2>/dev/null); then
            if echo "$volumes_now" | grep -qi winboat; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Winboat volumes pending -alert"
                cleanup_failed=1
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Winboat volumes removed"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: cannot verify volumes -alert"
            cleanup_failed=1
        fi
    fi
    printf "\n"

    # Step 3: Uninstall Winboat package
    echo "$(date '+%Y-%m-%d %H:%M:%S') [3/5] Uninstalling Winboat package..."
    if dpkg-query -W -f='${Status}' winboat 2>/dev/null | grep -q "install ok installed"; then
        if ! apt-get purge -y winboat; then
            purge_failed=1
        fi
        apt-get autoremove -y || true
        apt-get clean || true

        # Remove configuration files
        if [ -n "$local_user" ] && [ "$local_user" != "root" ]; then
            rm -rf "/home/$local_user/.config/winboat" || true
            rm -rf "/home/$local_user/.winboat" || true
        fi
        rm -rf /var/cache/apparmor/*/winboat || true
        if [ "$purge_failed" -eq 0 ]; then
            echo "Winboat package removed"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Winboat package pending -alert"
        fi
    else
        echo "Winboat package is not installed"
    fi
    printf "\n"

    # Step 4: Remove winboat work directory
    echo "$(date '+%Y-%m-%d %H:%M:%S') [4/5] Removing winboat work directory..."
    if [ -n "$local_user" ] && [ "$local_user" != "root" ] && [ -d "/home/$local_user/winboat" ]; then
        rm -rf "/home/$local_user/winboat" || true
        if [ -d "/home/$local_user/winboat" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: winboat directory pending -alert"
            cleanup_failed=1
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: winboat directory removed"
        fi
    else
        echo "No winboat work directory found"
    fi
    printf "\n"

    # Step 5: Ask to remove dependencies
    echo "$(date '+%Y-%m-%d %H:%M:%S') [5/5] Cleaning up dependencies..."
    printf "\n"

    read -p "Do you want to remove FreeRDP3? (y/n): " remove_freerdp
    case $remove_freerdp in
        [Yy]*)
            echo "$(date '+%Y-%m-%d %H:%M:%S') Removing FreeRDP3..."
            if flatpak uninstall -y com.freerdp.FreeRDP >/dev/null 2>&1; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: FreeRDP3 removed"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: FreeRDP3 removal failed -alert"
                cleanup_failed=1
            fi
            ;;
        *)
            echo "FreeRDP3 kept installed"
            ;;
    esac
    printf "\n"

    read -p "Do you want to remove Docker? (y/n): " remove_docker
    case $remove_docker in
        [Yy]*)
            check_ipv4_interfaces
            check_internet
            echo "$(date '+%Y-%m-%d %H:%M:%S') Removing Docker..."
            docker_script=$(mktemp /tmp/docker.XXXXXX.sh)
            if ! wget --timeout=30 --show-progress https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/docker.sh -O "$docker_script"; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/docker.sh"
                exit 1
            fi
            echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: docker.sh"
            chmod +x "$docker_script"
            "$docker_script" --uninstall
            rm "$docker_script"
            ;;
        *)
            echo "Docker kept installed"
            ;;
    esac
    printf "\n"

    if [ "$purge_failed" -gt 0 ] || [ "$cleanup_failed" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Winboat uninstalled, cleanup pending -alert"
        return 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Winboat uninstallation completed"
}

# Show help
show_help() {
    echo "Usage: $0 [--install|--uninstall|--help]"
    echo "Commands:"
    echo "  --install    Install Winboat + Dependencies (Docker, FreeRDP)"
    echo "  --uninstall  Uninstall Winboat"
    echo ""
    echo "If no command is provided, interactive mode will start"
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Main execution logic
if [ $# -eq 0 ]; then
    # Interactive mode
    echo "What action do you want to perform?"
    echo "1) Install Winboat + Dependencies"
    echo "2) Uninstall Winboat"
    echo "3) Exit"
    read -p "Select an option [3]: " option
    option="${option:-3}"

    case $option in
      1)
        install_winboat
        ;;
      2)
        uninstall_winboat || exit 1
        ;;
      3)
        ;;
      *)
        echo "Invalid option"
        exit 1
        ;;
    esac
else
    # Command line mode
    case $1 in
        --install)
            install_winboat
            ;;
        --uninstall)
            uninstall_winboat || exit 1
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: winboat done"
