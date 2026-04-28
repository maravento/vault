#!/bin/bash
# maravento.com
#
# =======================================================================================
#  AI STACK MANAGER - Dockerized Version
#  Complete containerized stack: Ollama + LLM + Open WebUI + Docker + Portainer
#  opencode is optional (CLI tool, runs natively, not in Docker)
#
#  Usage: ./aistack.sh [COMMAND]
#  Commands: install | status | model | install-opencode | uninstall-opencode | uninstall
#  Without arguments, runs interactive menu
# =======================================================================================

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Check root privileges
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Check OS (Debian/Ubuntu only)
if ! command -v apt-get &>/dev/null; then
    echo "ERROR: This script requires Debian/Ubuntu with apt-get"
    exit 1
fi

# Script lock to prevent concurrent execution
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# Detect local user
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
if [ -z "$local_user" ]; then
    local_user=$(ls -l /home | grep '^d' | head -1 | awk '{print $3}')
    if [ -z "$local_user" ]; then
        echo "ERROR: Cannot determine local user"
        exit 1
    fi
    echo "Using fallback user: $local_user"
fi

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
AI_BASE_DIR="/home/$local_user/aiworker"
OPEN_WEBUI_PORT=3000
OLLAMA_PORT=11434
PORTAINER_PORT=9000

# GPU Detection
detect_gpu() {
    HAS_GPU=false
    HAS_NVIDIA_DOCKER=false
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        HAS_GPU=true
        echo "✅ NVIDIA GPU detected"
        nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | xargs echo "   GPU Model:"
        
        # Check if nvidia-docker is installed
        if command -v nvidia-container-toolkit &>/dev/null || \
           docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &>/dev/null 2>&1; then
            HAS_NVIDIA_DOCKER=true
            echo "✅ NVIDIA Container Toolkit detected (GPU will be used)"
        else
            echo "⚠️  NVIDIA Container Toolkit not installed"
            echo "   GPU available but Docker cannot use it"
            echo "   Install with:"
            echo "   apt install -y nvidia-container-toolkit"
            echo "   systemctl restart docker"
        fi
    else
        echo "ℹ️  No NVIDIA GPU detected (will use CPU for Ollama)"
    fi
}

# ── Detect native (non-Docker) installations ──────────────────────────────────
detect_native_components() {
    NATIVE_OLLAMA=false
    NATIVE_OPENWEBUI=false
    NATIVE_PORTAINER=false

    # Ollama native: binary or install directory
    if command -v ollama &>/dev/null || \
       [ -f "/usr/local/bin/ollama" ] || \
       [ -f "/usr/bin/ollama" ] || \
       [ -d "/usr/share/ollama" ]; then
        NATIVE_OLLAMA=true
    fi

    # Open WebUI native: pip package or process on port 8080 (outside Docker)
    if pip show open-webui &>/dev/null 2>&1 || \
       (ss -tlnp 2>/dev/null | grep -q ":${OPEN_WEBUI_PORT}" && \
        ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q "${OPEN_WEBUI_PORT}"); then
        NATIVE_OPENWEBUI=true
    fi

    # Portainer native: process on port 9000 outside Docker
    if ss -tlnp 2>/dev/null | grep -q ":${PORTAINER_PORT}" && \
       ! docker ps --format '{{.Ports}}' 2>/dev/null | grep -q "${PORTAINER_PORT}"; then
        NATIVE_PORTAINER=true
    fi
}

# ── Remove detected native components (interactive) ───────────────────────────
remove_native_components() {
    local found=false

    if [ "$NATIVE_OLLAMA" = true ]; then
        found=true
        echo ""
        warn "Native Ollama installation detected outside Docker"
        echo -e "  ${DIM}Paths: /usr/local/bin/ollama  /usr/share/ollama  ~/.ollama${RESET}"
        read -rp "  Remove native Ollama? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            systemctl stop ollama 2>/dev/null || true
            systemctl disable ollama 2>/dev/null || true
            rm -f /etc/systemd/system/ollama.service
            systemctl daemon-reload 2>/dev/null || true
            rm -f /usr/local/bin/ollama /usr/bin/ollama
            rm -rf /usr/share/ollama
            rm -rf "/home/$local_user/.ollama"
            id ollama &>/dev/null && userdel ollama 2>/dev/null || true
            ok "Native Ollama removed"
        fi
    fi

    if [ "$NATIVE_OPENWEBUI" = true ]; then
        found=true
        echo ""
        warn "Native Open WebUI installation detected outside Docker"
        read -rp "  Remove native Open WebUI (pip uninstall)? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            pip uninstall -y open-webui 2>/dev/null || true
            ok "Native Open WebUI removed"
        fi
    fi

    if [ "$NATIVE_PORTAINER" = true ]; then
        found=true
        echo ""
        warn "A process was detected on port ${PORTAINER_PORT} outside Docker (possible native Portainer)"
        read -rp "  Do you want to review and stop it manually? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            ss -tlnp | grep ":${PORTAINER_PORT}"
        fi
    fi

    if [ "$found" = false ]; then
        ok "No native installations detected outside Docker"
    fi
}

