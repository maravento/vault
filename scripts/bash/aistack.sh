#!/bin/bash
# maravento.com
#
################################################################################
#
#  AI STACK MANAGER - Dockerized Version
#
#  Stack:      Docker + Portainer + Ollama + Open WebUI
#  Optional:   OpenCode (AI CLI tool, runs natively)
#              LM Studio (desktop app for local LLMs, requires GUI)
#
#  LLM models are managed independently from the stack installation.
#  Online models (OpenAI, Anthropic, etc.) can be connected via Open WebUI.
#
#  Usage: ./aistack.sh [COMMAND]
#  Commands:
#  install | status | model | install-opencode | update-opencode | uninstall-opencode | uninstall
#  Without arguments, runs interactive menu
#
################################################################################

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
fi

# LOCAL USER (multi-strategy detection with validation)
local_user=""
# 1. Local graphical session (:0)
local_user=$(who | awk '/\(:0\)/{print $1; exit}')
# 2. Parent process logname (works well with sudo)
[ -z "$local_user" ] && local_user=$(logname 2>/dev/null || true)
# 3. SUDO_USER variable (when run via sudo from terminal)
[ -z "$local_user" ] && local_user="${SUDO_USER:-}"
# 4. First active session user (SSH or other)
[ -z "$local_user" ] && local_user=$(who | awk 'NR==1{print $1}')
# 5. First valid home directory
[ -z "$local_user" ] && local_user=$(ls -l /home 2>/dev/null | awk '/^d/{print $3; exit}')
# Validate the user actually exists on the system
if [ -z "$local_user" ] || ! id "$local_user" &>/dev/null; then
    echo "ERROR: Cannot determine a valid local user"
    exit 1
fi

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
AI_BASE_DIR="/home/$local_user/aiworker"
OPEN_WEBUI_PORT=3000
OLLAMA_PORT=11434
PORTAINER_PORT=9000

# Ensure the base directory exists and belongs to the local user from the start
sudo -u "$local_user" bash -c "mkdir -p \"$AI_BASE_DIR\""

HAS_GPU=false
HAS_NVIDIA_DOCKER=false

# GPU Detection
detect_gpu() {
    HAS_GPU=false
    HAS_NVIDIA_DOCKER=false
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        HAS_GPU=true
        echo "NVIDIA GPU detected"
        nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | xargs echo "   GPU Model:"
        
        # Check if nvidia-docker is installed
        if command -v nvidia-container-toolkit &>/dev/null || \
           docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &>/dev/null 2>&1; then
            HAS_NVIDIA_DOCKER=true
            echo "NVIDIA Container Toolkit detected (GPU will be used)"
        else
            echo "   NVIDIA Container Toolkit not installed"
            echo "   GPU available but Docker cannot use it"
            echo "   Install with:"
            echo "   apt install -y nvidia-container-toolkit"
            echo "   systemctl restart docker"
        fi
    else
        echo "No NVIDIA GPU detected (will use CPU for Ollama)"
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
    "llama3.3:70b"           # State-of-the-art 2025, ~43GB RAM, matches Llama 3.1 405B quality
    "gemma4:31b"             # Maximum quality, needs 20GB RAM, high-end GPU
    "gemma4:26b"             # MoE architecture, needs 18GB RAM
    "qwen2.5-coder:14b"      # Top-rated coding model 2026, ~9GB RAM, 16GB recommended
    "mistral-small3.2"       # Latest Mistral Small, improved function calling, ~14GB RAM
    "phi4:14b"               # Microsoft Phi-4, punches above its weight, ~9GB RAM, MIT license
    "qwen2.5:14b"            # General purpose, strong multilingual, ~9GB RAM
    "gemma3:12b"             # Google Gemma 3, vision + creative writing, ~8GB RAM
    "qwen2.5-coder:7b"       # Powerful for coding, 6-8GB RAM
    "gemma4:e4b"             # Balanced multimodal, 5-6GB RAM
    "codellama:7b"           # Code-specialized, 6-8GB RAM
    "deepseek-coder-v2:16b"  # DeepSeek Coder V2, MoE, ~8.9GB RAM, MIT license
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
  echo "  |        AI STACK MANAGER - Dockerized v1.2            |"
  echo "  |        Ollama · Open Web UI · Portainer              |"
  echo "  +------------------------------------------------------+"
  echo -e "${RESET}"
  echo -e "  ${DIM}Base directory: ${WHITE}${AI_BASE_DIR}${RESET}"
  echo ""
}

ok()   { echo -e "  ${GREEN}[OK]${RESET}  $*"; }
err()  { echo -e "  ${RED}[ERROR]${RESET}  $*"; }
info() { echo -e "  ${BLUE}[INFO]${RESET}  $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${RESET}  $*"; }
step() { echo -e "\n  ${MAGENTA}>>${RESET}  ${BOLD}$*${RESET}"; }
line() { echo -e "  ${DIM}------------------------------------------------${RESET}"; }

