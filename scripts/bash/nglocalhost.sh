#!/bin/bash
# maravento.com
#
################################################################################
#
# ngLocalhost tunnel start | stop | status
# https://www.nglocalhost.com/
# ⚠ Before using this script:
# - Register on the tunnel service website with your email address.
# - The server fingerprint will be automatically managed by this script.
#
################################################################################

echo "ngLocalhost Tunnel Starting. Wait..."
printf "\n"

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
    echo "⚠️ SSH is not installed"
    echo "run: sudo apt install openssh-server"
    exit 1
fi

if ! nc -z -w 5 nglocalhost.com 22; then
    echo "ngLocalhost Offline"
    exit 1
fi

if [ ! -f ~/.ssh/known_hosts ]; then
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 600 ~/.ssh/known_hosts
fi

if grep -q "nglocalhost.com" ~/.ssh/known_hosts; then
    echo "Fingerprint OK (nglocalhost.com)"
else
    ssh-keyscan -t rsa nglocalhost.com >> ~/.ssh/known_hosts && \
    echo "Fingerprint Add (nglocalhost.com)"
fi

SCRIPT_NAME=$(basename "$0")
ACTIVE_FLAG="/tmp/${SCRIPT_NAME}_active"
PID_FILE="/tmp/${SCRIPT_NAME}.pid"
PORTS_FILE="/tmp/${SCRIPT_NAME}.${UID}.ports"
is_running() {
    if pgrep -f "ssh.*nglocalhost.com" > /dev/null || [ -f "$ACTIVE_FLAG" ]; then
        return 0
    else
        return 1
    fi
}
kill_all_tunnel_processes() {
    pkill -f "ssh.*nglocalhost.com" 2>/dev/null
    rm -f "$PID_FILE" "$ACTIVE_FLAG" "$PORTS_FILE"
}
start() {
    kill_all_tunnel_processes
    read -p "Enter port number(s) to expose: " ports
    if [ -z "$ports" ]; then
        echo "❌ Error. You must enter at least one port."
        exit 1
    fi
    touch "$ACTIVE_FLAG"
    PORT_ARGS=""
    local_ports=()
    for port in $ports; do
        if ss -tuln | grep -q ":$port "; then
            echo "Port $port accessible ✅"
        else
            echo "⚠️ Port $port is not accessible locally"
            continue
        fi
        PORT_ARGS+=" -R 0:localhost:$port"
        local_ports+=($port)
    done
    if [ -z "$PORT_ARGS" ]; then
        rm -f "$ACTIVE_FLAG"
        exit 1
    fi
    local output_file
    output_file=$(mktemp /tmp/nglocalhost_output.XXXXXX)
    ssh -q -T -o LogLevel=ERROR -o ServerAliveInterval=60 -o ServerAliveCountMax=30 ${PORT_ARGS:-} nglocalhost.com > "$output_file" 2>&1 &
    SSH_PID=$!
    echo "$SSH_PID" > "$PID_FILE"
    for i in {1..10}; do
        if [ -s "$output_file" ]; then
            break
        fi
        sleep 1
    done
    output=$(cat "$output_file")
    rm -f "$output_file"
    echo "$output"
    assigned_ports=$(echo "$output" | grep -oP 'nglocalhost\.com:\K[0-9]+')
    if [ -z "$assigned_ports" ]; then
        echo "No remote ports assigned"
        rm -f "$ACTIVE_FLAG"
        kill "$SSH_PID" 2>/dev/null
        exit 1
    fi
    > "$PORTS_FILE"
    i=0
    for assigned_port in $assigned_ports; do
        echo "Local ${local_ports[$i]} ➜ https://nglocalhost.com:$assigned_port"
        echo "${local_ports[$i]}:$assigned_port" >> "$PORTS_FILE"
        ((i++)) || true
    done
    rm -f "$ACTIVE_FLAG"
}
stop() {
    if is_running; then
        kill_all_tunnel_processes
        echo "✅ Tunnel stopped"
    else
        echo "⚠️ No tunnel running"
    fi
}
status() {
    if is_running; then
        echo "✅ Tunnel running"
        cat "$PORTS_FILE" 2>/dev/null
    else
        echo "⚠️ Tunnel NOT running"
    fi
}
case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|status}" ;;
esac