# Available models for selection
AVAILABLE_MODELS=(
    "gemma4:31b-dense"       # Maximum quality, needs 20-24GB RAM, high-end GPU
    "gemma4:26b-moe"         # MoE architecture, needs 8-10GB RAM
    "qwen2.5-coder:7b"       # Powerful for coding, 6-8GB RAM
    "gemma4:e4b"             # Balanced multimodal, 5-6GB RAM
    "codellama:7b"           # Code-specialized, 6-8GB RAM
    "deepseek-coder:6.7b"    # MIT license, good for coding
    "mistral:7b"             # General purpose, Apache 2.0
    "phi3:3.8b"              # Small but capable, MIT license
    "llama3.2:3b"            # Balanced quality/speed, ~3GB RAM
    "qwen2.5-coder:1.5b"     # Fast coding model, 2-3GB RAM, ideal for CPU
    "gemma4:e2b"             # Ultralight multimodal, ~4GB RAM
    "llama3.2:1b"            # Very fast, ~1-2GB RAM
)

DEFAULT_MODEL="qwen2.5-coder:7b"
SELECTED_MODEL="$DEFAULT_MODEL"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Visual Helpers ───────────────────────────────────────────────────────────
header() {
  clear
  echo -e "${CYAN}"
  echo "  +------------------------------------------------------+"
  echo "  |        AI STACK MANAGER - Dockerized v1.0            |"
  echo "  |        Ollama · Open Web UI · Portainer              |"
  echo "  +------------------------------------------------------+"
  echo -e "${RESET}"
  echo -e "  ${DIM}Base directory: ${WHITE}${AI_BASE_DIR}${RESET}"
  echo ""
}

ok()   { echo -e "  ${GREEN}✔${RESET}  $*"; }
err()  { echo -e "  ${RED}✘${RESET}  $*"; }
info() { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
step() { echo -e "\n  ${MAGENTA}▶${RESET}  ${BOLD}$*${RESET}"; }
line() { echo -e "  ${DIM}------------------------------------------------${RESET}"; }

pause() { echo ""; read -rp "  Press Enter to continue..." _; }

# ── Model selection menu ──────────────────────────────────────────────────────
select_model() {
    echo ""
    echo -e "  ${BOLD}Available models:${RESET}"
    echo ""
    
    local i=1
    for model in "${AVAILABLE_MODELS[@]}"; do
        if [[ "$model" == "$DEFAULT_MODEL" ]]; then
            echo -e "  ${WHITE}$i)${RESET} $model ${DIM}(default)${RESET}"
        else
            echo -e "  ${WHITE}$i)${RESET} $model"
        fi
        ((i++))
    done
    
    echo ""
    echo -e "  ${DIM}Press Enter to use default: ${DEFAULT_MODEL}${RESET}"
    echo ""
    read -rp "  → Select model [1-${#AVAILABLE_MODELS[@]}]: " choice
    
    if [[ -z "$choice" ]]; then
        SELECTED_MODEL="$DEFAULT_MODEL"
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#AVAILABLE_MODELS[@]}" ]; then
        SELECTED_MODEL="${AVAILABLE_MODELS[$((choice-1))]}"
    else
        warn "Invalid selection, using default: $DEFAULT_MODEL"
        SELECTED_MODEL="$DEFAULT_MODEL"
    fi
    
    echo ""
    ok "Model selected: ${SELECTED_MODEL}"
    sleep 1
}

# ── Install Docker + Portainer ──────────────────────────────────────────────
install_docker() {
    step "Installing Docker + Portainer"
    
    if command -v docker &> /dev/null; then
        ok "Docker is already installed"
    else
        info "Installing Docker..."
        apt-get install -y ca-certificates curl gnupg lsb-release

        # GPG key
        rm -f /etc/apt/keyrings/docker.gpg > /dev/null
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg

        # Add repository
        echo \
            "deb [arch=$(dpkg --print-architecture) \
            signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        mkdir -p /etc/docker
        systemctl start docker
        systemctl enable docker
        usermod -aG docker $local_user
        
        ok "Docker installed successfully"
    fi
    
    # Verify Docker Compose plugin
    if ! docker compose version &>/dev/null; then
        err "Docker Compose plugin not available"
        exit 1
    fi
    
    # Install Portainer
    if docker ps --format '{{.Names}}' | grep -q "^portainer$"; then
        ok "Portainer already running"
    else
        info "Installing Portainer..."
        docker volume create portainer_data 2>/dev/null || true
        docker run -d -p ${PORTAINER_PORT}:9000 --name portainer --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data portainer/portainer-ce
        
        ok "Portainer installed"
        info "Access: http://localhost:${PORTAINER_PORT}"
    fi
}

# ── Install NVIDIA Container Toolkit (if GPU detected) ─────────────────────────
install_nvidia_docker() {
    if [ "$HAS_GPU" = true ] && [ "$HAS_NVIDIA_DOCKER" = false ]; then
        step "Installing NVIDIA Container Toolkit"
        
        # Add NVIDIA repository
        distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
            tee /etc/apt/sources.list.d/nvidia-docker.list
        
        apt-get update
        apt-get install -y nvidia-container-toolkit
        
        # Configure Docker daemon
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << EOF
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
        
        systemctl restart docker
        HAS_NVIDIA_DOCKER=true
        ok "NVIDIA Container Toolkit installed"
    fi
}

# ── Create docker-compose.yml ──────────────────────────────────────────────────
create_docker_compose() {
    step "Creating docker-compose.yml"
    
    mkdir -p "${AI_BASE_DIR}"
    
    # Determine GPU runtime for Ollama
    local OLLAMA_RUNTIME=""
    local OLLAMA_GPU_DEVICES=""
    if [ "$HAS_NVIDIA_DOCKER" = true ]; then
        OLLAMA_RUNTIME="    runtime: nvidia"
        OLLAMA_GPU_DEVICES="
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]"
    fi
    
    cat > "${AI_BASE_DIR}/docker-compose.yml" << EOF
services:
  # Ollama service - AI model runner
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: always
    volumes:
      - ${AI_BASE_DIR}/ollama/models:/root/.ollama
    ports:
      - "${OLLAMA_PORT}:11434"
    environment:
      - OLLAMA_HOST=0.0.0.0
${OLLAMA_RUNTIME}${OLLAMA_GPU_DEVICES}

  # Open WebUI - Chat interface
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    volumes:
      - ${AI_BASE_DIR}/open-webui/data:/app/backend/data
    ports:
      - "${OPEN_WEBUI_PORT}:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:${OLLAMA_PORT}
    depends_on:
      - ollama
    extra_hosts:
      - host.docker.internal:host-gateway

EOF

    ok "docker-compose.yml created at ${AI_BASE_DIR}"
}