pause() { echo ""; read -rp "  Press Enter to continue..." _; }

# ── Model selection menu ──────────────────────────────────────────────────────
select_model() {
    echo ""
    echo -e "  ${BOLD}Available Local Models:${RESET}"
    echo ""
    echo -e "  ${WHITE}0)${RESET} ${DIM}Skip — do not download a model now${RESET}"
    echo ""
    
    local i=1
    for model in "${AVAILABLE_MODELS[@]}"; do
        if [[ "$model" == "$DEFAULT_MODEL" ]]; then
            echo -e "  ${WHITE}$i)${RESET} $model ${DIM}(default)${RESET}"
        else
            echo -e "  ${WHITE}$i)${RESET} $model"
        fi
        i=$((i+1))
    done
    
    echo ""
    echo -e "  ${DIM}Press Enter to use default: ${DEFAULT_MODEL}${RESET}"
    echo ""
    read -rp "  → Select model [0-${#AVAILABLE_MODELS[@]}]: " choice
    
    if [[ -z "$choice" ]]; then
        SELECTED_MODEL="$DEFAULT_MODEL"
    elif [[ "$choice" == "0" ]]; then
        SELECTED_MODEL=""
        echo ""
        info "No model selected — you can download one later with: ./aistack.sh model"
        return 0
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
        rm -f /etc/apt/keyrings/docker.gpg /tmp/docker_$$.gpg
        mkdir -p /etc/apt/keyrings
        if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker_$$.gpg; then
            err "Failed to download Docker GPG key"
            rm -f /tmp/docker_$$.gpg
            exit 1
        fi
        DOCKER_GPG_FINGERPRINT=$(gpg --with-fingerprint --with-colons /tmp/docker_$$.gpg 2>/dev/null \
            | awk -F: '/^fpr/{print $10; exit}')
        DOCKER_GPG_EXPECTED="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
        if [ "$DOCKER_GPG_FINGERPRINT" != "$DOCKER_GPG_EXPECTED" ]; then
            err "Docker GPG key fingerprint mismatch!"
            err "  Expected: $DOCKER_GPG_EXPECTED"
            err "  Got:      ${DOCKER_GPG_FINGERPRINT:-<empty>}"
            rm -f /tmp/docker_$$.gpg
            exit 1
        fi
        gpg --dearmor < /tmp/docker_$$.gpg > /etc/apt/keyrings/docker.gpg
        chmod 644 /etc/apt/keyrings/docker.gpg
        rm -f /tmp/docker_$$.gpg
        ok "Docker GPG key verified (fingerprint OK)"

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
        usermod -aG docker "$local_user"
        
        ok "Docker installed successfully"
    fi
    
    # Verify Docker Compose plugin
    if ! docker compose version &>/dev/null; then
        err "Docker Compose plugin not available"
        exit 1
    fi
    
    # Install Portainer
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
        ok "Portainer already running"
    else
        info "Installing Portainer..."
        docker volume create portainer_data 2>/dev/null || true
        docker run -d -p ${PORTAINER_PORT}:9000 --name portainer --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data portainer/portainer-ce:lts
        
        ok "Portainer installed"
        info "Access: http://localhost:${PORTAINER_PORT}"
    fi
}

# ── Install NVIDIA Container Toolkit (if GPU detected) ─────────────────────────
install_nvidia_docker() {
    if [ "$HAS_GPU" = true ] && [ "$HAS_NVIDIA_DOCKER" = false ]; then
        step "Installing NVIDIA Container Toolkit"
        
        # Add NVIDIA repository - using keyrings (apt-key is deprecated)
        distribution=$(. /etc/os-release; echo "$ID$VERSION_ID")
        rm -f /etc/apt/keyrings/nvidia-docker.gpg /tmp/nvidia_docker_$$.gpg
        mkdir -p /etc/apt/keyrings
        if ! curl -fsSL https://nvidia.github.io/nvidia-docker/gpgkey -o /tmp/nvidia_docker_$$.gpg; then
            err "Failed to download NVIDIA Docker GPG key"
            rm -f /tmp/nvidia_docker_$$.gpg
            exit 1
        fi
        gpg --dearmor < /tmp/nvidia_docker_$$.gpg > /etc/apt/keyrings/nvidia-docker.gpg
        chmod 644 /etc/apt/keyrings/nvidia-docker.gpg
        rm -f /tmp/nvidia_docker_$$.gpg
        # Add repo with signed-by pointing to its own keyring (not the global one)
        curl -fsSL "https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list" \
            | sed 's|deb https://|deb [signed-by=/etc/apt/keyrings/nvidia-docker.gpg] https://|g' \
            | tee /etc/apt/sources.list.d/nvidia-docker.list > /dev/null
        ok "NVIDIA Docker GPG key imported to keyrings"
        
        apt-get update
        apt-get install -y nvidia-container-toolkit
        
        # Configure Docker daemon — merge nvidia runtime into existing config if present
        mkdir -p /etc/docker
        local daemon_json="/etc/docker/daemon.json"
        if command -v jq &>/dev/null && [ -s "$daemon_json" ]; then
            local tmp_daemon
            tmp_daemon=$(mktemp)
            jq 'if (.runtimes.nvidia | type) == "object" then . else .runtimes = (.runtimes // {} | .nvidia = {"path": "nvidia-container-runtime", "runtimeArgs": []}) end'                 "$daemon_json" > "$tmp_daemon" && mv "$tmp_daemon" "$daemon_json"
        else
            cat > "$daemon_json" << EOF
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EOF
        fi
        
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
    
    cd "${AI_BASE_DIR}" || { err "Cannot cd to ${AI_BASE_DIR}"; return 1; }

    # Pull images with retry logic (large images can fail on unstable connections)
    info "Pulling Docker images (may take several minutes)..."
    local max_attempts=5
    local attempt=1
    until docker compose pull; do
        if [ $attempt -ge $max_attempts ]; then
            err "Failed to pull Docker images after $max_attempts attempts"
            return 1
        fi
        warn "Pull failed (attempt $attempt/$max_attempts) — retrying in 10 seconds..."
        attempt=$((attempt + 1))
        sleep 10
    done
    
    # Start services
    info "Starting services..."
    docker compose up -d
    
    ok "AI Stack deployed successfully"
}

