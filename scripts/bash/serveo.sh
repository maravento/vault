#!/bin/bash
# maravento.com
#
################################################################################
#
# Serveo tunnel start | stop | status
# https://serveo.net/

# Before using this script:
# - Register on the tunnel service website with your email address.
# - The server fingerprint will be automatically managed by this script.
#
################################################################################

set -uo pipefail

## root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# LOCAL USER detection
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
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

echo "Serveo Tunnel Starting. Wait..."

# check dependencies
if ! command -v ssh >/dev/null 2>&1; then
    echo "SSH is not installed"
    echo "run: sudo apt install openssh-server"
    exit 1
fi

if ! nc -z -w 5 serveo.net 22; then
    echo "Serveo Offline"
    exit 1
fi

if [ ! -f ~/.ssh/known_hosts ]; then
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
fi
if grep -q "serveo.net" ~/.ssh/known_hosts; then
    echo "Fingerprint OK (serveo.net)"
else
    ssh-keyscan -t rsa serveo.net >> ~/.ssh/known_hosts && \
    echo "Fingerprint Add (serveo.net)"
fi

SCRIPT_NAME=$(basename "$0")
PID_FILE="/tmp/${SCRIPT_NAME}.pid"
ACTIVE_FLAG="/tmp/${SCRIPT_NAME}_active"

# Root-only state dir (not world-writable /tmp) to avoid symlink attacks on
# files that must persist across start/status/stop invocations
STATE_DIR="/run/${SCRIPT_NAME}"
mkdir -p -m 700 "$STATE_DIR"
OUTPUT_FILE="$STATE_DIR/output.txt"
PORTS_FILE="$STATE_DIR/ports.txt"

is_running() {
    if pgrep -f "ssh.*serveo.net" > /dev/null; then
        return 0
    elif [ -f "$ACTIVE_FLAG" ]; then
        return 0
    else
        return 1
    fi
}

kill_all_tunnel_processes() {
    pkill -f "ssh.*serveo.net" 2>/dev/null
    for pid in $(ps ax | grep -v grep | grep "[s]sh.*serveo.net" | awk '{print $1}'); do
        kill -9 "$pid" 2>/dev/null
    done
    current_pid=$$
    for pid in $(ps ax | grep -v grep | grep "[b]ash.*${SCRIPT_NAME}" | awk '{print $1}'); do
        if [ "$pid" != "$current_pid" ]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done
    rm -f "$PID_FILE" "$ACTIVE_FLAG" 2>/dev/null
    sleep 1
    if ps ax | grep -v grep | grep -q "[s]sh.*serveo.net"; then
        echo "Forcing termination..."
        pkill -9 -f "ssh.*serveo.net" 2>/dev/null
        sleep 1
    fi
}