# ── Deploy AI Stack ───────────────────────────────────────────────────────────
deploy_stack() {
    step "Deploying AI Stack with Docker Compose"
    
    cd "${AI_BASE_DIR}"
    
    # Pull images
    info "Pulling Docker images (may take a few minutes)..."
    docker compose pull
    
    # Start services
    info "Starting services..."
    docker compose up -d
    
    ok "AI Stack deployed successfully"
}

# ── Download Model ────────────────────────────────────────────────────────────
download_model() {
    step "Downloading model: ${SELECTED_MODEL}"
    
    # Wait for Ollama to be ready
    info "Waiting for Ollama service to be ready..."
    local max_attempts=30
    local attempt=0
    while ! curl -s --connect-timeout 2 "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; do
        sleep 2
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            warn "Ollama service not responding, continuing anyway..."
            break
        fi
    done
    
    # Check if model already exists
    if docker exec ollama ollama list 2>/dev/null | grep -q "${SELECTED_MODEL}"; then
        warn "Model ${SELECTED_MODEL} already downloaded"
        return 0
    fi
    
    info "Downloading ${SELECTED_MODEL} (may take several minutes)..."
    docker exec ollama ollama pull "${SELECTED_MODEL}"
    ok "Model ${SELECTED_MODEL} downloaded successfully"
}

# ── List installed models ──────────────────────────────────────────────────────
list_installed_models() {
    if ! docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        err "Ollama container is not running"
        return 1
    fi
    
    local models
    models=$(docker exec ollama ollama list 2>/dev/null | tail -n +2)
    if [[ -z "$models" ]]; then
        echo -e "  ${DIM}No models installed${RESET}"
        return 0
    fi
    
    echo ""
    echo -e "  ${BOLD}Installed models:${RESET}"
    echo ""
    echo "$models" | while read -r line; do
        local name=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $3, $4}')
        echo -e "  ${WHITE}•${RESET} $name ${DIM}($size)${RESET}"
    done
    echo ""
}

# ── Remove a specific model ────────────────────────────────────────────────────
remove_model() {
    if ! docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        err "Ollama container is not running"
        return 1
    fi
    
    # Get list of installed models
    local models_list=()
    while IFS= read -r line; do
        models_list+=("$(echo "$line" | awk '{print $1}')")
    done < <(docker exec ollama ollama list 2>/dev/null | tail -n +2)
    
    if [ ${#models_list[@]} -eq 0 ]; then
        info "No models installed to remove"
        return 0
    fi
    
    echo ""
    echo -e "  ${BOLD}Installed models:${RESET}"
    echo ""
    local i=1
    for model in "${models_list[@]}"; do
        echo -e "  ${WHITE}$i)${RESET} $model"
        ((i++))
    done
    echo ""
    echo -e "  ${WHITE}0)${RESET} Cancel"
    echo ""
    read -rp "  → Select model to remove [0-${#models_list[@]}]: " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#models_list[@]}" ]; then
        local model_to_remove="${models_list[$((choice-1))]}"
        echo ""
        read -rp "  Remove model '$model_to_remove'? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            docker exec ollama ollama rm "$model_to_remove"
            ok "Model '$model_to_remove' removed"
        else
            info "Cancelled"
        fi
    elif [ "$choice" != "0" ]; then
        warn "Invalid option"
    fi
}

# ── Change default model (remove current, install new) ────────────────────────
change_default_model() {
    # Get current selected model
    local current_model="$SELECTED_MODEL"
    
    echo ""
    echo -e "  ${BOLD}Current default model: ${WHITE}$current_model${RESET}"
    echo ""
    
    # Ask if user wants to remove current model
    read -rp "  Remove current model '$current_model' before installing new? [y/N]: " remove_current
    echo ""
    
    # Select new model
    select_model
    
    # Remove current model if requested
    if [[ "$remove_current" =~ ^[yY]$ ]]; then
        if docker exec ollama ollama list 2>/dev/null | grep -q "$current_model"; then
            info "Removing current model: $current_model"
            docker exec ollama ollama rm "$current_model"
            ok "Removed $current_model"
        fi
    fi
    
    # Download new model
    download_model
    
    # Update DEFAULT_MODEL in script? (optional)
    echo ""
    read -rp "  Set '$SELECTED_MODEL' as new default for future installs? [y/N]: " set_default
    if [[ "$set_default" =~ ^[yY]$ ]]; then
        DEFAULT_MODEL="$SELECTED_MODEL"
        ok "Default model updated to: $DEFAULT_MODEL"
    fi
}

# ── Manage Models Submenu ─────────────────────────────────────────────────────
menu_models() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo "  +------------------------------------------------------+"
        echo "  |                 MANAGE MODELS                        |"
        echo "  +------------------------------------------------------+"
        echo -e "${RESET}"
        echo ""
        
        # Show installed models
        list_installed_models
        
        echo -e "  ${BOLD}Select an option:${RESET}"
        echo ""
        echo -e "  ${WHITE}1)${RESET}  Install additional model"
        echo -e "  ${WHITE}2)${RESET}  Remove a model"
        echo -e "  ${WHITE}3)${RESET}  Change default model (remove current + install new)"
        echo -e "  ${WHITE}0)${RESET}  Back to main menu"
        echo ""
        line
        echo -n "  → Option: "
        read -r opt

        case "$opt" in
            1)  select_model; download_model; pause ;;
            2)  remove_model; pause ;;
            3)  change_default_model; pause ;;
            0)  return ;;
            *)  warn "Invalid option" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
