#!/bin/bash
# maravento.com
#
################################################################################
#
# Cloudflare Tunnel Service Manager (cftunnel)
# Unified control script for multiple Cloudflare Tunnels
#
# Usage: cftunnel.sh {create|start|startall|stop|status|delete}
#
#   create     Create a new tunnel interactively (login, name, hostname, service)
#   start      Start tunnels interactively (asks per tunnel)
#   startall   Start all configured tunnels without prompts + enable cron autostart
#   stop       Stop all running tunnels + remove cron autostart entry
#   status     List active/inactive tunnels
#   delete     Stop and permanently delete a tunnel (Cloudflare side + local config)
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
# PREREQUISITES:
# ==============
# 1. Install cloudflared (Debian/Ubuntu):
#    sudo mkdir -p --mode=0755 /usr/share/keyrings
#    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
#    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list
#    sudo apt-get update && sudo apt-get install cloudflared
#
# 2. Authenticate once (downloads cert.pem to ~/.cloudflared/):
#    cloudflared tunnel login
#
# API TOKEN (optional, only needed to auto-remove DNS records on delete):
# =========================================================================
# cloudflared has no CLI command to delete a DNS route, so removing the
# record left behind by 'cloudflared tunnel route dns' requires a scoped
# Cloudflare API Token instead of cert.pem:
#   1. dash.cloudflare.com -> profile icon -> My Profile -> API Tokens
#   2. Create Token -> Create Custom Token
#   3. Permissions: Zone -> DNS -> Edit
#   4. Zone Resources: Include -> Specific zone -> your domain only
#   5. (Recommended) set a TTL / client IP filter
#   6. Create Token and copy it -> it is shown only once
#   7. Paste it into the 'token_cloudflare' variable below (USER CONFIGURATION)
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
# RECOMMENDATION:
# ===============
# Use permanent tunnels for production services and temporary tunnels
# only for quick testing and development purposes.
#
# Always protect every tunnel hostname (HTTP or 'tcp://' ingress alike)
# with a Cloudflare Zero Trust Access Application + policy. Without it,
# anyone who discovers the hostname can reach the exposed service — the
# tunnel alone does not authenticate connections.
#
# Zero Trust -> Access Control -> Applications -> Create New Application
#
# For more information:
# https://developers.cloudflare.com/cloudflare-one/connections/connect-apps
################################################################################

set -uo pipefail

### --- USER CONFIGURATION --- ###
# Cloudflare API Token (Zone:DNS:Edit permission), only needed for 'delete'
# to auto-remove the DNS record. Leave empty to skip automatic DNS deletion.
token_cloudflare=""

# PATH for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "[ERROR] This script should not be run as root."
    exit 1
fi

# DEPENDENCIES
for dep in cloudflared curl gawk cron procps; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "[ERROR] Required dependency '$dep' is not installed." >&2
        exit 1
    fi
done

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
mkdir -p "$CONFIG_DIR"

### --- VALIDATION --- ###
# VALIDATION -- one variable per thing validated; use directly with =~
_UH_IPV4='^(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9][0-9]|[0-9])$'
_UH_UINT='^(0|[1-9][0-9]*)$'
_UH_FQDN='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'

is_valid_port() {
    [[ "$1" =~ $_UH_UINT ]] && (( $1 >= 1 && $1 <= 65535 ))
}

### --- FUNCTIONS --- ###

preflight_check() {
    local max_retries=10
    local interval=5
    local log_file="$CONFIG_DIR/preflight.log"
    local attempt=1
    local ts reason

    while (( attempt <= max_retries )); do
        ts=$(date '+%Y-%m-%d %H:%M:%S')
        reason=""

        if ! getent hosts cloudflare.com >/dev/null 2>&1; then
            reason="DNS resolution failed (cloudflare.com)"
        elif ! curl -sf --max-time 5 https://www.cloudflare.com/cdn-cgi/trace >/dev/null 2>&1; then
            reason="Cloudflare edge unreachable"
        elif ! curl -sf --max-time 5 https://api.cloudflare.com/cdn-cgi/trace >/dev/null 2>&1; then
            reason="Cloudflare API unreachable"
        else
            echo "[$ts] [OK] Preflight passed on attempt $attempt/$max_retries" | tee -a "$log_file"
            return 0
        fi

        echo "[$ts] [WARN] Preflight attempt $attempt/$max_retries failed: $reason" | tee -a "$log_file"
        sleep "$interval"
        ((attempt++))
    done

    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [ERROR] Preflight failed after $max_retries attempts. Aborting." | tee -a "$log_file"
    return 1
}

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
    printf '%s\n' "${tunnels[@]}"
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