# ── Guard: verify Docker is active and ollama container is running ────────────
require_ollama_running() {
    if ! command -v docker &>/dev/null; then
        err "Docker is not installed"
        return 1
    fi
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        err "Docker daemon is not running. Start it with: systemctl start docker"
        return 1
    fi
    if ! docker ps --format '{{.Names}}' | grep -q "^ollama$"; then
        err "Ollama container is not running. Start the stack first:"
        info "  cd ${AI_BASE_DIR} && docker compose up -d"
        return 1
    fi
}

# ── Download Model ────────────────────────────────────────────────────────────
download_model() {
    if [[ -z "${SELECTED_MODEL:-}" ]]; then
        info "No model selected — skipping download"
        return 0
    fi
    step "Downloading model: ${SELECTED_MODEL}"
    require_ollama_running || return 1
    
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
        warn "No models installed yet"
        info "Select an option below to download one"
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
        i=$((i+1))
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
    require_ollama_running || return 1
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
    
    echo -e "  ${DIM}   OpenCode runs natively on your system (not in Docker)${RESET}"
    echo -e "  ${DIM}   It provides AI assistance directly in your terminal/editor${RESET}"
    echo -e "  ${DIM}   You don't need it if you already use Open Web UI${RESET}"
    echo ""
    
    if command -v opencode &>/dev/null; then
        warn "opencode already installed"
        return 0
    fi
    
    # Detect Node.js installed via apt — conflicts with nvm-managed Node.js
    if command -v node &>/dev/null; then
        local node_path
        node_path=$(command -v node)
        if [[ "$node_path" == /usr/bin/node || "$node_path" == /usr/local/bin/node ]]; then
            err "Node.js is installed system-wide via apt ($node_path)"
            err "This conflicts with nvm and must be removed before continuing"
            info "Run: sudo apt remove --purge nodejs npm -y && sudo apt autoremove -y"
            return 1
        fi
    fi

    # Ensure nvm is installed (needed to manage Node.js without apt)
    local nvm_dir="/home/$local_user/.nvm"
    if [ ! -f "$nvm_dir/nvm.sh" ]; then
        info "Installing nvm (Node Version Manager) for user: $local_user..."
        local nvm_tmp
        nvm_tmp=$(mktemp /tmp/nvm_install_XXXXXX.sh)
        if ! curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh -o "$nvm_tmp"; then
            err "Failed to download nvm install script"
            rm -f "$nvm_tmp"
            return 1
        fi
        if ! head -1 "$nvm_tmp" | grep -qE '^#!((/usr)?/bin/(ba)?sh|/usr/bin/env (ba)?sh)'; then
            err "Downloaded nvm install script does not look like a shell script — aborting"
            rm -f "$nvm_tmp"
            return 1
        fi
        chown "$local_user" "$nvm_tmp"
        chmod +x "$nvm_tmp"
        if ! sudo -u "$local_user" bash "$nvm_tmp"; then
            err "nvm installation failed"
            rm -f "$nvm_tmp"
            return 1
        fi
        rm -f "$nvm_tmp"
        ok "nvm installed"
    else
        ok "nvm already installed"
    fi

    # Ensure Node.js LTS is installed via nvm
    local nvm_sh="$nvm_dir/nvm.sh"
    if ! sudo -u "$local_user" bash -c "source '$nvm_sh' && command -v node" &>/dev/null; then
        info "Installing Node.js LTS via nvm..."
        if ! sudo -u "$local_user" bash -c "source '$nvm_sh' && nvm install --lts"; then
            err "Node.js installation via nvm failed"
            return 1
        fi
        ok "Node.js LTS installed"
    else
        local node_ver
        node_ver=$(sudo -u "$local_user" bash -c "source '$nvm_sh' && node --version" 2>/dev/null)
        ok "Node.js already installed ($node_ver)"
    fi

    # pnpm is required (preferred over npm for security: avoids supply-chain attacks via hoisting)
    # Minimum version: 11
    local pnpm_home="/home/$local_user/.local/share/pnpm"
    local pnpm_env="source $(printf '%q' "$nvm_sh"); export PNPM_HOME=$(printf '%q' "$pnpm_home"); export PATH=\"\$PNPM_HOME/bin:\$PATH\""
    if [ ! -f "$pnpm_home/bin/pnpm" ]; then
        info "Installing pnpm..."
        local pnpm_tmp
        pnpm_tmp=$(mktemp /tmp/pnpm_install_XXXXXX.sh)
        if ! curl -fsSL https://get.pnpm.io/install.sh -o "$pnpm_tmp"; then
            err "Failed to download pnpm install script"
            rm -f "$pnpm_tmp"
            return 1
        fi
        if ! head -1 "$pnpm_tmp" | grep -qE '^#!((/usr)?/bin/(ba)?sh|/usr/bin/env (ba)?sh)'; then
            err "Downloaded pnpm install script does not look like a shell script — aborting"
            rm -f "$pnpm_tmp"
            return 1
        fi
        chown "$local_user" "$pnpm_tmp"
        chmod +x "$pnpm_tmp"
        if ! sudo -u "$local_user" bash "$pnpm_tmp"; then
            err "pnpm installation failed"
            rm -f "$pnpm_tmp"
            return 1
        fi
        rm -f "$pnpm_tmp"
        ok "pnpm installed"
    else
        ok "pnpm already installed"
    fi

    # Verify pnpm version >= 11
    local pnpm_version pnpm_ver_full
    pnpm_ver_full=$(sudo -u "$local_user" bash -c "$pnpm_env; pnpm --version 2>/dev/null" || echo 'unknown')
    pnpm_version=$(echo "$pnpm_ver_full" | grep -oE '^[0-9]+')
    if [ -z "$pnpm_version" ] || [ "$pnpm_version" -lt 11 ]; then
        err "pnpm version 11 or higher is required (found: $pnpm_ver_full)"
        info "Upgrade with: pnpm self-update"
        return 1
    fi
    ok "pnpm $pnpm_ver_full detected"

    info "Installing via pnpm (official package)..."
    local pnpm_bin="/home/$local_user/.local/share/pnpm/bin/pnpm"
    if ! printf 'a\n' | sudo -u "$local_user" bash -c "$pnpm_env; '$pnpm_bin' add -g opencode-ai@latest"; then
        err "pnpm failed to install opencode-ai"
        return 1
    fi
    local opencode_bin="/home/$local_user/.local/share/pnpm/bin/opencode"
    if [ -f "$opencode_bin" ]; then
        # Rename the real binary and replace it with a wrapper that loads nvm before executing
        # This ensures node is in PATH regardless of how the user invokes opencode
        mv "$opencode_bin" "${opencode_bin}.real"
        cat > "$opencode_bin" << WRAPPER
#!/bin/bash
export NVM_DIR="/home/$local_user/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"
exec "${opencode_bin}.real" "\$@"
WRAPPER
        chmod +x "$opencode_bin"
        # Symlink into system PATH so root and other users can also invoke it
        ln -sf "$opencode_bin" /usr/local/bin/opencode

        # Run postinstall explicitly — pnpm skips it by default for global packages.
        # pnpm root -g does not expose node_modules; locate the script directly
        # in the content-addressable store and cd into it before running node.
        local pnpm_store="/home/$local_user/.local/share/pnpm/store"
        local postinstall_path
        postinstall_path=$(find "$pnpm_store" -name "postinstall.mjs" -path "*/opencode-ai/*" 2>/dev/null | sort -V | tail -1)
        if [ -n "$postinstall_path" ]; then
            local postinstall_dir
            postinstall_dir=$(dirname "$postinstall_path")
            info "Running postinstall script..."
            sudo -u "$local_user" bash -c "$pnpm_env; cd '$postinstall_dir' && node postinstall.mjs"
        fi

        ok "opencode installed via pnpm"
        return 0
    fi
    
    # Fallback: Official install script as the real user (not root)
    # Separate download from execution to allow inspection and avoid pipe-to-bash
    info "Installing via official install script as user: $local_user..."
    local install_tmp
    install_tmp=$(mktemp /tmp/opencode_install_XXXXXX.sh)
    if ! curl -fsSL https://opencode.ai/install -o "$install_tmp"; then
        err "Failed to download opencode install script"
        rm -f "$install_tmp"
        return 1
    fi
    # Verify the downloaded file is a valid shell script (sanity check)
    if ! head -1 "$install_tmp" | grep -qE '^#!((/usr)?/bin/(ba)?sh|/usr/bin/env (ba)?sh)'; then
        err "Downloaded opencode install script does not look like a shell script — aborting"
        rm -f "$install_tmp"
        return 1
    fi
    chown "$local_user" "$install_tmp"
    chmod +x "$install_tmp"
    if sudo -u "$local_user" bash "$install_tmp"; then
        rm -f "$install_tmp"
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

    local pnpm_home="/home/$local_user/.local/share/pnpm"
    local pnpm_bin="$pnpm_home/bin/pnpm"
    local nvm_sh="/home/$local_user/.nvm/nvm.sh"
    local pnpm_env="source $(printf '%q' "$nvm_sh") 2>/dev/null; export PNPM_HOME=$(printf '%q' "$pnpm_home"); export PATH=\"\$PNPM_HOME/bin:\$PATH\""

    # Check if opencode is actually installed anywhere
    local found=false
    [ -f "/usr/local/bin/opencode" ]                                                                                        && found=true
    [ -d "/home/$local_user/.opencode" ]                                                                                    && found=true
    [ -f "$pnpm_bin" ] && sudo -u "$local_user" bash -c "$pnpm_env; pnpm list -g opencode-ai" &>/dev/null 2>&1             && found=true

    if [ "$found" = false ]; then
        info "OpenCode is not installed — nothing to do"
        return 0
    fi

    # Uninstall via pnpm (handles removal of the binary and package metadata)
    if [ -f "$pnpm_bin" ] && sudo -u "$local_user" bash -c "$pnpm_env; pnpm list -g opencode-ai" &>/dev/null 2>&1; then
        sudo -u "$local_user" bash -c "$pnpm_env; pnpm remove -g opencode-ai" &>/dev/null
        ok "OpenCode uninstalled via pnpm"
    fi
    # Remove the real binary left behind after pnpm remove (wrapper replaced it)
    rm -f "$pnpm_home/bin/opencode.real"
    # Remove system symlink
    rm -f /usr/local/bin/opencode

    # Remove user installation (as the real user)
    if [ -d "/home/$local_user/.opencode" ]; then
        sudo -u "$local_user" rm -rf "/home/$local_user/.opencode"
        ok "Removed /home/$local_user/.opencode"
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

    # Offer to also remove nvm and pnpm installed by this script
    echo ""
    warn "nvm, Node.js and pnpm were installed as dependencies for OpenCode"
    echo ""
    read -rp "  Also remove nvm, Node.js and pnpm? [y/N]: " remove_deps
    if [[ "$remove_deps" =~ ^[yY]$ ]]; then
        # Remove pnpm
        if [ -d "$pnpm_home" ]; then
            sudo -u "$local_user" rm -rf "$pnpm_home"
            ok "Removed $pnpm_home"
        fi

        # Remove nvm and Node.js
        local nvm_dir="/home/$local_user/.nvm"
        if [ -d "$nvm_dir" ]; then
            sudo -u "$local_user" rm -rf "$nvm_dir"
            ok "Removed $nvm_dir"
        fi

        # Clean nvm and pnpm entries from shell config files
        local shell_configs=()
        for config in "/home/$local_user/.bashrc" "/home/$local_user/.zshrc" "/home/$local_user/.profile" "/home/$local_user/.bash_profile"; do
            [ -f "$config" ] && shell_configs+=("$config")
        done

        for config in "${shell_configs[@]}"; do
            if grep -qE 'NVM_DIR|nvm\.sh|nvm_bash_completion|PNPM_HOME' "$config" 2>/dev/null; then
                # Remove nvm block (export NVM_DIR + the two source lines)
                sed -i '/export NVM_DIR/d' "$config"
                sed -i '/NVM_DIR\/nvm\.sh/d' "$config"
                sed -i '/NVM_DIR\/bash_completion/d' "$config"
                # Remove pnpm block including the case/:$PATH:/esac wrapper
                # Strategy: delete from the export PNPM_HOME line through the closing esac
                sed -i '/export PNPM_HOME/,/^esac/d' "$config"
                # Remove any leftover standalone pnpm references
                sed -i '/pnpm/d' "$config"
                # Remove blank lines left at the end of the file
                sed -i -e '/^[[:space:]]*$/{ /./!d }' "$config"
                ok "Cleaned nvm/pnpm entries from $config"
            fi
        done

        ok "nvm, Node.js and pnpm removed"
    fi
}

