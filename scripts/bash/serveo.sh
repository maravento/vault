#!/bin/bash
# maravento.com

# Serveo tunnel start | stop | status
# https://serveo.net/

echo "Serveo Tunnel Starting. Wait..."
printf "\n"

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

# check dependencies
if ! command -v ssh >/dev/null 2>&1; then
    echo "⚠️ SSH is not installed"
    echo "run: sudo apt install openssh-server"
    exit 1
fi

SCRIPT_NAME=$(basename "$0")
PID_FILE="/tmp/${SCRIPT_NAME}.pid"
ACTIVE_FLAG="/tmp/${SCRIPT_NAME}_active"

# Local User
local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')

# check serveo
is_running() {
    if pgrep -f "ssh.*serveo.net" > /dev/null; then
        return 0
    elif [ -f "$ACTIVE_FLAG" ]; then
        return 0
    else
        return 1
    fi
}

# Kill Tunnel
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
    # Stop any existing instances
    kill_all_tunnel_processes
    echo "Ports commonly exposed for remote access:"
    echo "SSH Access:   22 (SSH), 3306/5432 (Databases)..."
    echo "Web Access:   80 (HTTP), 443 (HTTPS)..."
    echo
    read -p "Enter port number(s) to expose (separated by spaces):" ports
    if [ -z "$ports" ]; then
        echo "❌ Error. You must enter at least one port."
        exit 1
    fi

    # Create activity flag
    touch "$ACTIVE_FLAG"
    # Create the SSH argument list and check the ports
    PORT_ARGS=''
    local_ports+=($port)
    for port in $ports; do
        if ss -tuln | grep -q ":$port "; then
            echo "Port $port accessible ✅"
        else
            echo "⚠️ Port $port is not accessible locally"
            echo "   Make sure a service is listening on that port"
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

    > /tmp/serveo_output.txt
    ssh -q -T \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=30 \
    $PORT_ARGS serveo.net > /tmp/serveo_output.txt 2>&1 &
    SSH_PID=$!

    for i in {1..10}; do
        if [ -s /tmp/serveo_output.txt ]; then
            break
        fi
        sleep 1
    done

    output=$(cat /tmp/serveo_output.txt)

    echo "Serveo Output:"
    echo "$output"

    # Check if the file has content
    if [ -z "$output" ]; then
        echo "Error: Could not get output from Serveo"
        rm -f "$ACTIVE_FLAG"
        kill $SSH_PID 2>/dev/null
        exit 1
    fi
    
    # Display full output for debugging
    echo "Serveo Output:"
    echo "$output"
    
    # Check if remote ports were assigned
    assigned_ports=$(echo "$output" | grep -oP 'serveo\.net:\K[0-9]+' | head -n ${#local_ports[@]})
    if [ -z "$assigned_ports" ]; then
        echo "The remote ports assigned by Serveo could not be obtained"
        rm -f "$ACTIVE_FLAG"
        kill $SSH_PID 2>/dev/null
        exit 1
    fi
    
    # Display remote ports assigned by Serveo
    echo "Remote ports assigned by serveo:"
    for assigned_port in ${assigned_ports[@]}; do
        echo "$assigned_port"
    done

    # Display SSH command for remote client and bind ports
    i=0
    for assigned_port in $assigned_ports; do
        local_port="${local_ports[$i]}"
        
        # Condition for common SSH ports
        if [[ "$local_port" -eq 22 ]] || [[ "$local_port" -eq 21 ]] || \
           [[ "$local_port" -eq 25 ]] || [[ "$local_port" -eq 53 ]] || \
           [[ "$local_port" -eq 110 ]] || [[ "$local_port" -eq 143 ]] || \
           [[ "$local_port" -eq 3306 ]] || [[ "$local_port" -eq 5432 ]] || \
           [[ "$local_port" -eq 6379 ]]; then
            echo "To connect from the remote client to the local port $local_port, run:"
            echo "  ssh -p $assigned_port $local_user@serveo.net"
        else
            # For web ports, always display the URL with the assigned port
            echo "Open your browser and access the port $local_port:"
            echo "  https://serveo.net:$assigned_port"
        fi
        ((i++))
    done
    
    # Remove flag when finished
    rm -f "$ACTIVE_FLAG"
    echo "The tunnel is now active"
    
    # save ports
    > /tmp/serveo_ports.txt
    i=0
    for assigned_port in $assigned_ports; do
        local_port="${local_ports[$i]}"
        echo "$local_port:$assigned_port" >> /tmp/serveo_ports.txt
        ((i++))
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
            echo "❌ ERROR: Not all processes could be stopped. Try manually:"
            echo "pkill -9 -f \"ssh.*serveo.net\""
        else
            echo "✅ Tunnel successfully stopped"
            rm -f /tmp/serveo_ports.txt
        fi
    else
        echo "⚠️ There are no active tunnels"
        rm -f /tmp/serveo_ports.txt
    fi
}


status() {
    if is_running; then
        echo "✅ The tunnel is running"

        ssh_pids=$(ps ax | grep -v grep | grep "[s]sh.*serveo.net" | awk '{print $1}')
        if [ -n "$ssh_pids" ]; then
            echo "Active SSH processes: $ssh_pids"
        fi

        if [ -f "$PID_FILE" ]; then
            echo "PID: $(cat "$PID_FILE" 2>/dev/null || echo "not available")"
        fi

        if [ -f /tmp/serveo_ports.txt ]; then
            echo "Exposed Ports:"
            while IFS=: read -r local_port remote_port; do
                if [[ "$local_port" -eq 22 ]]; then
                    echo "  Local $local_port ➜ ssh -p $remote_port user@serveo.net"
                else
                    echo "  Local $local_port ➜ https://serveo.net:$remote_port"
                fi
            done < /tmp/serveo_ports.txt
        else
            echo "No port mapping info found."
        fi

    else
        echo "⚠️ The tunnel is NOT running"
    fi
}

case "$1" in
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