# Deletes the DNS record for $1 (hostname) via the Cloudflare API.
# Requires the 'token_cloudflare' variable (Zone:DNS:Edit) set above. Never
# aborts the caller: missing token, missing zone, or missing record are all
# reported and skipped.
delete_dns_record() {
    local hostname="$1"

    if [[ -z "$hostname" ]]; then
        echo "[WARN] No hostname found in config; skipping DNS record deletion."
        return 0
    fi

    if [[ -z "$token_cloudflare" ]]; then
        echo "[WARN] 'token_cloudflare' is not set; skipping automatic DNS deletion."
        echo "[NOTE] Remove the DNS record for '$hostname' manually from the Cloudflare dashboard."
        return 0
    fi

    local api_token="$token_cloudflare"
    local zones_response
    zones_response=$(curl -sf -X GET "https://api.cloudflare.com/client/v4/zones?per_page=50" \
        -H "Authorization: Bearer $api_token" -H "Content-Type: application/json") || {
        echo "[WARN] Could not reach Cloudflare API to list zones; skipping automatic DNS deletion."
        return 0
    }

    # pick the zone whose name is the longest suffix match of $hostname
    local zone_id=""
    local zone_name=""
    local candidate
    while IFS=$'\t' read -r candidate cid; do
        [[ -z "$candidate" ]] && continue
        if [[ "$hostname" == "$candidate" || "$hostname" == *".$candidate" ]]; then
            if [[ ${#candidate} -gt ${#zone_name} ]]; then
                zone_name="$candidate"
                zone_id="$cid"
            fi
        fi
    done < <(echo "$zones_response" | gawk 'match($0,/"id":"[a-f0-9]+"/){id=substr($0,RSTART+6,RLENGTH-7)} match($0,/"name":"[^"]+"/){name=substr($0,RSTART+8,RLENGTH-9); if(id!="") print name"\t"id; id=""}' RS='}' ORS='\n')

    if [[ -z "$zone_id" ]]; then
        echo "[WARN] No matching Cloudflare zone found for '$hostname'; skipping automatic DNS deletion."
        return 0
    fi

    local records_response
    records_response=$(curl -sf -X GET "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?name=${hostname}" \
        -H "Authorization: Bearer $api_token" -H "Content-Type: application/json") || {
        echo "[WARN] Could not query DNS records for '$hostname'; skipping automatic DNS deletion."
        return 0
    }

    local record_id
    record_id=$(echo "$records_response" | gawk 'match($0,/"id":"[a-f0-9]+"/){print substr($0,RSTART+6,RLENGTH-7); exit}')

    if [[ -z "$record_id" ]]; then
        echo "[OK] No DNS record found for '$hostname' (already removed or never created)."
        return 0
    fi

    echo "Deleting DNS record for '$hostname' (zone: $zone_name)..."
    if curl -sf -X DELETE "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}" \
        -H "Authorization: Bearer $api_token" -H "Content-Type: application/json" >/dev/null; then
        echo "[OK] DNS record for '$hostname' deleted."
    else
        echo "[WARN] Failed to delete DNS record for '$hostname'; remove it manually from the dashboard."
    fi
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
            if kill -0 "$old_pid" 2>/dev/null; then
                kill -9 "$old_pid" 2>/dev/null
                sleep 1
            fi
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

    echo "Running: cloudflared --config $config_file tunnel run $tunnel_id"
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
    mapfile -t tunnels < <(detect_tunnels | grep -v '^$')

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

create_tunnel() {
    echo "Cloudflare Tunnel - Create New Tunnel"
    echo "======================================"
    echo ""

    if ! preflight_check; then
        return 1
    fi

    if [[ ! -f "$CONFIG_DIR/cert.pem" ]]; then
        echo "No Cloudflare certificate found. Login is required first."
        local do_login
        read -r -p "Run 'cloudflared tunnel login' now? (y/n): " do_login
        if [[ "$do_login" =~ ^[Yy]$ ]]; then
            "$CLOUDFLARED_BIN" tunnel login
            if [[ ! -f "$CONFIG_DIR/cert.pem" ]]; then
                echo "[ERROR] Login did not complete (cert.pem not found)."
                return 1
            fi
        else
            echo "[ERROR] Cannot create a tunnel without logging in first."
            return 1
        fi
    fi

    local tunnel_name
    read -r -p "Tunnel name: " tunnel_name
    if [[ -z "$tunnel_name" ]]; then
        echo "[ERROR] Tunnel name cannot be empty."
        return 1
    fi

    local config_file="$CONFIG_DIR/${tunnel_name}.yml"
    if [[ -f "$config_file" ]]; then
        echo "[ERROR] Config file already exists: $config_file"
        return 1
    fi

    echo "Running: cloudflared tunnel create $tunnel_name"
    local create_output
    create_output=$("$CLOUDFLARED_BIN" tunnel create "$tunnel_name" 2>&1)
    echo "$create_output"

    local tunnel_id
    tunnel_id=$(echo "$create_output" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)
    if [[ -z "$tunnel_id" ]]; then
        tunnel_id=$("$CLOUDFLARED_BIN" tunnel list 2>/dev/null | awk -v name="$tunnel_name" '$2==name {print $1}' | head -1)
    fi
    if [[ -z "$tunnel_id" ]]; then
        echo "[ERROR] Could not determine tunnel ID. Aborting config creation."
        return 1
    fi

    local credentials_file="$CONFIG_DIR/${tunnel_id}.json"

    local hostname service no_tls_verify service_type svc_ip svc_port domain
    while true; do
        read -r -p "Public hostname (e.g. sub.domain.com): " hostname
        if [[ -z "$hostname" ]]; then
            echo "[ERROR] Hostname is required. Aborting."
            return 1
        fi
        if [[ ! "$hostname" =~ $_UH_FQDN ]]; then
            echo "[WARNING] Invalid hostname format: '$hostname'"
            continue
        fi
        domain="${hostname#*.}"
        if ! getent hosts "$domain" >/dev/null 2>&1; then
            echo "[WARNING] Invalid domain: '$domain'"
            continue
        fi
        break
    done

    read -r -p "Service type (http/https/tcp): " service_type
    case "$service_type" in
        http|https|tcp)
            read -r -p "Server IP: " svc_ip
            if [[ ! "$svc_ip" =~ $_UH_IPV4 ]]; then
                echo "[ERROR] Invalid IP: '$svc_ip'"
                return 1
            fi
            read -r -p "Port: " svc_port
            if ! is_valid_port "$svc_port"; then
                echo "[ERROR] Invalid port: '$svc_port'"
                return 1
            fi
            service="${service_type}://${svc_ip}:${svc_port}"
            ;;
        *)
            echo "[ERROR] Invalid service type: $service_type"
            return 1
            ;;
    esac

    no_tls_verify=""
    if [[ "$service" == https://* ]]; then
        local tls_answer
        read -r -p "Origin uses a self-signed certificate? [y/N]: " tls_answer
        if [[ "$tls_answer" =~ ^[Yy]$ ]]; then
            no_tls_verify="yes"
        fi
    fi

    {
        echo "tunnel: $tunnel_id"
        echo "credentials-file: $credentials_file"
        echo ""
        echo "ingress:"
        echo "  - hostname: $hostname"
        echo "    service: $service"
        if [[ "$no_tls_verify" == "yes" ]]; then
            echo "    originRequest:"
            echo "      noTLSVerify: true"
        fi
        echo "  - service: http_status:404"
    } > "$config_file"

    echo "[OK] Config file created: $config_file"

    local do_route
    read -r -p "Route DNS '$hostname' to this tunnel now? (y/n): " do_route
    if [[ "$do_route" =~ ^[Yy]$ ]]; then
        "$CLOUDFLARED_BIN" tunnel route dns "$tunnel_name" "$hostname"
    fi

    local do_start
    read -r -p "Start tunnel '$tunnel_name' now? (y/n): " do_start
    if [[ "$do_start" =~ ^[Yy]$ ]]; then
        start_tunnel "$tunnel_name"
    fi

    echo "[OK] Tunnel '$tunnel_name' setup complete."
}

start_multiple_tunnels() {
    echo "Cloudflare Tunnel - Start Multiple Tunnels"
    echo "============================================"
    echo ""

    if ! preflight_check; then
        return 1
    fi

    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | grep -v '^$')
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
    if ! preflight_check; then
        return 1
    fi
    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | grep -v '^$')

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
    mapfile -t tunnels < <(detect_tunnels | grep -v '^$')

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

delete_tunnel() {
    echo "Cloudflare Tunnel - Delete Tunnel"
    echo "=================================="
    echo ""

    local tunnels=()
    mapfile -t tunnels < <(detect_tunnels | grep -v '^$')

    if [[ ${#tunnels[@]} -eq 0 ]]; then
        echo "[ERROR] No tunnel configuration files found in $CONFIG_DIR/"
        return 1
    fi

    echo "Detected tunnel(s):"
    for i in "${!tunnels[@]}"; do
        echo "  $((i+1)). ${tunnels[i]}"
    done
    echo ""

    local tunnel_name
    read -r -p "Tunnel name or number to delete: " tunnel_name
    if [[ -z "$tunnel_name" ]]; then
        echo "[ERROR] Tunnel name cannot be empty."
        return 1
    fi

    if [[ "$tunnel_name" =~ ^[0-9]+$ ]]; then
        local index=$((tunnel_name - 1))
        if [[ $index -lt 0 || $index -ge ${#tunnels[@]} ]]; then
            echo "[ERROR] Invalid selection: $tunnel_name"
            return 1
        fi
        tunnel_name="${tunnels[$index]}"
    fi

    local config_file="$CONFIG_DIR/${tunnel_name}.yml"
    if [[ ! -f "$config_file" ]]; then
        echo "[ERROR] Config file does not exist: $config_file"
        return 1
    fi

    local confirm
    echo "[WARNING] This will stop and permanently delete tunnel '$tunnel_name' (Cloudflare side + local config)."
    read -r -p "Continue? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        return 0
    fi

    local tunnel_id hostname
    tunnel_id=$(get_tunnel_id "$config_file")
    hostname=$(grep "hostname:" "$config_file" | head -1 | awk '{print $3}')

    stop_tunnel "$tunnel_name"

    echo "Running: cloudflared tunnel delete $tunnel_name"
    if ! "$CLOUDFLARED_BIN" tunnel delete "$tunnel_name" 2>&1; then
        echo "[WARN] 'cloudflared tunnel delete' failed. Retrying with --force..."
        "$CLOUDFLARED_BIN" tunnel delete -f "$tunnel_name" 2>&1
    fi

    delete_dns_record "$hostname"

    rm -f "$config_file" "$CONFIG_DIR/${tunnel_name}.pid" "$CONFIG_DIR/${tunnel_name}.log"
    [[ -n "$tunnel_id" ]] && rm -f "$CONFIG_DIR/${tunnel_id}.json"

    echo "[OK] Tunnel '$tunnel_name' deleted."
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
ACTION="${1:-}"

if [[ -z "$ACTION" ]]; then
    echo "Cloudflare Tunnel Service Manager (cftunnel)"
    echo "============================================="
    echo "  1. create    - Create a new tunnel interactively"
    echo "  2. start     - Start tunnels interactively"
    echo "  3. startall  - Start all tunnels and enable autostart"
    echo "  4. stop      - Stop all tunnels and remove autostart"
    echo "  5. status    - Show status of all tunnels"
    echo "  6. delete    - Delete a tunnel"
    echo "  0. exit"
    echo ""
    read -r -p "Select an option: " menu_choice
    case "$menu_choice" in
        1) ACTION="create" ;;
        2) ACTION="start" ;;
        3) ACTION="startall" ;;
        4) ACTION="stop" ;;
        5) ACTION="status" ;;
        6) ACTION="delete" ;;
        0) exit 0 ;;
        *) echo "[ERROR] Invalid option: $menu_choice"; exit 1 ;;
    esac
fi

case "$ACTION" in
    create)
        create_tunnel
        ;;
    start)
        # prevent overlapping runs
        SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
        exec 200>"$SCRIPT_LOCK"
        if ! flock -n 200; then
            echo "[ERROR] Script $(basename "$0") is already running"
            exit 1
        fi
        start_multiple_tunnels
        ;;
    startall)
        # prevent overlapping runs
        SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
        exec 200>"$SCRIPT_LOCK"
        if ! flock -n 200; then
            echo "[ERROR] Script $(basename "$0") is already running"
            exit 1
        fi
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
    delete)
        delete_tunnel
        ;;
    *)
        echo "Usage: $0 {create|start|startall|stop|status|delete}"
        echo ""
        echo "Examples:"
        echo "  $0 create                   # Create a new tunnel interactively"
        echo "  $0 start                    # Start tunnels interactively"
        echo "  $0 startall                 # Start all tunnels and enable autostart"
        echo "  $0 stop                     # Stop all tunnels and remove autostart"
        echo "  $0 status                   # Show status of all tunnels"
        echo "  $0 delete                   # Delete a tunnel (stop + remove from Cloudflare + local config)"
        exit 1
        ;;
esac
