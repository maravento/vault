#!/bin/bash
# maravento.com
#
# Winboat (Install | Remove)
#
# -----------------------------------------------------------------------------
# RDP connection recovery
#
# If the RDP window closes unexpectedly and reconnection fails, run:
#   pkill -f freerdp
# or:
#   flatpak kill com.freerdp.FreeRDP
#
# -----------------------------------------------------------------------------
# RDP limitations
#
# Winboat does NOT bypass Windows RDP session limits.
# FreeRDP is used strictly as an RDP client.
#
# Windows limits:
#   Windows 10/11 (all editions): 1 RDP session
#   Windows Server              : 2 admin sessions
#
# More sessions require RDS and valid CALs.
# -----------------------------------------------------------------------------

echo "Winboat Install | Remove Starting. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || "$UBUNTU_VERSION" != "24.04" ]]; then
    echo "Unsupported system. This script requires Ubuntu 24.04"
    exit 1
fi

# LOCAL USER
# Get real user (not root) - multiple fallback methods
local_user=$(logname 2>/dev/null || echo "$SUDO_USER")
# If not found or is root, try detecting active graphical user
if [ -z "$local_user" ] || [ "$local_user" = "root" ]; then
    local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}')
fi
# As a final fallback, take the first logged user
if [ -z "$local_user" ]; then
    local_user=$(who | head -1 | awk '{print $1}')
fi
# Clean possible spaces or line breaks
local_user=$(echo "$local_user" | xargs)

# Function to install Winboat
install_winboat() {
    echo "=== Installing Winboat ==="
    printf "\n"

    # Step 1: Install Docker + Portainer
    echo "[1/4] Installing Docker + Portainer..."
    if ! command -v docker &> /dev/null; then
        DOCKER_SCRIPT="/tmp/docker.sh"
        wget --show-progress https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/docker.sh -O "$DOCKER_SCRIPT"
        chmod +x "$DOCKER_SCRIPT"
        "$DOCKER_SCRIPT" install
        rm "$DOCKER_SCRIPT"
    else
        echo "Docker is already installed. Skipping..."
    fi
    printf "\n"

    # Step 2: Install FreeRDP
    echo "[2/4] Installing FreeRDP3..."
    
    # Check and remove Ubuntu repository version if installed (conflicts with Flatpak)
    if dpkg -l | grep -q freerdp3-x11; then
        echo "Found freerdp3-x11 from Ubuntu repository. Removing to avoid conflicts..."
        apt-get purge -y freerdp3-x11 || true
        apt-get autoremove -y || true
        echo "Ubuntu repository version removed"
    fi
    
    # Install FreeRDP from Flatpak (fixes bugs present in Ubuntu 24.04 repository version)
    if ! flatpak list 2>/dev/null | grep -q "com.freerdp.FreeRDP"; then
        echo "Installing Flatpak if not present..."
        apt-get update
        apt-get install -y flatpak
        
        echo "Adding Flathub repository..."
        flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
        
        echo "Installing FreeRDP from Flatpak..."
        flatpak install --system -y flathub com.freerdp.FreeRDP
        echo "FreeRDP3 installed successfully from Flatpak"
    else
        echo "FreeRDP3 (Flatpak) is already installed. Skipping..."
    fi
    printf "\n"

    # Step 3: Install Winboat
    echo "[3/4] Installing Winboat..."
    if ! command -v winboat &> /dev/null; then
        echo "Fetching latest Winboat release..."
        DEB_URL=$(curl -s https://api.github.com/repos/TibixDev/winboat/releases/latest | grep -oP '"browser_download_url": "\K[^"]*\.deb')
        
        if [ -z "$DEB_URL" ]; then
            echo "Error: Could not fetch Winboat download URL"
            exit 1
        fi

        echo "Downloading Winboat..."
        wget -q --show-progress "$DEB_URL" -O /tmp/winboat.deb
        
        echo "Installing Winboat package..."
        dpkg -i /tmp/winboat.deb
        apt-get install -f -y
        rm /tmp/winboat.deb
        
        echo "Winboat installed successfully!"
    else
        echo "Winboat is already installed. Skipping..."
    fi
    printf "\n"

    # Step 4: Offer reboot
    echo "[4/4] Installation completed!"
    printf "\n"
    read -p "Do you want to reboot the system now? (y/n): " reboot_choice
    case $reboot_choice in
        [Yy]*)
            echo "Rebooting system..."
            reboot
            ;;
        *)
            echo "Reboot skipped. Please reboot manually to complete the installation."
            ;;
    esac
}

