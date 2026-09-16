#!/bin/bash
# maravento.com
#
################################################################################
#
# ngLocalhost tunnel start | stop | status
# https://www.nglocalhost.com/
# Before using this script:
# - Register on the tunnel service website with your email address.
# - The server fingerprint will be automatically managed by this script.
#
################################################################################

set -uo pipefail

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "ERROR: This script should not be run as root -- abort"
    exit 1
fi

echo "ngLocalhost Tunnel Starting. Wait..."

# dependencies
for dep in openssh-client netcat-openbsd procps iproute2 coreutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

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

script_name=$(basename "$0")
run_dir="/run/user/${UID}"
mkdir -p "$run_dir"
active_flag="${run_dir}/${script_name}_active"
pid_file="${run_dir}/${script_name}.pid"
ports_file="${run_dir}/${script_name}.ports"
is_running() {
    if pgrep -f "ssh.*nglocalhost.com" > /dev/null || [ -f "$active_flag" ]; then
        return 0
    else
        return 1
    fi
}
kill_all_tunnel_processes() {
    pkill -f "ssh.*nglocalhost.com" 2>/dev/null
    rm -f "$pid_file" "$active_flag" "$ports_file"
}
start() {
    # prevent overlapping runs
    script_lock="/var/lock/$(basename "$0" .sh).lock"
    (umask 077; : >> "$script_lock")
    exec 200>"$script_lock"
    if ! flock -n 200; then
        echo "ERROR: script $(basename "$0") is already running -- abort"
        exit 1
    fi

    kill_all_tunnel_processes
    read -r -p "Enter port number(s) to expose: " ports
    if [ -z "$ports" ]; then
        echo "Error. You must enter at least one port."
        exit 1
    fi
    touch "$active_flag"
    port_args=""
    local_ports=()
    for port in $ports; do
        if ss -tuln | grep -q ":$port "; then
            echo "Port $port accessible "
        else
            echo "Port $port is not accessible locally"
            continue
        fi
        port_args+=" -R 0:localhost:$port"
        local_ports+=($port)
    done
    if [ -z "$port_args" ]; then
        rm -f "$active_flag"
        exit 1
    fi
    local output_file
    output_file=$(mktemp /tmp/nglocalhost_output.XXXXXX)
    ssh -q -T -o LogLevel=ERROR -o ServerAliveInterval=60 -o ServerAliveCountMax=30 ${port_args:-} nglocalhost.com > "$output_file" 2>&1 &
    ssh_pid=$!
    echo "$ssh_pid" > "$pid_file"
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
        rm -f "$active_flag"
        kill "$ssh_pid" 2>/dev/null
        exit 1
    fi
    > "$ports_file"
    i=0
    for assigned_port in $assigned_ports; do
        echo "Local ${local_ports[$i]} -> https://nglocalhost.com:$assigned_port"
        echo "${local_ports[$i]}:$assigned_port" >> "$ports_file"
        ((i++)) || true
    done
    rm -f "$active_flag"
}
stop() {
    if is_running; then
        kill_all_tunnel_processes
        echo "Tunnel stopped"
    else
        echo "No tunnel running"
    fi
}
status() {
    if is_running; then
        echo "Tunnel running"
        cat "$ports_file" 2>/dev/null
    else
        echo "Tunnel NOT running"
    fi
}
case "${1:-}" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|status}" ;;
esac
