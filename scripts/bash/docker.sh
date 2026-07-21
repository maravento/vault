#!/bin/bash
# maravento.com
#
# Docker + Portainer (Install | Remove)

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

# LOCAL USER detection
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
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

echo "Docker Install | Remove Starting. Wait..."

# Function to install Docker and docker-compose-plugin
install_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Proceeding with installation..."
    apt-get install -y ca-certificates curl gnupg lsb-release

    # GPG
    rm -f /etc/apt/keyrings/docker.gpg > /dev/null
    mkdir -p /etc/apt/keyrings

    # Download the key to a temp file and verify its fingerprint before trusting it
    DOCKER_GPG_EXPECTED_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
    DOCKER_GPG_TMP=$(mktemp)
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$DOCKER_GPG_TMP"
    DOCKER_GPG_ACTUAL_FPR=$(gpg --with-colons --import-options show-only --import --fingerprint "$DOCKER_GPG_TMP" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
    if [ "$DOCKER_GPG_ACTUAL_FPR" != "$DOCKER_GPG_EXPECTED_FPR" ]; then
        echo "ERROR: Docker GPG key fingerprint mismatch (got: ${DOCKER_GPG_ACTUAL_FPR:-none}, expected: $DOCKER_GPG_EXPECTED_FPR)"
        rm -f "$DOCKER_GPG_TMP"
        exit 1
    fi
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg "$DOCKER_GPG_TMP"
    rm -f "$DOCKER_GPG_TMP"

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
    usermod -aG docker "$local_user"
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
      NETWORK_NAME=$(docker network inspect --format '{{.Name}}' "$NETWORK")
      if ! echo "$PREDEFINED_NETWORKS" | grep -wq "$NETWORK_NAME"; then
        docker network rm $NETWORK
      fi
    done

    # Uninstall Docker packages
    for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        echo "Removing Dockers Packages..."
        dpkg -s "$pkg" &>/dev/null && apt-get purge -y "$pkg"
    done

    # Delete Docker ppa, directories and files
    rm -rf /var/lib/docker 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/docker.list

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
    read -rp "Select an option (1, 2 or 3): " option

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
