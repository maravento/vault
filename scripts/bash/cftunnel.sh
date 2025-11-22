#!/bin/bash
#
# Cloudflare Tunnel Service Manager (cftunnel)
# Unified control script for both permanent and temporary Cloudflare Tunnels
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
# 3. Create config.yml in ~/.cloudflared/config.yml with tunnel configuration
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
#   ├── config.yml               # Tunnel configuration file
#   ├── TUNNEL-ID.json           # Tunnel credentials
#   ├── tunnel.pid               # PID file (created by this script)
#   └── tunnel.log               # Log file (created by this script)
#
# RECOMMENDATION:
# ===============
# Use permanent tunnels for production services and temporary tunnels
# only for quick testing and development purposes.
#
# For more information:
# https://developers.cloudflare.com/cloudflare-one/connections/connect-apps

### --- CONFIGURATION --- ###
USER_HOME="$(getent passwd "$USER" | cut -d: -f6)"
CONFIG_DIR="$USER_HOME/.cloudflared"
PID_FILE="$CONFIG_DIR/tunnel.pid"
LOG_FILE="$CONFIG_DIR/tunnel.log"
CLOUDFLARED_BIN="$(command -v cloudflared)"

### --- SAFETY CHECKS --- ###
if [[ $EUID -eq 0 ]]; then
    echo "❌ This script must NOT be run as root."
    exit 1
fi
if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    echo "❌ cloudflared is not installed or not in PATH."
    exit 1
fi
mkdir -p "$CONFIG_DIR"

### --- FUNCTIONS --- ###
start_tunnel() {
    echo "🔵 Cloudflare Tunnel - Start"
    echo "============================"
    echo ""
    
    if [[ ! -f "$CONFIG_DIR/config.yml" ]]; then
        echo "❌ Configuration file not found: $CONFIG_DIR/config.yml"
        echo ""
        read -p "Do you want to establish a temporary connection? (y/n): " USE_TEMP
        
        if [[ "$USE_TEMP" =~ ^[Yy]$ ]]; then
            read -p "Local Port to Expose: " PORT
            
            if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
                echo "❌ Port must be a number."
                exit 1
            fi
        else
            echo "❌ Operation aborted."
            exit 1
        fi
    else
        TUNNEL_NAME=$(grep -E '^(tunnel:|tunnel-name:)' "$CONFIG_DIR/config.yml" | head -1 | awk '{print $2}')
        if [[ -z "$TUNNEL_NAME" ]]; then
            echo "❌ No tunnel name found in config.yml"
            exit 1
        fi
        
        echo "✅ Configuration file found: $CONFIG_DIR/config.yml"
        echo "🔍 Tunnel name: $TUNNEL_NAME"
        echo ""
        read -p "Do you want to connect to '$TUNNEL_NAME'? (y/n): " USE_NAMED
        
        if [[ "$USE_NAMED" =~ ^[Yy]$ ]]; then
            USE_NAMED=true
        else
            echo "❌ Operation aborted."
            exit 1
        fi
    fi
    
    if [[ -f "$PID_FILE" ]]; then
        OLD_PID=$(cat "$PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "⚠️ Tunnel already running (PID $OLD_PID)"
            echo ""
            read -p "Stop existing tunnel and start new one? (y/n): " RESTART
            if [[ ! "$RESTART" =~ ^[Yy]$ ]]; then
                return
            fi
            kill "$OLD_PID" 2>/dev/null
            sleep 1
        fi
        rm -f "$PID_FILE"
    fi
    
    echo ""
    
    if [[ "$USE_NAMED" == true ]]; then
        echo "🔵 Starting named tunnel '$TUNNEL_NAME' using config.yml..."
        nohup "$CLOUDFLARED_BIN" tunnel run "$TUNNEL_NAME" >> "$LOG_FILE" 2>&1 &
    else
        echo "🔵 Starting temporary tunnel for http://127.0.0.1:$PORT..."
        nohup "$CLOUDFLARED_BIN" tunnel --url "http://127.0.0.1:$PORT" >> "$LOG_FILE" 2>&1 &
    fi
    
    NEW_PID=$!
    echo "$NEW_PID" > "$PID_FILE"
    
    sleep 3
    
    if kill -0 "$NEW_PID" 2>/dev/null; then
        echo "🟢 Tunnel started (PID $NEW_PID)"
        echo "📋 Log file: $LOG_FILE"
        echo ""
        
        if [[ "$USE_NAMED" == true ]]; then
            echo "🌐 Using subdomain(s) defined in config.yml"
            echo "📖 Check Cloudflare DNS for your configured subdomains"
            sleep 2
            echo ""
            echo "Recent log output:"
            tail -10 "$LOG_FILE"
        else
            sleep 2
            URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_FILE" | tail -1)
            if [[ -n "$URL" ]]; then
                echo "🌐 Tunnel URL: $URL"
            else
                echo "Waiting for URL to be generated..."
                sleep 3
                tail -5 "$LOG_FILE"
            fi
        fi
    else
        echo "❌ Failed to start tunnel. Check log: $LOG_FILE"
        tail -20 "$LOG_FILE"
        rm -f "$PID_FILE"
    fi
}

stop_tunnel() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo "⚠️ No tunnel process found."
        return
    fi
    
    PID=$(cat "$PID_FILE")
    
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "⚠️ Process not running. Cleaning..."
        rm -f "$PID_FILE"
        return
    fi
    
    echo "🔴 Stopping tunnel (PID $PID)..."
    kill "$PID"
    sleep 1
    
    if kill -0 "$PID" 2>/dev/null; then
        kill -9 "$PID"
    fi
    
    rm -f "$PID_FILE"
    echo "✔️ Tunnel stopped."
}

status_tunnel() {
    if [[ -f "$PID_FILE" ]]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            echo "🟢 Tunnel running (PID $PID)"
            echo ""
            echo "Recent log:"
            tail -10 "$LOG_FILE" 2>/dev/null
        else
            echo "🔴 No tunnel running"
        fi
    else
        echo "🔴 No tunnel running"
    fi
}

### --- MAIN --- ###
ACTION="$1"
case "$ACTION" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        status_tunnel
        ;;
    *)
        echo "Usage: $0 {start|stop|status}"
        exit 1
        ;;
esac
