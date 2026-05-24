#!/bin/bash
# maravento.com
#
################################################################################
#
# Cloudflare Tunnel Service Manager (cftunnel)
# Unified control script for multiple Cloudflare Tunnels
#
# Usage: cftunnel.sh {start|startall|stop|status}
#
#   start      Start tunnels interactively (asks per tunnel)
#   startall   Start all configured tunnels without prompts + enable cron autostart
#   stop       Stop all running tunnels + remove cron autostart entry
#   status     List active/inactive tunnels
################################################################################

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "[ERROR] This script should not be run as root."
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
    echo "[ERROR] Cannot determine a valid home directory (resolved: '${USER_HOME:-empty}')."
    exit 1
fi

CONFIG_DIR="$USER_HOME/.cloudflared"
CLOUDFLARED_BIN="$(command -v cloudflared)"

if [[ ! -x "$CLOUDFLARED_BIN" ]]; then
    echo "[ERROR] cloudflared is not installed or not in PATH."
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

    echo "Starting tunnel: $tunnel_name"
    echo "Config: $config_file"

    if [[ ! -f "$config_file" ]]; then
        echo "[ERROR] Config file does not exist: $config_file"
        return 1
    fi

    # Check if already running
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid=$(cat "$pid_file")
        if _pid_is_valid "$old_pid" && kill -0 "$old_pid" 2>/dev/null; then
            echo "[WARN] Tunnel '$tunnel_name' already running (PID $old_pid)"
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
        echo "[ERROR] No 'tunnel:' entry found in config file."
        return 1
    fi

    echo "Running: cloudflared tunnel run --config $config_file $tunnel_id"
    nohup "$CLOUDFLARED_BIN" --config "$config_file" tunnel run "$tunnel_id" >> "$log_file" 2>&1 &

    local new_pid=$!
    echo "$new_pid" > "$pid_file"

    local retries=10
    while [[ $retries -gt 0 ]]; do
        sleep 1
        if _pid_is_valid "$new_pid" && kill -0 "$new_pid" 2>/dev/null; then
            echo "[UP] Tunnel '$tunnel_name' started (PID $new_pid)"
            echo "Log file: $log_file"
            return 0
        fi
        ((retries--))
    done

    echo "[ERROR] Failed to start tunnel '$tunnel_name'"
    tail -20 "$log_file"
    rm -f "$pid_file"
    return 1
}

stop_tunnel() {
    local tunnel_name="$1"
    local pid_file="$CONFIG_DIR/${tunnel_name}.pid"

    if [[ ! -f "$pid_file" ]]; then
        echo "[DOWN] Tunnel '$tunnel_name' not running."
        return
    fi

    local pid
    pid=$(cat "$pid_file")
    if ! _pid_is_valid "$pid"; then
        echo "[WARN] Invalid PID in $pid_file ('$pid'). Removing stale file."
        rm -f "$pid_file"
        return
    fi

    echo "Stopping tunnel '$tunnel_name' (PID $pid)..."
    kill "$pid" 2>/dev/null
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid"
    fi

    rm -f "$pid_file"
    echo "[OK] Tunnel '$tunnel_name' stopped."
}