#  OPENCODE (Optional CLI tool - runs natively, NOT in Docker)
# ══════════════════════════════════════════════════════════════════════════════

# ── Install opencode (optional CLI tool) ──────────────────────────────────────
install_opencode() {
    step "Installing opencode (optional CLI tool)"
    
    echo -e "  ${DIM}ℹ️  OpenCode runs natively on your system (not in Docker)${RESET}"
    echo -e "  ${DIM}   It provides AI assistance directly in your terminal/editor${RESET}"
    echo -e "  ${DIM}   You don't need it if you already use Open Web UI${RESET}"
    echo ""
    
    if command -v opencode &>/dev/null; then
        warn "opencode already installed"
        return 0
    fi
    
    # Try via npm (official package manager method)
    if command -v npm &>/dev/null; then
        info "Installing via npm (official package)..."
        npm install -g opencode-ai@latest
        if command -v opencode &>/dev/null; then
            ok "opencode installed via npm"
            return 0
        fi
    fi
    
    # Fallback: Official install script as the real user (not root)
    info "Installing via official install script as user: $local_user..."
    if sudo -u "$local_user" curl -fsSL https://opencode.ai/install | sudo -u "$local_user" bash; then
        # The install script puts it in /home/$local_user/.opencode/bin
        if [ -f "/home/$local_user/.opencode/bin/opencode" ]; then
            # Create symlink in system PATH for root access
            ln -sf "/home/$local_user/.opencode/bin/opencode" /usr/local/bin/opencode
            ok "Created symlink: /usr/local/bin/opencode"
        fi
        
        if command -v opencode &>/dev/null; then
            ok "OpenCode installed successfully"
            return 0
        else
            warn "Install script completed but opencode command not found"
            info "You may need to log out and back in, or run: hash -r"
            return 1
        fi
    else
        warn "Official install script failed"
        info "Please install manually: https://opencode.ai"
        return 1
    fi
}

# ── Uninstall opencode only ───────────────────────────────────────────────────
uninstall_opencode() {
    step "Uninstalling opencode"

    # Check if opencode is actually installed anywhere
    local found=false
    command -v opencode &>/dev/null                          && found=true
    [ -f "/usr/local/bin/opencode" ]                        && found=true
    [ -d "/home/$local_user/.opencode" ]                    && found=true
    command -v npm &>/dev/null && npm list -g opencode-ai &>/dev/null 2>&1 && found=true

    if [ "$found" = false ]; then
        info "OpenCode is not installed — nothing to do"
        return 0
    fi

    # Remove system symlink
    if [ -f "/usr/local/bin/opencode" ]; then
        rm -f "/usr/local/bin/opencode"
        ok "Removed /usr/local/bin/opencode"
    fi

    # Remove user installation (as the real user)
    if [ -d "/home/$local_user/.opencode" ]; then
        sudo -u "$local_user" rm -rf "/home/$local_user/.opencode"
        ok "Removed /home/$local_user/.opencode"
    fi

    # Uninstall via npm if installed that way
    if command -v npm &>/dev/null && npm list -g opencode-ai &>/dev/null 2>&1; then
        npm uninstall -g opencode-ai
        ok "OpenCode uninstalled via npm"
    fi

    # Remove shell config lines only if any config file actually contains 'opencode'
    local has_entries=false
    for config in "/home/$local_user/.bashrc" "/home/$local_user/.zshrc" "/home/$local_user/.profile" "/home/$local_user/.bash_profile"; do
        [ -f "$config" ] && grep -q "opencode" "$config" 2>/dev/null && has_entries=true && break
    done

    if [ "$has_entries" = true ]; then
        echo ""
        read -rp "  Remove OpenCode entries from shell config files (.bashrc, .zshrc)? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            for config in "/home/$local_user/.bashrc" "/home/$local_user/.zshrc" "/home/$local_user/.profile" "/home/$local_user/.bash_profile"; do
                if [ -f "$config" ] && grep -q "opencode" "$config" 2>/dev/null; then
                    sed -i '/opencode/d' "$config" && ok "Cleaned $config"
                fi
            done
        fi
    fi

    ok "opencode completely uninstalled"
}

