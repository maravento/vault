#!/bin/bash
# maravento.com
#
# Docker + Portainer (Install | Remove)

echo "Docker Install | Remove Starting. Wait..."
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
    echo "This script requires Ubuntu 24.04. Use at your own risk"
    # exit 1
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

# Function to install Docker and docker-compose-plugin
install_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Proceeding with installation..."
    apt-get install -y ca-certificates curl gnupg lsb-release

    # GPG
    rm -f /etc/apt/keyrings/docker.gpg > /dev/null
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Add Repo
    echo \
      "deb [arch=$(dpkg --print-architecture) \
      signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    #apt install -y docker.io docker-compose-plugin
    mkdir -p /etc/docker
    docker compose version
    systemctl start docker
    systemctl enable docker
    usermod -aG docker $local_user
    docker volume create portainer_data
    docker run -d -p 9000:9000 --name portainer --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data portainer/portainer-ce
    #docker run hello-world
    echo "Docker + Portainer has been installed successfully"
    echo "Access: http://localhost:9000/"
  else
    echo "Docker is already installed"
  fi
}

# Docker uninstall function
uninstall_docker() {
  if command -v docker &> /dev/null; then
    echo "Docker is installed. Proceeding with uninstallation..."

    # Stop and kill all running containers
    CONTAINERS=$(docker ps -q)
    if [ -n "$CONTAINERS" ]; then
      docker stop $CONTAINERS
      docker rm $CONTAINERS
    fi

    # Delete all volumes
    VOLUMES=$(docker volume ls -q)
    if [ -n "$VOLUMES" ]; then
      docker volume rm $VOLUMES
    fi

    # Delete all images
    IMAGES=$(docker images -q)
    if [ -n "$IMAGES" ]; then
      docker rmi $IMAGES
    fi

    # Delete custom networks (excluding predefined ones)
    NETWORKS=$(docker network ls -q)
    PREDEFINED_NETWORKS="bridge host none"
    for NETWORK in $NETWORKS; do
      NETWORK_NAME=$(docker network inspect --format '{{.Name}}' $NETWORK)
      if ! echo "$PREDEFINED_NETWORKS" | grep -wq "$NETWORK_NAME"; then
        docker network rm $NETWORK
      fi
    done

    # Uninstall Docker
    if [ "$(docker ps -q)" ]; then
        echo "Stopping all containers..."
        docker stop $(docker ps -q)
    fi

    if [ "$(docker ps -a -q)" ]; then
        echo "Removing all containers..."
        docker rm $(docker ps -a -q)
    fi

    if [ "$(docker images -q)" ]; then
        echo "Removing all images..."
        docker rmi $(docker images -q)
    fi

    if [ "$(docker volume ls -q)" ]; then
        echo "Removing all volumes..."
        docker volume prune -f
    fi

    if [ "$(docker network ls -q)" ]; then
        echo "Removing all networks..."
        docker network prune -f
    fi

    for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        echo "Removing Dockers Packages..."
        dpkg -s "$pkg" &>/dev/null && apt-get purge -y "$pkg"
    done

    # Delete Docker ppa, directories and files
    rm -rf /var/lib/docker &>/dev/null
    rm /etc/apt/sources.list.d/docker.list &>/dev/null

    # Clean up unneeded packages
    apt autoremove -y
    apt-get clean

    echo "Docker has been successfully uninstalled"
  else
    echo "Docker is not installed"
  fi
}

# Show help
show_help() {
    echo "Usage: $0 [COMMAND]"
    echo "Commands:"
    echo "  install    Install Docker + Portainer"
    echo "  remove     Uninstall Docker"
    echo ""
    echo "If no command is provided, interactive mode will start."
    exit 0
}

# Main execution logic
if [ $# -eq 0 ]; then
    # Interactive mode
    echo "What action do you want to perform?"
    echo "1) Install Docker + Portainer"
    echo "2) Uninstall Docker"
    echo "3) Exit"
    read -p "Select an option (1, 2 or 3): " option

    case $option in
      1)
        install_docker
        ;;
      2)
        uninstall_docker
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
            install_docker
            ;;
        remove)
            uninstall_docker
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
