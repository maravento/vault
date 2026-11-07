#!/bin/bash
# maravento.com
#
################################################################################
#
# Docker + Portainer (Install | Remove)
# FILE: docker.sh
#
# DESCRIPTION: Installs Docker CE together with Portainer, or removes Docker.
# Without an argument it opens an interactive menu.
#
# USAGE: sudo bash docker.sh [--install|--uninstall|--help]
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

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: docker start..."

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

# Leaves the installer's Portainer running. Used by the first install and the retry.
ensure_portainer() {
  local container_names portainer_image portainer_running portainer_label
  docker info >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: docker is not responding -abort" >&2; exit 1; }
  container_names=$(docker ps -a --format '{{.Names}}') || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot list containers -abort" >&2; exit 1; }
  if ! grep -qx portainer <<< "$container_names"; then
    docker volume create portainer_data || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create portainer volume -abort" >&2; exit 1; }
    docker run -d -p 9000:9000 --name portainer --restart=always \
    --label com.maravento.docker-sh=portainer \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data portainer/portainer-ce || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot start portainer -abort" >&2; exit 1; }
  fi
  portainer_image=$(docker inspect -f '{{.Config.Image}}' portainer) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot inspect portainer -abort" >&2; exit 1; }
  case "$portainer_image" in
    portainer/portainer-ce|portainer/portainer-ce:*) ;;
    *) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: container name portainer is used by another image -abort" >&2; exit 1; ;;
  esac
  portainer_running=$(docker inspect -f '{{.State.Running}}' portainer) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot inspect portainer -abort" >&2; exit 1; }
  if [ "$portainer_running" != "true" ]; then
    portainer_label=$(docker inspect -f '{{index .Config.Labels "com.maravento.docker-sh"}}' portainer) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot inspect portainer -abort" >&2; exit 1; }
    if [ "$portainer_label" != "portainer" ]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: stopped portainer was not created by docker.sh -abort" >&2
      exit 1
    fi
    docker start portainer || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot start portainer -abort" >&2; exit 1; }
    portainer_running=$(docker inspect -f '{{.State.Running}}' portainer) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot inspect portainer -abort" >&2; exit 1; }
    [ "$portainer_running" = "true" ] || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: portainer is not running -abort" >&2; exit 1; }
  fi
}

# Function to install Docker and docker-compose-plugin
install_docker() {
  if ! command -v docker &> /dev/null; then
    check_ipv4_interfaces
    check_internet
    echo "$(date '+%Y-%m-%d %H:%M:%S') Docker is not installed. Proceeding with installation..."
    apt-get update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    apt-get install -y ca-certificates curl gnupg lsb-release || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install prerequisites -abort" >&2
        exit 1
    }

    # GPG
    local key_dir=/etc/apt/keyrings key_stage
    if ! mkdir -p -- "$key_dir" || ! key_stage=$(mktemp -d "$key_dir/docker-key.XXXXXX"); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot stage Docker GPG key -abort" >&2
        exit 1
    fi

    # Download the key to a temp file and verify its fingerprint before trusting it
    DOCKER_GPG_EXPECTED_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
    DOCKER_GPG_TMP="$key_stage/docker.asc"
    if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$DOCKER_GPG_TMP"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: https://download.docker.com/linux/ubuntu/gpg"
        rm -rf -- "$key_stage"
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: gpg"
    DOCKER_GPG_ACTUAL_FPR=$(gpg --with-colons --import-options show-only --import --fingerprint "$DOCKER_GPG_TMP" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
    if [ "$DOCKER_GPG_ACTUAL_FPR" != "$DOCKER_GPG_EXPECTED_FPR" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Docker GPG fingerprint mismatch, got: ${DOCKER_GPG_ACTUAL_FPR:-none}" >&2
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: expected: $DOCKER_GPG_EXPECTED_FPR -abort" >&2
        rm -rf -- "$key_stage"
        exit 1
    fi
    if ! gpg --dearmor -o "$key_stage/docker.gpg" "$DOCKER_GPG_TMP" ||
       ! chmod 644 "$key_stage/docker.gpg" ||
       ! mv -fT -- "$key_stage/docker.gpg" "$key_dir/docker.gpg"; then
        rm -rf -- "$key_stage"
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot store Docker GPG key -abort" >&2
        exit 1
    fi
    rm -rf -- "$key_stage"

    # Add Repo
    echo \
      "deb [arch=$(dpkg --print-architecture) \
      signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot write docker.list -abort" >&2
        exit 1
    }

    # Install
    apt-get update || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
        exit 1
    }
    # Method 1: install Docker CE and Compose from the Docker repository.
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot install Docker packages -abort" >&2
        exit 1
    }
    # Method 2: alternative docker.io installation; replace Method 1.
    #apt install -y docker.io docker-compose-plugin # Optional
    mkdir -p /etc/docker
    docker compose version || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: docker compose not available -abort" >&2
        exit 1
    }
    systemctl start docker || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot start docker -abort" >&2
        exit 1
    }
    systemctl enable docker || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot enable docker -abort" >&2
        exit 1
    }
    usermod -aG docker "$local_user" || {
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot add user to docker group -abort" >&2
        exit 1
    }
    ensure_portainer
    #docker run hello-world
    echo "Docker + Portainer has been installed successfully"
    echo "Access: http://localhost:9000/"
  else
    ensure_portainer
    echo "Docker is already installed"
  fi
}

# Docker uninstall function
uninstall_docker() {
    local purge_failed=0
  if command -v docker &> /dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Docker is installed. Proceeding with uninstallation..."

    # Stop and kill all running containers
    CONTAINERS=$(docker ps -q)
    if [ -n "$CONTAINERS" ]; then
      docker stop $CONTAINERS
    fi
    CONTAINERS=$(docker ps -aq)
    if [ -n "$CONTAINERS" ]; then
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') Removing Dockers Packages..."
        if dpkg -s "$pkg" &>/dev/null && ! apt-get purge -y "$pkg"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: package $pkg not removed -alert"
            purge_failed=1
        fi
    done

    # Delete Docker ppa, directories and files
    rm -rf /var/lib/docker 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/docker.list

    # Clean up unneeded packages
    apt autoremove -y
    apt-get clean

    if [ "$purge_failed" -gt 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Docker data removed, packages pending -alert"
    else
        echo "Docker has been successfully uninstalled"
    fi
  else
    echo "Docker is not installed"
  fi
}

# Show help
show_help() {
    echo "Usage: $0 [--install|--uninstall|--help]"
    echo "Commands:"
    echo "  --install    Install Docker + Portainer"
    echo "  --uninstall  Uninstall Docker"
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
    echo "1) Install Docker + Portainer"
    echo "2) Uninstall Docker"
    echo "3) Exit"
    read -rp "Select an option (1, 2 or 3): " option
    option="${option:-3}"

    case $option in
      1)
        install_docker
        ;;
      2)
        uninstall_docker
        ;;
      3)
        ;;
      *)
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
        exit 1
        ;;
    esac
else
    # Command line mode
    case $1 in
        --install)
            install_docker
            ;;
        --uninstall)
            uninstall_docker
            ;;
        --help|-h)
            show_help
            ;;
        *)
            echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: invalid option -abort" >&2
            show_help
            exit 1
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: docker done"