# ── OpenCode Submenu ──────────────────────────────────────────────────────────
menu_opencode() {
    while true; do
        clear
        echo -e "${MAGENTA}"
        echo "  +------------------------------------------------------+"
        echo "  |              OPENCODE (Optional CLI Tool)            |"
        echo "  +------------------------------------------------------+"
        echo -e "${RESET}"
        echo ""
        echo -e "  ${DIM}OpenCode is an optional CLI tool that runs natively on your system${RESET}"
        echo -e "  ${DIM}It is NOT installed inside Docker and is NOT required for the AI Stack${RESET}"
        echo ""
        echo -e "  ${BOLD}Select an option:${RESET}"
        echo ""
        echo -e "  ${WHITE}1)${RESET}  Install OpenCode"
        echo -e "  ${WHITE}2)${RESET}  Uninstall OpenCode"
        echo -e "  ${WHITE}0)${RESET}  Back to main menu"
        echo ""
        line
        echo -n "  → Option: "
        read -r opt

        case "$opt" in
            1)  install_opencode; return ;;
            2)  uninstall_opencode; return ;;
            0)  return ;;
            *)  warn "Invalid option" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════════════════════
#  UNINSTALL FUNCTIONS (Individual components)
# ══════════════════════════════════════════════════════════════════════════════

# Uninstall Open Web UI only
uninstall_open_webui() {
    step "Uninstalling Open Web UI"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^open-webui$"; then
        docker stop open-webui 2>/dev/null
        docker rm open-webui 2>/dev/null
        ok "Open Web UI container removed"
        
        read -rp "  Remove Open Web UI image? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            docker rmi ghcr.io/open-webui/open-webui:main 2>/dev/null
            ok "Open Web UI image removed"
        fi
        
        read -rp "  Remove Open Web UI data? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            rm -rf "${AI_BASE_DIR}/open-webui/data"
            ok "Open Web UI data removed"
        fi
    else
        warn "Open Web UI container not found"
    fi

    # ── Offer to remove native Open WebUI if found ─────────────────────────
    echo ""
    step "Checking for native Open WebUI outside Docker..."
    detect_native_components
    if [ "$NATIVE_OPENWEBUI" = true ]; then
        remove_native_components
    else
        ok "No native Open WebUI installation detected"
    fi
}

# Uninstall Ollama container only
uninstall_ollama_container() {
    step "Uninstalling Ollama container"

    if ! command -v docker &>/dev/null; then
        info "Docker is not installed — skipping container removal"
    elif docker ps -a --format '{{.Names}}' | grep -q "^ollama$"; then
        docker stop ollama 2>/dev/null
        docker rm ollama 2>/dev/null
        ok "Ollama container removed"

        read -rp "  Remove Ollama image? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            docker rmi ollama/ollama:latest 2>/dev/null
            ok "Ollama image removed"
        fi

        read -rp "  Remove downloaded models? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            rm -rf "${AI_BASE_DIR}/ollama/models"
            ok "Models removed"
        fi
    else
        info "Ollama container not found — skipping"
    fi

    # ── Offer to remove native Ollama if found ─────────────────────────────
    echo ""
    step "Checking for native Ollama outside Docker..."
    detect_native_components
    if [ "$NATIVE_OLLAMA" = true ]; then
        remove_native_components
    else
        ok "No native Ollama installation detected"
    fi
}

# Uninstall Portainer only
uninstall_portainer() {
    step "Uninstalling Portainer"
    
    if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        docker stop portainer 2>/dev/null
        docker rm portainer 2>/dev/null
        ok "Portainer container removed"
        
        read -rp "  Remove Portainer volume (data)? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            docker volume rm portainer_data 2>/dev/null
            ok "Portainer data removed"
        fi
        
        read -rp "  Remove Portainer image? [y/N]: " confirm
        if [[ "$confirm" =~ ^[yY]$ ]]; then
            docker rmi portainer/portainer-ce 2>/dev/null
            ok "Portainer image removed"
        fi
    else
        warn "Portainer container not found"
    fi
}

# Uninstall models only (keep everything else)
uninstall_models_only() {
    step "Removing AI models"
    
    if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        local models
        models=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ', ')
        if [[ -n "$models" ]]; then
            echo -e "  ${DIM}Installed models: ${models}${RESET}"
            echo ""
            read -rp "  Remove ALL models? [y/N]: " confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                docker exec ollama ollama list | tail -n +2 | awk '{print $1}' | while read -r model; do
                    docker exec ollama ollama rm "$model"
                    ok "Removed: $model"
                done
            fi
        else
            warn "No models found"
        fi
    else
        err "Ollama container is not running"
    fi
}