# Function to remove Winboat
uninstall_winboat() {
    echo "=== Uninstalling Winboat ==="
    printf "\n"
    
    echo "WARNING: This will remove:"
    echo "  - Winboat application"
    echo "  - Docker containers and volumes"
    echo "  - Configuration files (.winboat, .config/winboat)"
    echo "  - Work directory (/home/$local_user/winboat) if exists"
    printf "\n"
    read -p "Do you want to continue? (y/n): " confirm_removal
    case $confirm_removal in
        [Yy]*)
            echo "Proceeding with uninstallation..."
            ;;
        *)
            echo "Uninstallation cancelled"
            return
            ;;
    esac
    printf "\n"

    # Step 1: Stop Winboat processes
    echo "[1/5] Stopping Winboat processes..."
    pkill -f "^winboat$" 2>/dev/null || true
    pkill -f xfreerdp3 2>/dev/null || true
    sleep 2
    printf "\n"

    # Step 2: Stop and remove Winboat Docker containers
    echo "[2/5] Removing Winboat Docker containers..."
    WINBOAT_CONTAINERS=$(docker ps -a --filter "name=WinBoat" --format "{{.ID}}" 2>/dev/null)
    if [ -n "$WINBOAT_CONTAINERS" ]; then
        echo "Found Winboat containers, stopping and removing..."
        docker stop $WINBOAT_CONTAINERS 2>/dev/null || true
        docker rm $WINBOAT_CONTAINERS 2>/dev/null || true
        echo "Winboat containers removed"
    else
        echo "No Winboat containers found"
    fi
    
    # Remove Winboat Docker volumes
    WINBOAT_VOLUMES=$(docker volume ls --format "{{.Name}}" 2>/dev/null | grep -i winboat)
    if [ -n "$WINBOAT_VOLUMES" ]; then
        echo "Found Winboat volumes, removing..."
        echo "$WINBOAT_VOLUMES" | xargs -r docker volume rm 2>/dev/null || true
        echo "Winboat volumes removed"
    fi
    printf "\n"

    # Step 3: Uninstall Winboat package
    echo "[3/5] Uninstalling Winboat package..."
    if dpkg-query -W -f='${Status}' winboat 2>/dev/null | grep -q "install ok installed"; then
        apt-get purge -y winboat || true
        apt-get autoremove -y || true
        apt-get clean || true
        
        # Remove configuration files
        if [ -n "$local_user" ] && [ "$local_user" != "root" ]; then
            rm -rf /home/$local_user/.config/winboat || true
            rm -rf /home/$local_user/.winboat || true
        fi
        rm -rf /var/cache/apparmor/*/winboat || true
        echo "Winboat package removed"
    else
        echo "Winboat package is not installed"
    fi
    printf "\n"

    # Step 4: Remove winboat work directory
    echo "[4/5] Removing winboat work directory..."
    if [ -n "$local_user" ] && [ "$local_user" != "root" ] && [ -d "/home/$local_user/winboat" ]; then
        rm -rf /home/$local_user/winboat || true
        echo "Winboat directory removed"
    else
        echo "No winboat work directory found"
    fi
    printf "\n"

    # Step 5: Ask to remove dependencies
    echo "[5/5] Cleaning up dependencies..."
    printf "\n"
    
    read -p "Do you want to remove FreeRDP3? (y/n): " remove_freerdp
    case $remove_freerdp in
        [Yy]*)
            echo "Removing FreeRDP3..."
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
            echo "Removing Docker..."
            DOCKER_SCRIPT="/tmp/docker.sh"
            wget --show-progress https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/docker.sh -O "$DOCKER_SCRIPT"
            chmod +x "$DOCKER_SCRIPT"
            "$DOCKER_SCRIPT" remove
            rm "$DOCKER_SCRIPT"
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
    echo "Usage: $0 [COMMAND]"
    echo "Commands:"
    echo "  install    Install Winboat + Dependencies (Docker, FreeRDP)"
    echo "  remove     Uninstall Winboat"
    echo ""
    echo "If no command is provided, interactive mode will start."
    exit 0
}

# Main execution logic
if [ $# -eq 0 ]; then
    # Interactive mode
    echo "What action do you want to perform?"
    echo "1) Install Winboat + Dependencies"
    echo "2) Uninstall Winboat"
    echo "3) Exit"
    read -p "Select an option (1, 2 or 3): " option

    case $option in
      1)
        install_winboat
        ;;
      2)
        uninstall_winboat
        ;;
      3)
        echo "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid option"
        exit 1
        ;;
    esac
else
    # Command line mode
    case $1 in
        install)
            install_winboat
            ;;
        remove)
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