# ── Update opencode to latest version ────────────────────────────────────────
update_opencode() {
    step "Updating opencode to latest version"

    if ! command -v opencode &>/dev/null; then
        warn "OpenCode is not installed — use Install instead"
        return 1
    fi

    local pnpm_home="/home/$local_user/.local/share/pnpm"
    local nvm_sh="/home/$local_user/.nvm/nvm.sh"
    local pnpm_env="source $(printf '%q' "$nvm_sh") 2>/dev/null; export PNPM_HOME=$(printf '%q' "$pnpm_home"); export PATH=\"\$PNPM_HOME/bin:\$PATH\""
    local pnpm_bin="$pnpm_home/bin/pnpm"

    if [ -f "$pnpm_bin" ] && sudo -u "$local_user" bash -c "$pnpm_env; pnpm list -g opencode-ai" &>/dev/null 2>&1; then
        info "Updating opencode-ai via pnpm..."
        if ! printf 'a\n' | sudo -u "$local_user" bash -c "$pnpm_env; '$pnpm_bin' update -g opencode-ai"; then
            err "pnpm update failed"
            return 1
        fi

        # Rebuild the nvm wrapper around the updated real binary if needed
        local opencode_bin="$pnpm_home/bin/opencode"
        if [ -f "${opencode_bin}.real" ]; then
            # Wrapper already exists — nothing extra to do
            :
        elif [ -f "$opencode_bin" ]; then
            mv "$opencode_bin" "${opencode_bin}.real"
            cat > "$opencode_bin" << WRAPPER
#!/bin/bash
export NVM_DIR="/home/$local_user/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"
exec "${opencode_bin}.real" "\$@"
WRAPPER
            chmod +x "$opencode_bin"
            ln -sf "$opencode_bin" /usr/local/bin/opencode
        fi

        # Run postinstall explicitly — pnpm skips it by default for global packages.
        # pnpm root -g does not expose node_modules; locate the script directly
        # in the content-addressable store and cd into it before running node.
        local pnpm_store="/home/$local_user/.local/share/pnpm/store"
        local postinstall_path
        postinstall_path=$(find "$pnpm_store" -name "postinstall.mjs" -path "*/opencode-ai/*" 2>/dev/null | sort -V | tail -1)
        if [ -n "$postinstall_path" ]; then
            local postinstall_dir
            postinstall_dir=$(dirname "$postinstall_path")
            info "Running postinstall script..."
            sudo -u "$local_user" bash -c "$pnpm_env; cd '$postinstall_dir' && node postinstall.mjs"
        fi

        ok "OpenCode updated via pnpm"
    else
        info "pnpm package not found — reinstalling via official script..."
        local update_tmp
        update_tmp=$(mktemp /tmp/opencode_update_XXXXXX.sh)
        if ! curl -fsSL https://opencode.ai/install -o "$update_tmp"; then
            err "Failed to download opencode install script"
            rm -f "$update_tmp"
            return 1
        fi
        if ! head -1 "$update_tmp" | grep -qE '^#!((/usr)?/bin/(ba)?sh|/usr/bin/env (ba)?sh)'; then
            err "Downloaded opencode script does not look like a shell script — aborting"
            rm -f "$update_tmp"
            return 1
        fi
        chown "$local_user" "$update_tmp"
        chmod +x "$update_tmp"
        if sudo -u "$local_user" bash "$update_tmp"; then
            rm -f "$update_tmp"
            ok "OpenCode updated via official script"
        else
            rm -f "$update_tmp"
            err "Update via official script failed"
            return 1
        fi
    fi

    if command -v opencode &>/dev/null; then
        local ver
        ver=$(sudo -u "$local_user" bash -c "source '$nvm_sh' 2>/dev/null; opencode --version 2>/dev/null" || echo "unknown")
        ok "OpenCode is now at version: $ver"
    fi
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
        echo -e "  ${WHITE}2)${RESET}  Update OpenCode"
        echo -e "  ${WHITE}3)${RESET}  Uninstall OpenCode"
        echo -e "  ${WHITE}0)${RESET}  Back to main menu"
        echo ""
        line
        echo -n "  → Option: "
        read -r opt

        case "$opt" in
            1)  install_opencode; return ;;
            2)  update_opencode; return ;;
            3)  uninstall_opencode; return ;;
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
    
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
        local models
        models=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ', ')
        if [[ -n "$models" ]]; then
            echo -e "  ${DIM}Installed models: ${models}${RESET}"
            echo ""
            read -rp "  Remove ALL models? [y/N]: " confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r model; do
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
    if docker --version >/dev/null 2>&1; then
        read -rp "  Remove Docker completely? [y/N]: " remove_docker
        if [[ "$remove_docker" =~ ^[yY]$ ]]; then
            local purge_failed=()
            for pkg in docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose docker-compose-v2; do
                if dpkg -s "$pkg" &>/dev/null; then
                    if ! apt-get purge -y "$pkg"; then
                        warn "Failed to purge package: $pkg"
                        purge_failed+=("$pkg")
                    fi
                fi
            done
            if [ ${#purge_failed[@]} -gt 0 ]; then
                err "Some packages could not be removed: ${purge_failed[*]}"
                info "Try manually: apt-get purge -y ${purge_failed[*]}"
            fi
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
            if [ -d "${AI_BASE_DIR}/lmstudio" ]; then
                find "${AI_BASE_DIR}" -mindepth 1 -maxdepth 1 ! -name "lmstudio" -exec rm -rf {} +
                ok "Data removed (lmstudio directory preserved)"
            else
                rm -rf "${AI_BASE_DIR}"
                ok "Data removed"
            fi
        else
            info "Data kept"
        fi
    else
        info "Not found — skipping"
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
    if docker --version >/dev/null 2>&1; then
        ok "Docker installed: $(docker --version)"
        info "Docker Compose: $(docker compose version 2>/dev/null || echo 'N/A')"
    else
        err "Docker NOT installed"
    fi
    
    echo -e "\n  ${BOLD}--- Portainer ------------------------------------${RESET}"
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^portainer$"; then
        ok "Portainer running: http://localhost:${PORTAINER_PORT}"
    elif command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
        warn "Portainer stopped (container exists but is not running)"
    else
        warn "Portainer not running"
    fi
    
    echo -e "\n  ${BOLD}--- Ollama ---------------------------------------${RESET}"
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ollama$"; then
        ok "Ollama container running"
        if curl -s --connect-timeout 2 "http://localhost:${OLLAMA_PORT}/api/tags" &>/dev/null; then
            ok "Ollama API responding"
            local models
            models=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' '  ' || echo "none")
            info "Models: ${models:-none}"
        fi
    elif command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' | grep -q "^ollama$"; then
        warn "Ollama container stopped (exists but is not running)"
    else
        err "Ollama container NOT running"
    fi
    
    echo -e "\n  ${BOLD}--- Open WebUI -----------------------------------${RESET}"
    if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^open-webui$"; then
        ok "Open WebUI running: http://localhost:${OPEN_WEBUI_PORT}"
    elif command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' | grep -q "^open-webui$"; then
        warn "Open WebUI stopped (container exists but is not running)"
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
    echo -e "  ${WHITE}0)${RESET} Back"
    echo ""
    read -rp "  → Select option: " update_opt

    case "$update_opt" in
        1)
            step "Updating EVERYTHING..."
            docker pull ollama/ollama:latest
            docker pull ghcr.io/open-webui/open-webui:main
            docker compose up -d --pull always
            info "Updating Portainer..."
            docker stop portainer >/dev/null 2>&1 || true
            docker rm portainer >/dev/null 2>&1 || true
            docker pull portainer/portainer-ce:lts
            docker run -d -p ${PORTAINER_PORT}:9000 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data portainer/portainer-ce:lts >/dev/null

            docker image prune -f >/dev/null
            ok "Full stack updated"
            ;;
        2)
            step "Updating Ollama, LLM and Web UI..."
            docker pull ollama/ollama:latest
            docker pull ghcr.io/open-webui/open-webui:main
            docker compose up -d --pull always
            docker image prune -f >/dev/null
            ok "AI components updated"
            ;;
        3)
            step "Updating Docker Engine & Portainer..."
            apt-get update -qq
            apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1

            docker stop portainer >/dev/null 2>&1 || true
            docker rm portainer >/dev/null 2>&1 || true
            docker pull portainer/portainer-ce:lts
            docker run -d -p ${PORTAINER_PORT}:9000 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data portainer/portainer-ce:lts >/dev/null

            docker image prune -f >/dev/null
            ok "Docker and Portainer updated"
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

    install_docker
    echo ""
    
    install_nvidia_docker
    echo ""
    
    create_docker_compose
    echo ""
    
    deploy_stack
    echo ""

    docker restart portainer > /dev/null 2>&1
    
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
    echo -e "  ${YELLOW}   ⚠  First startup takes 1-2 minutes — Open WebUI downloads${RESET}"
    echo -e "  ${YELLOW}      embedding models on first run. Subsequent starts are instant.${RESET}"
    echo -e "  ${DIM}2. Create an admin account${RESET}"
    echo -e "  ${DIM}3. Go to option 2 in the main menu to download a local LLM model${RESET}"
    echo -e "  ${DIM}   or connect an API provider (OpenAI, Anthropic, etc.) in Settings${RESET}"
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

