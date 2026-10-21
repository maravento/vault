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
for dep in wget curl util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') winboat start..."

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

# Function to install Winboat
install_winboat() {
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
        apt-get purge -y freerdp3-x11 || true
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') Fetching latest Winboat release..."
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
    winboat_containers=$(docker ps -a --filter "name=WinBoat" --format "{{.ID}}" 2>/dev/null)
    if [ -n "$winboat_containers" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Found Winboat containers, stopping and removing..."
        docker stop $winboat_containers 2>/dev/null || true
        docker rm $winboat_containers 2>/dev/null || true
        echo "Winboat containers removed"
    else
        echo "No Winboat containers found"
    fi

    # Remove Winboat Docker volumes
    winboat_volumes=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -i winboat)
    if [ -n "$winboat_volumes" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') Found Winboat volumes, removing..."
        echo "$winboat_volumes" | xargs -r docker volume rm 2>/dev/null || true
        echo "Winboat volumes removed"
    fi
    printf "\n"

    # Step 3: Uninstall Winboat package
    echo "$(date '+%Y-%m-%d %H:%M:%S') [3/5] Uninstalling Winboat package..."
    if dpkg-query -W -f='${Status}' winboat 2>/dev/null | grep -q "install ok installed"; then
        apt-get purge -y winboat || true
        apt-get autoremove -y || true
        apt-get clean || true

        # Remove configuration files
        if [ -n "$local_user" ] && [ "$local_user" != "root" ]; then
            rm -rf "/home/$local_user/.config/winboat" || true
            rm -rf "/home/$local_user/.winboat" || true
        fi
        rm -rf /var/cache/apparmor/*/winboat || true
        echo "Winboat package removed"
    else
        echo "Winboat package is not installed"
    fi
    printf "\n"

    # Step 4: Remove winboat work directory
    echo "$(date '+%Y-%m-%d %H:%M:%S') [4/5] Removing winboat work directory..."
    if [ -n "$local_user" ] && [ "$local_user" != "root" ] && [ -d "/home/$local_user/winboat" ]; then
        rm -rf "/home/$local_user/winboat" || true
        echo "Winboat directory removed"
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
            flatpak uninstall -y com.freerdp.FreeRDP 2>/dev/null || true
            echo "FreeRDP3 has been removed"
            ;;
        *)
            echo "FreeRDP3 kept installed"
            ;;
    esac
    printf "\n"

    read -p "Do you want to remove Docker? (y/n): " remove_docker
    case $remove_docker in
        [Yy]*)
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

    echo "=== Winboat uninstallation completed ==="
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
        uninstall_winboat
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
            uninstall_winboat
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
echo "$(date '+%Y-%m-%d %H:%M:%S') winboat done at: $(date '+%Y-%m-%d %H:%M:%S')"