# ── Uninstall everything (complete) ───────────────────────────────────────────
uninstall_all() {
    echo ""
    warn "${BOLD}ATTENTION! This will remove ALL containers, images, volumes, and data${RESET}"
    echo ""
    read -rp "  Are you sure? Type 'CONFIRM' to continue: " confirm
    if [[ "$confirm" != "CONFIRM" ]]; then
        info "Operation cancelled"
        return 0
    fi
    echo ""

    # ── AI Stack containers (Ollama + Open WebUI) ──────────────────────────
    step "AI Stack containers (Ollama + Open WebUI)..."
    if command -v docker &>/dev/null && [ -f "${AI_BASE_DIR}/docker-compose.yml" ]; then
        cd "${AI_BASE_DIR}" && docker compose down -v 2>/dev/null || true
        ok "Containers stopped and removed"
    else
        info "Not found — skipping"
    fi

    # ── Portainer ──────────────────────────────────────────────────────────
    step "Portainer..."
    if command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
        docker stop portainer 2>/dev/null || true
        docker rm portainer 2>/dev/null || true
        docker volume rm portainer_data 2>/dev/null || true
        ok "Portainer removed"
    else
        info "Not found — skipping"
    fi

    # ── Docker ─────────────────────────────────────────────────────────────
    step "Docker..."
    if command -v docker &>/dev/null; then
        read -rp "  Remove Docker completely? [y/N]: " remove_docker
        if [[ "$remove_docker" =~ ^[yY]$ ]]; then
            for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose docker-compose-v2; do
                dpkg -s "$pkg" &>/dev/null && apt-get purge -y "$pkg"
            done
            rm -rf /var/lib/docker
            rm -rf /var/lib/containerd
            rm -f /etc/apt/sources.list.d/docker.list
            apt autoremove -y
            apt-get clean
            ok "Docker removed"
        else
            info "Docker kept"
        fi
    else
        info "Not installed — skipping"
    fi

    # ── AI data directory ──────────────────────────────────────────────────
    step "AI data directory (${AI_BASE_DIR})..."
    if [ -d "${AI_BASE_DIR}" ]; then
        read -rp "  Remove all AI data? [y/N]: " remove_data
        if [[ "$remove_data" =~ ^[yY]$ ]]; then
            rm -rf "${AI_BASE_DIR}"
            ok "Data removed"
        else
            info "Data kept"
        fi
    else
        info "Not found — skipping"
    fi

    # ── OpenCode ───────────────────────────────────────────────────────────
    step "OpenCode..."
    if command -v opencode &>/dev/null || [ -f "/usr/local/bin/opencode" ] || [ -d "/home/$local_user/.opencode" ]; then
        uninstall_opencode
    else
        info "Not installed — skipping"
    fi

    # ── Native installations outside Docker ────────────────────────────────
    step "Checking for native installations outside Docker..."
    detect_native_components
    remove_native_components

    echo ""
    ok "AI Stack completely uninstalled"
}

# ── Show status ────────────────────────────────────────────────────────────────
status_all() {
    echo ""
    echo -e "  ${BOLD}${CYAN}--- AI STACK STATUS -----------------------------${RESET}"
    echo -e "  ${DIM}$(date)${RESET}"
    
    echo -e "\n  ${BOLD}--- Docker ---------------------------------------${RESET}"
    if command -v docker &>/dev/null; then
        ok "Docker installed: $(docker --version)"
        info "Docker Compose: $(docker compose version 2>/dev/null || echo 'N/A')"
    else
        err "Docker NOT installed"
    fi
    
    echo -e "\n  ${BOLD}--- Portainer ------------------------------------${RESET}"
    if docker ps --format '{{.Names}}' | grep -q "^portainer$"; then
        ok "Portainer running: http://localhost:${PORTAINER_PORT}"
    else
        warn "Portainer not running"
    fi
    
    echo -e "\n  ${BOLD}--- Ollama ---------------------------------------${RESET}"
    if docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        ok "Ollama container running"
        if curl -s --connect-timeout 2 "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
            ok "Ollama API responding"
            local models
            models=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' '  ' || echo "none")
            info "Models: ${models:-none}"
        fi
    else
        err "Ollama container NOT running"
    fi
    
    echo -e "\n  ${BOLD}--- Open WebUI -----------------------------------${RESET}"
    if docker ps --format '{{.Names}}' | grep -q "^open-webui$"; then
        ok "Open WebUI running: http://localhost:${OPEN_WEBUI_PORT}"
    else
        err "Open WebUI NOT running"
    fi
    
    echo -e "\n  ${BOLD}--- OpenCode (optional) -------------------------${RESET}"
    if command -v opencode &>/dev/null; then
        ok "opencode installed: $(which opencode)"
    else
        info "OpenCode NOT installed (optional, runs natively)"
    fi
    
    echo -e "\n  ${BOLD}--- GPU -----------------------------------------${RESET}"
    if [ "$HAS_GPU" = true ]; then
        ok "NVIDIA GPU detected"
        if [ "$HAS_NVIDIA_DOCKER" = true ]; then
            ok "GPU available to Docker containers"
        else
            warn "GPU detected but NVIDIA Container Toolkit not installed"
        fi
    else
        info "No GPU detected (using CPU)"
    fi
    
    echo ""
    line
    info "Base directory: ${AI_BASE_DIR}"
}