# ── Install LM Studio ─────────────────────────────────────────────────────────
install_lmstudio() {
    step "Installing LM Studio (optional desktop app)"

    # Require a graphical environment
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        err "No graphical environment detected (DISPLAY and WAYLAND_DISPLAY are unset)"
        info "LM Studio requires a desktop environment to run"
        return 1
    fi

    # Only x86_64 is supported
    local arch
    arch=$(uname -m)
    if [ "$arch" != "x86_64" ]; then
        err "LM Studio only supports x86_64 (detected: $arch)"
        return 1
    fi

    if [ -f "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage" ]; then
        ok "LM Studio is already installed"
        return 0
    fi

    # Install libfuse2 dependency (required by AppImage)
    if ! dpkg -s libfuse2 &>/dev/null 2>&1; then
        info "Installing libfuse2 (required by AppImage)..."
        apt-get install -y libfuse2 &>/dev/null
        ok "libfuse2 installed"
    fi

    # Download AppImage
    info "Downloading LM Studio AppImage..."
    sudo -u "$local_user" bash -c "mkdir -p \"${AI_BASE_DIR}/lmstudio\""
    if ! curl -fL --progress-bar "https://lmstudio.ai/download/latest/linux/x64?format=AppImage" -o "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage"; then
        err "Failed to download LM Studio"
        rm -f "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage"
        return 1
    fi
    chown "$local_user" "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage"
    chmod +x "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage"

    # Create desktop entry for the local user
    local desktop_dir="/home/$local_user/.local/share/applications"
    mkdir -p "$desktop_dir"
    cat > "$desktop_dir/lmstudio.desktop" << EOF
[Desktop Entry]
Name=LM Studio
Comment=Run large language models locally
Exec=${AI_BASE_DIR}/lmstudio/LMStudio.AppImage --no-sandbox
Icon=lmstudio
Terminal=false
Type=Application
Categories=Development;Science;
EOF
    chown "$local_user" "$desktop_dir/lmstudio.desktop"

    # Create launcher in system PATH
    cat > /usr/local/bin/lmstudio << EOF
#!/bin/bash
exec ${AI_BASE_DIR}/lmstudio/LMStudio.AppImage --no-sandbox "\$@"
EOF
    chmod +x /usr/local/bin/lmstudio

    ok "LM Studio installed"
    info "Launch with: lmstudio  or from your application menu"
}

