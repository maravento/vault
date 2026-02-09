#!/bin/bash
#
# Cloudflare Tunnel Service Manager (cftunnel)
# Unified control script for multiple Cloudflare Tunnels
#
# PREREQUISITES:
# ==============
# 1. Install cloudflared first:
#    https://pkg.cloudflare.com/index.html
#
# 2. For permanent tunnels, authenticate and create:
#    cloudflared tunnel login
#    cloudflared tunnel create TUNNEL_NAME
#    cloudflared tunnel route dns TUNNEL_NAME subdomain.yourdomain.com
#
# 3. Create config files in ~/.cloudflared/ with .yml extension
#
# USEFUL COMMANDS:
# ================
# cloudflared tunnel login                              # First-time authentication
# cloudflared tunnel list                               # List all tunnels
# cloudflared tunnel create TUNNEL_NAME                 # Create new tunnel
# cloudflared tunnel run TUNNEL_NAME                    # Start specific tunnel
# cloudflared tunnel route dns TUNNEL_NAME SUBDOMAIN    # Route DNS to tunnel
# cloudflared tunnel cleanup TUNNEL_NAME                # Cleanup tunnel connections
# cloudflared tunnel delete TUNNEL_NAME                 # Delete tunnel permanently
#
# FILE STRUCTURE:
# ===============
# ~/.cloudflared/
#   ├── cert.pem                 # Authentication certificate
#   ├── tunnel1.yml              # Tunnel configuration file
#   ├── tunnel2.yml              # Another tunnel configuration
#   ├── TUNNEL-ID.json           # Tunnel credentials
#   ├── tunnel1.pid              # PID file for tunnel1
#   ├── tunnel2.pid              # PID file for tunnel2
#   └── tunnel1.log              # Log file for tunnel1
#
# RECOMMENDATION:
# ===============
# Use permanent tunnels for production services and temporary tunnels
# only for quick testing and development purposes.
#
# For more information:
# https://developers.cloudflare.com/cloudflare-one/connections/connect-apps

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

### --- CONFIGURATION --- ###
USER_HOME="$(getent passwd "$USER" | cut -d: -f6)"
CONFIG_DIR="$USER_HOME/.cloudflared"
CLOUDFLARED_BIN="$(command -v cloudflared)"

if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    echo "❌ cloudflared is not installed or not in PATH."
    exit 1
fi
mkdir -p "$CONFIG_DIR"

### --- FUNCTIONS --- ###

