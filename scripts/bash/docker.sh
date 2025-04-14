#!/bin/bash
# by maravento.com

# Docker Install | Remove
# tested: Ubuntu 24.04

echo "Docker Install | Remove Starting. Wait..."
printf "\n"

# checking root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done

# Function to install Docker and docker-compose-plugin
install_docker() {
  if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Proceeding with installation..."
    apt update
    apt install -y docker.io docker-compose-plugin
    mkdir -p /etc/docker
    docker compose version
    systemctl start docker
    systemctl enable docker
    echo "Docker has been installed successfully"
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
    apt purge -y docker.io docker-compose-plugin

    # Delete Docker directories and files
    rm -rf /var/lib/docker

    # Clean up unneeded packages
    apt autoremove -y

    echo "Docker has been successfully uninstalled"
  else
    echo "Docker is not installed"
  fi
}

# Options
echo "What action do you want to perform?"
echo "1) Install Docker"
echo "2) Uninstall Docker"
read -p "Select an option (1 or 2): " option

case $option in
  1)
    install_docker
    ;;
  2)
    uninstall_docker
    ;;
  *)
    echo "Invalid option"
    ;;
esac