start() {
    # prevent overlapping runs
    SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$SCRIPT_LOCK")
    exec 200>"$SCRIPT_LOCK"
    if ! flock -n 200; then
        echo "Script $(basename "$0") is already running"
        exit 1
    fi

    kill_all_tunnel_processes
    echo "Ports commonly exposed for remote access:"
    echo "SSH Access: 22 (SSH), 3306/5432 (Databases)..."
    echo "Web Access: 80 (HTTP), 443 (HTTPS)..."
    echo
    read -p "Enter port number(s) to expose (separated by spaces):" ports
    if [ -z "$ports" ]; then
        echo "Error. You must enter at least one port."
        exit 1
    fi

    touch "$ACTIVE_FLAG"
    PORT_ARGS=''
    local_ports=()
    for port in $ports; do
        if ss -tuln | grep -q ":$port "; then
            echo "Port $port accessible "
        else
            echo "Port $port is not accessible locally"
            echo "Make sure a service is listening on that port"
            continue
        fi
        PORT_ARGS+=" -R 0:localhost:$port"
        local_ports+=($port)
    done
    if [ -z "$PORT_ARGS" ]; then
        echo "Ports could not be added. The tunnel will not start."
        rm -f "$ACTIVE_FLAG"
        exit 1
    fi
    echo "Starting tunnel with ports: $ports"

    > "$OUTPUT_FILE"
    # OPCIONAL: Add the following options if you do not want to use SSH fingerprint verification
    # -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    ssh -q -T -o LogLevel=ERROR -o ServerAliveInterval=60 -o ServerAliveCountMax=30 ${PORT_ARGS:-} serveo.net > "$OUTPUT_FILE" 2>&1 &
    SSH_PID=$!
    echo "$SSH_PID" > "$PID_FILE"

    for i in {1..10}; do
        if [ -s "$OUTPUT_FILE" ]; then
            break
        fi
        sleep 1
    done

    output=$(cat "$OUTPUT_FILE")

    if [ -z "$output" ]; then
        echo "Error: Could not get output from Serveo"
        rm -f "$ACTIVE_FLAG"
        kill $SSH_PID 2>/dev/null
        exit 1
    fi

    echo "Serveo Output:"
    echo "$output"

    assigned_ports=$(echo "$output" | grep -oP 'serveo\.net:\K[0-9]+' | head -n ${#local_ports[@]})
    if [ -z "$assigned_ports" ]; then
        echo "The remote ports assigned by Serveo could not be obtained"
        rm -f "$ACTIVE_FLAG"
        kill $SSH_PID 2>/dev/null
        exit 1
    fi

    echo "Remote ports assigned by serveo:"
    for assigned_port in ${assigned_ports[@]}; do
        echo "$assigned_port"
    done

    i=0
    for assigned_port in $assigned_ports; do
        local_port="${local_ports[$i]}"

        if [[ "$local_port" -eq 22 ]] || [[ "$local_port" -eq 21 ]] || \
           [[ "$local_port" -eq 25 ]] || [[ "$local_port" -eq 53 ]] || \
           [[ "$local_port" -eq 110 ]] || [[ "$local_port" -eq 143 ]] || \
           [[ "$local_port" -eq 3306 ]] || [[ "$local_port" -eq 5432 ]] || \
           [[ "$local_port" -eq 6379 ]]; then
            echo "To connect from the remote client to the local port $local_port, run:"
            echo "ssh -p $assigned_port $local_user@serveo.net"
        else
            echo "Open your browser and access the port $local_port:"
            echo "https://serveo.net:$assigned_port"
        fi
        ((i++)) || true
    done

    rm -f "$ACTIVE_FLAG"
    echo "The tunnel is now active"

    > "$PORTS_FILE"
    i=0
    for assigned_port in $assigned_ports; do
        local_port="${local_ports[$i]}"
        echo "$local_port:$assigned_port" >> "$PORTS_FILE"
        ((i++)) || true
    done
}

stop() {
    local tunnel_pids
    tunnel_pids=$(pgrep -f "ssh.*serveo.net")

    if [[ -n "$tunnel_pids" ]]; then
        echo "Stopping the tunnel..."
        kill_all_tunnel_processes
        sleep 1

        if pgrep -f "ssh.*serveo.net" > /dev/null; then
            echo "ERROR: Not all processes could be stopped. Try manually:"
            echo "pkill -9 -f \"ssh.*serveo.net\""
        else
            echo "Tunnel successfully stopped"
            rm -f "$PORTS_FILE"
        fi
    else
        echo "There are no active tunnels"
        rm -f "$PORTS_FILE"
    fi
}

status() {
    if is_running; then
        echo "The tunnel is running"

        ssh_pids=$(ps ax | grep -v grep | grep "[s]sh.*serveo.net" | awk '{print $1}')
        if [ -n "$ssh_pids" ]; then
            echo "Active SSH processes: $ssh_pids"
        fi

        if [ -f "$PID_FILE" ]; then
            echo "PID: $(cat "$PID_FILE" 2>/dev/null || echo "not available")"
        fi

        if [ -f "$PORTS_FILE" ]; then
            echo "Exposed Ports:"
            while IFS=: read -r local_port remote_port; do
                if [[ "$local_port" -eq 22 ]]; then
                    echo "Local $local_port -> ssh -p $remote_port user@serveo.net"
                else
                    echo "Local $local_port -> https://serveo.net:$remote_port"
                fi
            done < "$PORTS_FILE"
        else
            echo "No port mapping info found."
        fi

    else
        echo "The tunnel is NOT running"
    fi
}

case "${1:-}" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
        echo "Uso: $0 {start|stop|status}"
        exit 1
        ;;
esac