# Function to detect all YML configuration files
detect_tunnels() {
    local tunnels=()
    if [[ -d "$CONFIG_DIR" ]]; then
        for file in "$CONFIG_DIR"/*.yml; do
            if [[ -f "$file" ]]; then
                local tunnel_name=$(basename "$file" .yml)
                tunnels+=("$tunnel_name")
            fi
        done
    fi
    echo "${tunnels[@]}"
}

# Function to get tunnel ID from YAML file
get_tunnel_id() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        grep "^tunnel:" "$config_file" | head -1 | awk '{print $2}'
    fi
}

start_tunnel() {
    local tunnel_name="$1"
    local config_file="$CONFIG_DIR/${tunnel_name}.yml"
    local pid_file="$CONFIG_DIR/${tunnel_name}.pid"
    local log_file="$CONFIG_DIR/${tunnel_name}.log"
    
    echo "🔵 Starting tunnel: $tunnel_name"
    echo "📄 Config: $config_file"

    if [[ ! -f "$config_file" ]]; then
        echo "❌ Config file does not exist: $config_file"
        return 1
    fi

    # Check if already running
    if [[ -f "$pid_file" ]]; then
        OLD_PID=$(cat "$pid_file")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "⚠️ Tunnel '$tunnel_name' already running (PID $OLD_PID)"
            read -p "Stop existing tunnel and start new one? (y/n): " RESTART
            if [[ ! "$RESTART" =~ ^[Yy]$ ]]; then
                return 0
            fi
            kill "$OLD_PID" 2>/dev/null
            sleep 1
            rm -f "$pid_file"
        else
            rm -f "$pid_file"
        fi
    fi

    # Extract tunnel ID from YAML
    TUNNEL_ID=$(get_tunnel_id "$config_file")
    if [[ -z "$TUNNEL_ID" ]]; then
        echo "❌ No 'tunnel:' entry found in config file."
        return 1
    fi

    echo "🚀 Running: cloudflared tunnel run --config $config_file $TUNNEL_ID"
    nohup "$CLOUDFLARED_BIN" --config "$config_file" tunnel run "$TUNNEL_ID" >> "$log_file" 2>&1 &

    NEW_PID=$!
    echo "$NEW_PID" > "$pid_file"

    sleep 2
    if kill -0 "$NEW_PID" 2>/dev/null; then
        echo "🟢 Tunnel '$tunnel_name' started (PID $NEW_PID)"
        echo "📋 Log file: $log_file"
        return 0
    else
        echo "❌ Failed to start tunnel '$tunnel_name'"
        tail -20 "$log_file"
        rm -f "$pid_file"
        return 1
    fi
}

stop_tunnel() {
    local tunnel_name="$1"
    local pid_file="$CONFIG_DIR/${tunnel_name}.pid"
    
    if [[ ! -f "$pid_file" ]]; then
        echo "🔴 Tunnel '$tunnel_name' not running."
        return
    fi

    PID=$(cat "$pid_file")

    echo "🔴 Stopping tunnel '$tunnel_name' (PID $PID)..."
    kill "$PID" 2>/dev/null
    sleep 1

    if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID"
    fi

    rm -f "$pid_file"
    echo "✔️ Tunnel '$tunnel_name' stopped."
}

stop_all_tunnels() {
    echo "🔴 Stopping all Cloudflare tunnels..."
    
    # Find all .pid files and stop them
    for pid_file in "$CONFIG_DIR"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local tunnel_name=$(basename "$pid_file" .pid)
            local PID=$(cat "$pid_file")
            
            if kill -0 "$PID" 2>/dev/null; then
                echo "Stopping tunnel '$tunnel_name' (PID $PID)..."
                kill "$PID" 2>/dev/null
                sleep 1
                if kill -0 "$PID" 2>/dev/null; then
                    kill -9 "$PID"
                fi
                rm -f "$pid_file"
                echo "✔️ Tunnel '$tunnel_name' stopped."
            else
                rm -f "$pid_file"
            fi
        fi
    done
    
    echo "✅ All tunnels stopped."
}

status_tunnel() {
    local tunnel_name="$1"
    local pid_file="$CONFIG_DIR/${tunnel_name}.pid"
    local log_file="$CONFIG_DIR/${tunnel_name}.log"

    if [[ ! -f "$pid_file" ]]; then
        echo "🔴 Tunnel '$tunnel_name' not running."
        return
    fi

    PID=$(cat "$pid_file")

    if kill -0 "$PID" 2>/dev/null; then
        echo "🟢 Tunnel '$tunnel_name' running (PID $PID)"
        echo ""
        echo "Recent log:"
        tail -10 "$log_file" 2>/dev/null
    else
        echo "🔴 Tunnel '$tunnel_name' not running."
        rm -f "$pid_file"
    fi
}

start_multiple_tunnels() {
    echo "🔵 Cloudflare Tunnel - Start Multiple Tunnels"
    echo "============================================"
    echo ""
    
    # Detect all tunnels
    local tunnels=($(detect_tunnels))
    local tunnel_count=${#tunnels[@]}
    
    if [[ $tunnel_count -eq 0 ]]; then
        echo "❌ No tunnel configuration files found in $CONFIG_DIR/"
        echo "💡 Create configuration files with .yml extension (e.g., tunnel1.yml, tunnel2.yml)"
        exit 1
    fi
    
    echo "📊 Detected $tunnel_count tunnel(s):"
    for i in "${!tunnels[@]}"; do
        echo "  $((i+1)). ${tunnels[i]}"
    done
    echo ""
    
    read -p "Do you want to start the detected tunnel(s)? (y/n): " START_ALL
    
    if [[ ! "$START_ALL" =~ ^[Yy]$ ]]; then
        echo ""
        echo "❌ Operation aborted."
        echo "💡 Cloudflare does not allow temporary tunnels when permanent ones exist."
        exit 1
    fi
    
    echo ""
    
    # If only one tunnel, start it directly
    if [[ $tunnel_count -eq 1 ]]; then
        echo "🚀 Starting single tunnel: ${tunnels[0]}"
        start_tunnel "${tunnels[0]}"
    else
        # For multiple tunnels, ask confirmation for each
        for tunnel in "${tunnels[@]}"; do
            read -p "Start tunnel '$tunnel'? (y/n): " START_TUNNEL
            if [[ "$START_TUNNEL" =~ ^[Yy]$ ]]; then
                start_tunnel "$tunnel"
                echo ""
            else
                echo "⏭️  Skipping tunnel '$tunnel'"
                echo ""
            fi
        done
    fi
    
    echo ""
    echo "✅ Tunnel startup process completed."
}

### --- MAIN --- ###
ACTION="$1"
TUNNEL_NAME="$2"

case "$ACTION" in
    start)
        if [[ -z "$TUNNEL_NAME" ]]; then
            # No tunnel specified - use multiple tunnel mode
            start_multiple_tunnels
        else
            # Specific tunnel specified
            start_tunnel "$TUNNEL_NAME"
        fi
        ;;
    stop)
        if [[ -z "$TUNNEL_NAME" ]]; then
            # No tunnel specified - stop all
            stop_all_tunnels
        else
            # Specific tunnel specified
            stop_tunnel "$TUNNEL_NAME"
        fi
        ;;
    status)
        if [[ -z "$TUNNEL_NAME" ]]; then
            echo "❌ Please specify tunnel name for status check."
            echo "Usage: $0 status <tunnel_name>"
            echo "Available tunnels: $(detect_tunnels)"
            exit 1
        else
            status_tunnel "$TUNNEL_NAME"
        fi
        ;;
    list)
        echo "📋 Available tunnels:"
        tunnels=($(detect_tunnels))
        for i in "${!tunnels[@]}"; do
            echo "  $((i+1)). ${tunnels[i]}"
        done
        ;;
    *)
        echo "Usage: $0 {start|stop|status|list} [tunnel_name]"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Start all detected tunnels (with confirmation)"
        echo "  $0 start tunnel1            # Start specific tunnel"
        echo "  $0 stop                     # Stop all tunnels"
        echo "  $0 stop tunnel1             # Stop specific tunnel"
        echo "  $0 status tunnel1           # Check status of specific tunnel"
        echo "  $0 list                     # List all available tunnels"
        exit 1
        ;;
esac
