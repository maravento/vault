#!/bin/bash
# maravento.com
#
################################################################################
#
# Cloudflare Tunnel Service Manager (cftunnel)
# Unified control script for multiple Cloudflare Tunnels
#
################################################################################

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

### --- CONFIGURATION --- ###

_resolve_user_home() {
    local home=""
    # 1. getent with explicit user from SUDO_USER or USER or logname
    local try_user="${SUDO_USER:-${USER:-}}"
    [ -z "$try_user" ] && try_user=$(logname 2>/dev/null || true)
    [ -n "$try_user" ] && home=$(getent passwd "$try_user" | cut -d: -f6)
    # 2. Fall back to $HOME if set and valid
    [ -z "$home" ] && [ -n "${HOME:-}" ] && [ -d "$HOME" ] && home="$HOME"
    # 3. getent with current UID
    [ -z "$home" ] && home=$(getent passwd "$(id -u)" | cut -d: -f6)
    echo "$home"
}

USER_HOME=$(_resolve_user_home)
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "❌ Cannot determine a valid home directory (resolved: '${USER_HOME:-empty}')."
    exit 1
fi

CONFIG_DIR="$USER_HOME/.cloudflared"
CLOUDFLARED_BIN="$(command -v cloudflared)"

if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    echo "❌ cloudflared is not installed or not in PATH."
    exit 1
fi
mkdir -p "$CONFIG_DIR"

### --- FUNCTIONS --- ###

detect_tunnels() {
    local tunnels=()
    if [[ -d "$CONFIG_DIR" ]]; then
        local old_nullglob
        old_nullglob=$(shopt -p nullglob)
        shopt -s nullglob
        for file in "$CONFIG_DIR"/*.yml; do
            [[ -f "$file" ]] && tunnels+=("$(basename "$file" .yml)")
        done
        eval "$old_nullglob"
    fi
    echo "${tunnels[@]}"
}

get_tunnel_id() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        grep "^tunnel:" "$config_file" | head -1 | awk '{print $2}'
    fi
}

_pid_is_valid() {
    local pid="$1"
    [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]]
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
        local old_pid
        old_pid=$(cat "$pid_file")
        if _pid_is_valid "$old_pid" && kill -0 "$old_pid" 2>/dev/null; then
            echo "⚠️ Tunnel '$tunnel_name' already running (PID $old_pid)"
            local restart
            read -r -p "Stop existing tunnel and start new one? (y/n): " restart
            if [[ ! "$restart" =~ ^[Yy]$ ]]; then
                return 0
            fi
            kill "$old_pid" 2>/dev/null
            sleep 1
            rm -f "$pid_file"
        else
            rm -f "$pid_file"
        fi
    fi

    # Extract tunnel ID from YAML
    local tunnel_id
    tunnel_id=$(get_tunnel_id "$config_file")
    if [[ -z "$tunnel_id" ]]; then
        echo "❌ No 'tunnel:' entry found in config file."
        return 1
    fi

    echo "🚀 Running: cloudflared tunnel run --config $config_file $tunnel_id"
    nohup "$CLOUDFLARED_BIN" --config "$config_file" tunnel run "$tunnel_id" >> "$log_file" 2>&1 &

    local new_pid=$!
    echo "$new_pid" > "$pid_file"

    sleep 2
    if _pid_is_valid "$new_pid" && kill -0 "$new_pid" 2>/dev/null; then
        echo "🟢 Tunnel '$tunnel_name' started (PID $new_pid)"
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

    local pid
    pid=$(cat "$pid_file")
    if ! _pid_is_valid "$pid"; then
        echo "⚠️ Invalid PID in $pid_file ('$pid'). Removing stale file."
        rm -f "$pid_file"
        return
    fi

    echo "🔴 Stopping tunnel '$tunnel_name' (PID $pid)..."
    kill "$pid" 2>/dev/null
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid"
    fi

    rm -f "$pid_file"
    echo "✔️ Tunnel '$tunnel_name' stopped."
}

stop_all_tunnels() {
    echo "🔴 Stopping all Cloudflare tunnels..."

    local old_nullglob
    old_nullglob=$(shopt -p nullglob)
    shopt -s nullglob
    for pid_file in "$CONFIG_DIR"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local tunnel_name pid
            tunnel_name=$(basename "$pid_file" .pid)
            pid=$(cat "$pid_file")

            if ! _pid_is_valid "$pid"; then
                echo "⚠️ Invalid PID in $pid_file ('$pid'). Removing stale file."
                rm -f "$pid_file"
                continue
            fi

            if kill -0 "$pid" 2>/dev/null; then
                echo "Stopping tunnel '$tunnel_name' (PID $pid)..."
                kill "$pid" 2>/dev/null
                sleep 1
                kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
                rm -f "$pid_file"
                echo "✔️ Tunnel '$tunnel_name' stopped."
            else
                rm -f "$pid_file"
            fi
        fi
    done
    eval "$old_nullglob"

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

    local pid
    pid=$(cat "$pid_file")
    if ! _pid_is_valid "$pid"; then
        echo "⚠️ Invalid PID in $pid_file. Removing stale file."
        rm -f "$pid_file"
        return
    fi

    if kill -0 "$pid" 2>/dev/null; then
        echo "🟢 Tunnel '$tunnel_name' running (PID $pid)"
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

    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | tr ' ' '\n' | grep -v '^$')
    local tunnel_count=${#tunnels[@]}

    if [[ $tunnel_count -eq 0 ]]; then
        echo "❌ No tunnel configuration files found in $CONFIG_DIR/"
        echo "💡 Create configuration files with .yml extension"
        return 1
    fi

    echo "📊 Detected $tunnel_count tunnel(s):"
    for i in "${!tunnels[@]}"; do
        echo "  $((i+1)). ${tunnels[i]}"
    done
    echo ""

    local start_all
    read -r -p "Do you want to start the detected tunnel(s)? (y/n): " start_all

    if [[ ! "$start_all" =~ ^[Yy]$ ]]; then
        echo ""
        echo "❌ Operation aborted."
        return 1
    fi

    echo ""

    if [[ $tunnel_count -eq 1 ]]; then
        echo "🚀 Starting single tunnel: ${tunnels[0]}"
        start_tunnel "${tunnels[0]}"
    else
        local start_one
        for tunnel in "${tunnels[@]}"; do
            read -r -p "Start tunnel '$tunnel'? (y/n): " start_one
            if [[ "$start_one" =~ ^[Yy]$ ]]; then
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
            start_multiple_tunnels
        else
            start_tunnel "$TUNNEL_NAME"
        fi
        ;;
    stop)
        if [[ -z "$TUNNEL_NAME" ]]; then
            stop_all_tunnels
        else
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
        local_tunnels=()
        mapfile -t local_tunnels < <(detect_tunnels | tr ' ' '\n' | grep -v '^$')
        for i in "${!local_tunnels[@]}"; do
            echo "  $((i+1)). ${local_tunnels[i]}"
        done
        ;;
    *)
        echo "Usage: $0 {start|stop|status|list} [tunnel_name]"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Start all detected tunnels"
        echo "  $0 start tunnel1            # Start specific tunnel"
        echo "  $0 stop                     # Stop all tunnels"
        echo "  $0 stop tunnel1             # Stop specific tunnel"
        echo "  $0 status tunnel1           # Check status of specific tunnel"
        echo "  $0 list                     # List all available tunnels"
        exit 1
        ;;
esac