stop_all_tunnels() {
    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | tr ' ' '\n' | grep -v '^$')

    if [[ ${#tunnels[@]} -eq 0 ]]; then
        echo "[ERROR] No tunnel configuration files found in $CONFIG_DIR/"
        return 1
    fi

    local stopped=0 already=0
    for tunnel in "${tunnels[@]}"; do
        local pid_file="$CONFIG_DIR/${tunnel}.pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            if ! _pid_is_valid "$pid"; then
                rm -f "$pid_file"
                ((already++))
                continue
            fi
            if kill -0 "$pid" 2>/dev/null; then
                echo "Stopping tunnel '$tunnel' (PID $pid)..."
                kill "$pid" 2>/dev/null
                sleep 1
                kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
                rm -f "$pid_file"
                echo "[OK] Tunnel '$tunnel' stopped."
                ((stopped++))
            else
                rm -f "$pid_file"
                ((already++))
            fi
        else
            ((already++))
        fi
    done

    if [[ $stopped -eq 0 ]]; then
        echo "All tunnels were already stopped."
    else
        echo "[OK] All tunnels stopped."
    fi
}

status_tunnel() {
    local tunnel_name="$1"
    local pid_file="$CONFIG_DIR/${tunnel_name}.pid"
    local log_file="$CONFIG_DIR/${tunnel_name}.log"

    if [[ ! -f "$pid_file" ]]; then
        echo "[DOWN] Tunnel '$tunnel_name' not running."
        return
    fi

    local pid
    pid=$(cat "$pid_file")
    if ! _pid_is_valid "$pid"; then
        echo "[WARN] Invalid PID in $pid_file. Removing stale file."
        rm -f "$pid_file"
        return
    fi

    if kill -0 "$pid" 2>/dev/null; then
        echo "[UP] Tunnel '$tunnel_name' running (PID $pid)"
        echo ""
        echo "Recent log:"
        tail -10 "$log_file" 2>/dev/null
    else
        echo "[DOWN] Tunnel '$tunnel_name' not running."
        rm -f "$pid_file"
    fi
}

start_multiple_tunnels() {
    echo "Cloudflare Tunnel - Start Multiple Tunnels"
    echo "============================================"
    echo ""

    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | tr ' ' '\n' | grep -v '^$')
    local tunnel_count=${#tunnels[@]}

    if [[ $tunnel_count -eq 0 ]]; then
        echo "[ERROR] No tunnel configuration files found in $CONFIG_DIR/"
        echo "Tip: Create configuration files with .yml extension"
        return 1
    fi

    echo "Detected $tunnel_count tunnel(s):"
    for i in "${!tunnels[@]}"; do
        echo "  $((i+1)). ${tunnels[i]}"
    done
    echo ""

    local answer
    for tunnel in "${tunnels[@]}"; do
        read -r -p "Start tunnel '$tunnel'? (y/n): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            start_tunnel "$tunnel"
            echo ""
        else
            echo "Skipping tunnel '$tunnel'"
            echo ""
        fi
    done

    echo "[OK] Tunnel startup process completed."
}

startall_tunnels() {
    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | tr ' ' '\n' | grep -v '^$')

    if [[ ${#tunnels[@]} -eq 0 ]]; then
        echo "[ERROR] No tunnel configuration files found in $CONFIG_DIR/"
        return 1
    fi

    for tunnel in "${tunnels[@]}"; do
        local pid_file="$CONFIG_DIR/${tunnel}.pid"
        if [[ -f "$pid_file" ]]; then
            local old_pid
            old_pid=$(cat "$pid_file")
            if _pid_is_valid "$old_pid" && kill -0 "$old_pid" 2>/dev/null; then
                echo "[WARN] Tunnel '$tunnel' already running (PID $old_pid), skipping."
                continue
            else
                rm -f "$pid_file"
            fi
        fi
        start_tunnel "$tunnel"
    done
}

status_all_tunnels() {
    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | tr ' ' '\n' | grep -v '^$')

    if [[ ${#tunnels[@]} -eq 0 ]]; then
        echo "[ERROR] No tunnel configuration files found in $CONFIG_DIR/"
        return 1
    fi

    for tunnel in "${tunnels[@]}"; do
        local pid_file="$CONFIG_DIR/${tunnel}.pid"
        if [[ -f "$pid_file" ]]; then
            local pid
            pid=$(cat "$pid_file")
            if _pid_is_valid "$pid" && kill -0 "$pid" 2>/dev/null; then
                echo "[UP] $tunnel (PID $pid)"
            else
                rm -f "$pid_file"
                echo "[DOWN] $tunnel"
            fi
        else
            echo "[DOWN] $tunnel"
        fi
    done
}

_cron_remove() {
    local script_path="$1"
    if crontab -l 2>/dev/null | grep -qF "$script_path"; then
        crontab -l 2>/dev/null | grep -vF "$script_path" | crontab -
        pkill -HUP crond 2>/dev/null || pkill -HUP cron 2>/dev/null || true
        echo "[OK] Autostart entry removed from crontab."
    fi
}

### --- MAIN --- ###
ACTION="$1"
TUNNEL_NAME="$2"

case "$ACTION" in
    start)
        start_multiple_tunnels
        ;;
    startall)
        script_path=$(realpath "$0")
        startall_tunnels
        if ! crontab -l 2>/dev/null | grep -qF "$script_path"; then
            (crontab -l 2>/dev/null; echo "@reboot $script_path startall") | crontab -
            pkill -HUP crond 2>/dev/null || pkill -HUP cron 2>/dev/null || true
            echo "[OK] Autostart enabled in crontab."
            echo "Entry: @reboot $script_path startall"
        else
            echo "[WARN] Autostart entry already exists in crontab."
        fi
        ;;
    stop)
        stop_all_tunnels
        _cron_remove "$(realpath "$0")"
        ;;
    status)
        status_all_tunnels
        ;;
    *)
        echo "Usage: $0 {start|startall|stop|status}"
        echo ""
        echo "Examples:"
        echo "  $0 start                    # Start tunnels interactively"
        echo "  $0 startall                 # Start all tunnels and enable autostart"
        echo "  $0 stop                     # Stop all tunnels and remove autostart"
        echo "  $0 status                   # Show status of all tunnels"
        exit 1
        ;;
esac
