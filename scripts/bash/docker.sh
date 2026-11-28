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
# USAGE:
# COMMAND                          ACTION
# sudo bash docker.sh              Interactive menu
# sudo bash docker.sh --install    Install
# sudo bash docker.sh --uninstall  Uninstall
# sudo bash docker.sh -h           Show usage
# sudo bash docker.sh --help       Show usage
#
################################################################################

set -uo pipefail

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

# dependencies
net_checked=0
for dep in coreutils util-linux grep iproute2 libc-bin ca-certificates curl gnupg lsb-release; do
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

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: docker start..."

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

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

# Leaves the installer's Portainer running. Used by the first install and the retry.
ensure_portainer() {
    local container_names portainer_image portainer_running portainer_label
    docker info >/dev/null 2>&1 || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: docker is not responding -abort" >&2; exit 1; }
    container_names=$(docker ps -a --format '{{.Names}}') || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot list containers -abort" >&2; exit 1; }
    if ! grep -qx portainer <<< "$container_names"; then
        if ! docker image inspect portainer/portainer-ce >/dev/null 2>&1; then
            check_ipv4_interfaces
            check_internet
            retry_cmd "download Portainer image" docker pull portainer/portainer-ce || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot start portainer -abort" >&2; exit 1; }
        fi
        docker volume create portainer_data || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot create portainer volume -abort" >&2; exit 1; }
        docker run --pull=never -d -p 9000:9000 --name portainer --restart=always \
        --label com.maravento.docker-sh=portainer \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data portainer/portainer-ce || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot start portainer -abort" >&2; exit 1; }
    fi
    portainer_image=$(docker inspect -f '{{.Config.Image}}' portainer) || { echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot inspect portainer -abort" >&2; exit 1; }
    case "$portainer_image" in
        portainer/portainer-ce|portainer/portainer-ce:*) ;;
        *) echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: name portainer used by another image -abort" >&2; exit 1; ;;
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Docker not installed. Installing..."
        retry_cmd "update package lists" apt-get update || {
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
                exit 1
        }

        # GPG
        local key_dir=/etc/apt/keyrings key_stage
        if ! mkdir -p -- "$key_dir" || ! key_stage=$(mktemp -d "$key_dir/docker-key.XXXXXX"); then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot stage Docker GPG key -abort" >&2
                exit 1
        fi

        # Download the key to a temp file and verify its fingerprint before trusting it
        docker_gpg_expected_fpr="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
        docker_gpg_tmp="$key_stage/docker.asc"
        if ! retry_cmd "download signing key" curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$docker_gpg_tmp"; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') PARTIAL: https://download.docker.com/linux/ubuntu/gpg"
                rm -rf -- "$key_stage"
                exit 1
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') SAVED: gpg"
        docker_gpg_actual_fpr=$(gpg --with-colons --import-options show-only --import --fingerprint "$docker_gpg_tmp" 2>/dev/null | awk -F: '/^fpr:/{print $10; exit}')
        if [ "$docker_gpg_actual_fpr" != "$docker_gpg_expected_fpr" ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [1/2] Docker GPG fingerprint mismatch, got: ${docker_gpg_actual_fpr:-none}" >&2
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: [2/2] expected: $docker_gpg_expected_fpr -abort" >&2
                rm -rf -- "$key_stage"
                exit 1
        fi
        if ! gpg --dearmor -o "$key_stage/docker.gpg" "$docker_gpg_tmp" ||
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
        retry_cmd "update package lists" apt-get update || {
                echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot update package lists -abort" >&2
                exit 1
        }
        # Method 1: install Docker CE and Compose from the Docker repository.
        retry_cmd "install packages" apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
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
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Docker + Portainer installed"
        echo "Access: http://localhost:9000/"
    else
        ensure_portainer
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Docker already installed -skip"
    fi
}

# Docker uninstall function
uninstall_docker() {
        local purge_failed=0
    if command -v docker &> /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Docker is installed. Proceeding with uninstallation..."

        # Stop and kill all running containers
        container_ids=$(docker ps -q)
        if [ -n "$container_ids" ]; then
            docker stop $container_ids
        fi
        container_ids=$(docker ps -aq)
        if [ -n "$container_ids" ]; then
            docker rm $container_ids
        fi

        # Delete all volumes
        volume_ids=$(docker volume ls -q)
        if [ -n "$volume_ids" ]; then
            docker volume rm $volume_ids
        fi

        # Delete all images
        image_ids=$(docker images -q)
        if [ -n "$image_ids" ]; then
            docker rmi $image_ids
        fi

        # Delete custom networks (excluding predefined ones)
        network_ids=$(docker network ls -q)
        predefined_networks="bridge host none"
        for network_id in $network_ids; do
            network_name=$(docker network inspect --format '{{.Name}}' "$network_id")
            if ! echo "$predefined_networks" | grep -wq "$network_name"; then
                docker network rm $network_id
            fi
        done

        # Uninstall Docker packages
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: removing Docker packages..."
        for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
                if dpkg -s "$pkg" &>/dev/null && ! apt-get purge -y "$pkg"; then
                        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: package $pkg not removed -alert"
                        purge_failed=1
                fi
        done

        # Delete Docker ppa, directories and files
        rm -rf /var/lib/docker 2>/dev/null || true
        rm -f /etc/apt/sources.list.d/docker.list
        rm -f /etc/apt/keyrings/docker.gpg

        # Clean up unneeded packages
        apt autoremove -y
        apt-get clean

        if [ "$purge_failed" -gt 0 ]; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: Docker data removed, packages pending -alert"
        else
                echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Docker uninstalled"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: Docker not installed -skip"
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
    echo ""
    echo "==== Docker Installation Menu ===="
    echo "1) Install Docker + Portainer"
    echo "2) Uninstall Docker"
    echo "3) Exit"
    read -rp "Select an option (1, 2 or 3): " option
    echo ""
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
echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: docker done"