# ── Update components ──────────────────────────────────────────────────────────
update_components() {
    step "Updating AI Stack Components"
    
    if [ ! -f "${AI_BASE_DIR}/docker-compose.yml" ]; then
        err "Stack not deployed. Run './aistack.sh install' first"
        return 1
    fi
    
    cd "${AI_BASE_DIR}"
    
    echo ""
    echo -e "  ${BOLD}Components to update:${RESET}"
    echo -e "  ${WHITE}1)${RESET} Update All (Docker + Portainer + Ollama + LLM + Open WebUI)"
    echo -e "  ${WHITE}2)${RESET} Update Ollama + LLM + Open WebUI"
    echo -e "  ${WHITE}3)${RESET} Update Docker + Portainer"
    echo -e "  ${WHITE}4)${RESET} Update OpenCode (if installed)"
    echo -e "  ${WHITE}0)${RESET} Back"
    echo ""
    read -rp "  → Select option: " update_opt
    
    case "$update_opt" in
        1)
            step "Updating EVERYTHING..."
            # Update AI Stack
            docker pull ollama/ollama:latest
            docker pull ghcr.io/open-webui/open-webui:main
            docker compose up -d --pull always --force-recreate
            
            # Update Portainer (Silencioso)
            info "Updating Portainer..."
            docker stop portainer >/dev/null 2>&1 || true
            docker rm portainer >/dev/null 2>&1 || true
            docker pull portainer/portainer-ce:latest
            docker run -d -p ${PORTAINER_PORT}:9000 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data portainer/portainer-ce:latest >/dev/null
            
            docker image prune -f >/dev/null
            ok "Full stack updated"
            ;;
        2)
            step "Updating Ollama, LLM and Web UI..."
            docker pull ollama/ollama:latest
            docker pull ghcr.io/open-webui/open-webui:main
            docker compose up -d --pull always --force-recreate
            docker image prune -f >/dev/null
            ok "AI components updated"
            ;;
        3)
            step "Updating Docker Engine & Portainer..."
            # Actualización de binarios del sistema
            apt-get update -qq
            apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
            
            # Update Portainer (Silencioso)
            docker stop portainer >/dev/null 2>&1 || true
            docker rm portainer >/dev/null 2>&1 || true
            docker pull portainer/portainer-ce:latest
            docker run -d -p ${PORTAINER_PORT}:9000 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data portainer/portainer-ce:latest >/dev/null
            
            docker image prune -f >/dev/null
            ok "Docker and Portainer updated"
            ;;
        4)
            if command -v opencode &>/dev/null; then
                step "Updating opencode..."
                if command -v npm &>/dev/null && npm list -g opencode-ai &>/dev/null 2>&1; then
                    npm update -g opencode-ai >/dev/null 2>&1
                    ok "OpenCode updated via npm"
                else
                    info "Reinstalling via official script..."
                    sudo -u "$local_user" curl -fsSL https://opencode.ai/install | sudo -u "$local_user" bash >/dev/null 2>&1
                    ok "OpenCode reinstalled"
                fi
            else
                warn "OpenCode not installed"
            fi
            ;;
        0)
            return
            ;;
        *)
            warn "Invalid option"
            ;;
    esac
    
    echo ""
    ok "Update completed"
    info "Note: For Open WebUI changes, remember to refresh (Ctrl+F5)."
}

# ── Full installation (without OpenCode) ──────────────────────────────────────
install_all() {
    step "Full AI Stack Installation (Dockerized)"
    echo ""

    # ── Check for native installations before proceeding ──────────────────
    detect_native_components
    local native_warn=false
    [ "$NATIVE_OLLAMA" = true ]     && native_warn=true
    [ "$NATIVE_OPENWEBUI" = true ]  && native_warn=true
    [ "$NATIVE_PORTAINER" = true ]  && native_warn=true

    if [ "$native_warn" = true ]; then
        echo ""
        echo -e "  ${YELLOW}┌─────────────────────────────────────────────────────┐${RESET}"
        echo -e "  ${YELLOW}│  ⚠  NATIVE COMPONENTS DETECTED OUTSIDE DOCKER       │${RESET}"
        echo -e "  ${YELLOW}└─────────────────────────────────────────────────────┘${RESET}"
        echo ""
        [ "$NATIVE_OLLAMA" = true ]     && warn "Ollama is installed natively on this system"
        [ "$NATIVE_OPENWEBUI" = true ]  && warn "Open WebUI is installed natively on this system"
        [ "$NATIVE_PORTAINER" = true ]  && warn "A service is using port ${PORTAINER_PORT} outside Docker"
        echo ""
        echo -e "  ${DIM}These may conflict with the Docker-based installation${RESET}"
        echo -e "  ${DIM}(port conflicts, shared resources, etc.)${RESET}"
        echo ""
        read -rp "  Continue with Docker installation anyway? [y/N]: " proceed
        if [[ ! "$proceed" =~ ^[yY]$ ]]; then
            info "Installation cancelled"
            return 0
        fi
        echo ""
    fi

    detect_gpu
    echo ""

    select_model
    echo ""
    
    install_docker
    echo ""
    
    install_nvidia_docker
    echo ""
    
    create_docker_compose
    echo ""
    
    deploy_stack
    echo ""
    
    download_model
    echo ""
    
    line
    ok "${BOLD}AI Stack fully installed and running!${RESET}"
    echo ""
    
    # ============================================================
    # POST-INSTALLATION MESSAGE
    # ============================================================
    echo -e "  ${BOLD}${GREEN}++++++++++++++++++++++++++++++++++++++++++++++++++++++${RESET}"
    echo -e "  ${BOLD}${GREEN}  WHAT TO DO NEXT${RESET}"
    echo -e "  ${BOLD}${GREEN}++++++++++++++++++++++++++++++++++++++++++++++++++++++${RESET}"
    echo ""
    echo -e "  ${BOLD}Access your AI services:${RESET}"
    echo ""
    echo -e "  ${WHITE}➜ Open Web UI:${RESET}  ${CYAN}http://localhost:${OPEN_WEBUI_PORT}${RESET}"
    echo -e "  ${WHITE}➜ Portainer:${RESET}     ${CYAN}http://localhost:${PORTAINER_PORT}${RESET}"
    echo -e "  ${WHITE}➜ Ollama API:${RESET}    ${CYAN}http://localhost:${OLLAMA_PORT}${RESET}"
    echo ""
    echo -e "  ${BOLD}First time using Open Web UI:${RESET}"
    echo -e "  ${DIM}1. Open http://localhost:${OPEN_WEBUI_PORT} in your browser${RESET}"
    echo -e "  ${DIM}2. Create an admin account${RESET}"
    echo -e "  ${DIM}3. Select model: ${SELECTED_MODEL}${RESET}"
    echo -e "  ${DIM}4. Start chatting!${RESET}"
    echo ""
    echo -e "  ${BOLD}Optional: OpenCode CLI tool${RESET}"
    echo -e "  ${DIM}OpenCode provides AI assistance in your terminal/editor${RESET}"
    echo -e "  ${DIM}To install it, select option 2 from the main menu${RESET}"
    echo ""
    echo -e "  ${BOLD}Useful commands:${RESET}"
    echo -e "  ${DIM}View logs:   cd ${AI_BASE_DIR} && docker compose logs -f${RESET}"
    echo -e "  ${DIM}Stop stack:  cd ${AI_BASE_DIR} && docker compose down${RESET}"
    echo -e "  ${DIM}Start stack: cd ${AI_BASE_DIR} && docker compose up -d${RESET}"
    echo -e "  ${DIM}View status: ./aistack.sh status${RESET}"
    echo ""
    echo -e "  ${BOLD}${GREEN}++++++++++++++++++++++++++++++++++++++++++++++++++++++${RESET}"
    echo ""
}