# ── Uninstall LM Studio ───────────────────────────────────────────────────────
uninstall_lmstudio() {
    step "Uninstalling LM Studio"

    local found=false
    [ -f "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage" ]                                && found=true
    [ -f "/usr/local/bin/lmstudio" ]                                        && found=true
    [ -f "/home/$local_user/.local/share/applications/lmstudio.desktop" ]   && found=true

    if [ "$found" = false ]; then
        info "LM Studio is not installed — nothing to do"
        return 0
    fi

    rm -f "${AI_BASE_DIR}/lmstudio/LMStudio.AppImage"
    rmdir "${AI_BASE_DIR}/lmstudio" 2>/dev/null || true
    rm -f "/usr/local/bin/lmstudio"
    rm -f "/home/$local_user/.local/share/applications/lmstudio.desktop"

    ok "LM Studio uninstalled"
}

# ── LM Studio menu ────────────────────────────────────────────────────────────
menu_lmstudio() {
    header
    echo -e "  LM Studio is an optional desktop app for running LLMs locally"
    echo -e "  It is NOT part of the Docker stack and runs natively on your system"
    echo ""
    echo -e "  ${WHITE}1)${RESET}  Install LM Studio"
    echo -e "  ${WHITE}2)${RESET}  Uninstall LM Studio"
    echo -e "  ${WHITE}0)${RESET}  Back to main menu"
    line
    echo -n "  → Option: "
    read -r opt
    case "$opt" in
        1)  install_lmstudio ;;
        2)  uninstall_lmstudio ;;
        0)  return ;;
        *)  warn "Invalid option" ;;
    esac
}