# ── Uninstall Submenu ──────────────────────────────────────────────────────────
menu_uninstall() {
    while true; do
        clear
        echo -e "${RED}"
        echo "  +------------------------------------------------------+"
        echo "  |                 UNINSTALL MENU                       |"
        echo "  +------------------------------------------------------+"
        echo -e "${RESET}"
        echo ""
        echo -e "  ${BOLD}Select what to uninstall:${RESET}"
        echo ""
        echo -e "  ${RED}COMPLETE${RESET}"
        echo -e "  ${WHITE}1)${RESET}  Uninstall EVERYTHING (containers + Docker + data)"
        echo ""
        echo -e "  ${YELLOW}COMPONENTS${RESET}"
        echo -e "  ${WHITE}2)${RESET}  Uninstall Open Web UI only"
        echo -e "  ${WHITE}3)${RESET}  Uninstall Ollama only"
        echo -e "  ${WHITE}4)${RESET}  Uninstall Portainer only"
        echo -e "  ${WHITE}5)${RESET}  Uninstall models only (keep everything else)"
        echo ""
        echo -e "  ${WHITE}0)${RESET}  Back to main menu"
        echo ""
        line
        echo -n "  → Option: "
        read -r opt

        case "$opt" in
            1)  uninstall_all; return ;;
            2)  uninstall_open_webui; return ;;
            3)  uninstall_ollama_container; return ;;
            4)  uninstall_portainer; return ;;
            5)  uninstall_models_only; return ;;
            0)  return ;;
            *)  warn "Invalid option" ;;
        esac
    done
}

# ── Main Menu ──────────────────────────────────────────────────────────────────
menu_main() {
    while true; do
        header
        echo -e "  ${BOLD}Select an option:${RESET}"
        echo ""
        echo -e "  ${WHITE}1)${RESET}  Install Stack (Docker/Portainer + Ollama/LLM + Open WebUI)"
        echo -e "  ${WHITE}2)${RESET}  Install/Uninstall OpenCode (optional CLI tool)"
        echo -e "  ${WHITE}3)${RESET}  Manage LLM Models (install/remove/change)"
        echo -e "  ${WHITE}4)${RESET}  Update Components"
        echo -e "  ${WHITE}5)${RESET}  Uninstall Stack Components"
        echo -e "  ${WHITE}6)${RESET}  Status"
        echo -e "  ${WHITE}7)${RESET}  View logs"
        echo -e "  ${WHITE}0)${RESET}  Exit"
        echo ""
        line
        echo -n "  → Option: "
        read -r opt

        case "$opt" in
            1)  install_all; pause ;;
            2)  menu_opencode; pause ;;
            3)  menu_models; pause ;;
            4)  update_components; pause ;;      # ← NUEVO: llama a la función
            5)  menu_uninstall; pause ;;         # ← antes era 4
            6)  detect_gpu; status_all; pause ;; # ← antes era 5
            7)  if [ -f "${AI_BASE_DIR}/docker-compose.yml" ]; then
                    cd "${AI_BASE_DIR}" && docker compose logs | less -R
                fi
                pause ;;
            0)  exit ;;
            *)  warn "Invalid option" ;;
        esac
    done
}

# ── CLI Mode ───────────────────────────────────────────────────────────────────
cli_mode() {
    case "${1:-}" in
        install)
            detect_gpu
            install_docker
            install_nvidia_docker
            create_docker_compose
            deploy_stack
            select_model
            download_model
            ;;
        install-opencode)
            install_opencode
            ;;
        uninstall-opencode)
            uninstall_opencode
            ;;
        uninstall)
            uninstall_all
            ;;
        status)
            detect_gpu
            status_all
            ;;
        model)
            select_model
            download_model
            ;;
        help|--help|-h)
            echo ""
            echo "AI Stack Manager - Dockerized Version"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  install             - Install AI Stack (Docker/Portained + Ollama/LLM + Open WebUI)"
            echo "  install-opencode    - Install OpenCode (optional CLI tool)"
            echo "  uninstall-opencode  - Uninstall OpenCode"
            echo "  uninstall           - Remove everything"
            echo "  status              - Show current status"
            echo "  model               - Download a model"
            echo ""
            echo "Without arguments, runs interactive menu"
            ;;
        *)
            err "Unknown command: ${1:-}"
            cli_mode help
            exit 1
            ;;
    esac
}

# ── Entry Point ────────────────────────────────────────────────────────────────
# Initial check for apt
apt-get update -qq 2>/dev/null || true

if [[ $# -eq 0 ]]; then
    menu_main
else
    cli_mode "$@"
fi