# ── Main Menu ──────────────────────────────────────────────────────────────────
menu_main() {
    while true; do
        header
        echo -e "  ${BOLD}Select an option:${RESET}"
        echo ""
        echo -e "  ${WHITE}1)${RESET}  Install Stack (Docker/Portainer + Ollama + Open WebUI)"
        echo -e "  ${WHITE}2)${RESET}  Manage LLM Models (download/remove/change)"
        echo -e "  ${WHITE}3)${RESET}  Update Components"
        echo -e "  ${WHITE}4)${RESET}  Uninstall Stack Components"
        echo -e "  ${WHITE}5)${RESET}  Install/Uninstall OpenCode (optional CLI tool)"
        echo -e "  ${WHITE}6)${RESET}  Install/Uninstall LM Studio (optional desktop app)"
        echo -e "  ${WHITE}7)${RESET}  Status"
        echo -e "  ${WHITE}8)${RESET}  View logs"
        echo -e "  ${WHITE}0)${RESET}  Exit"
        echo ""
        line
        echo -n "  → Option: "
        read -r opt

        case "$opt" in
            1)  install_all; pause ;;
            2)  menu_models; pause ;;
            3)  update_components; pause ;;
            4)  menu_uninstall; pause ;;
            5)  menu_opencode; pause ;;
            6)  menu_lmstudio; pause ;;
            7)  status_all; pause ;;
            8)  if [ -f "${AI_BASE_DIR}/docker-compose.yml" ]; then
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
            ;;
        install-opencode)
            install_opencode
            ;;
        update-opencode)
            update_opencode
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
            echo "  install             - Install AI Stack (Docker/Portainer + Ollama/LLM + Open WebUI)"
            echo "  install-opencode    - Install OpenCode (optional CLI tool)"
            echo "  update-opencode     - Update OpenCode to latest version"
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
