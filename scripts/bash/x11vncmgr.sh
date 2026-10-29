#!/bin/bash
# maravento.com
#
################################################################################
#
# x11vncmgr -- x11vnc systemd service manager
# FILE: x11vncmgr.sh
#
# DESCRIPTION: Manages x11vnc as a systemd service: install, uninstall, start,
# stop, status and restart. Must be run as root.
#
# USAGE: x11vncmgr.sh [--install|--uninstall|--start|--stop|--restart|--status]
#
#   --install    Install x11vnc, create the VNC password if missing, create and
#              enable the systemd service, and start it
#   --uninstall  Stop and disable the service, remove the service file, remove
#              the x11vnc package, remove the password file, and clear logs
#   --start      Start the service
#   --stop       Stop the service
#   --restart    Restart the service
#   --status     Show whether the service is active and the port is listening
#
#   Run with no arguments for an interactive menu with the same options.
#
# LOG: /var/log/x11vncmgr.log, this script's own actions, rewritten each run
#      x11vnc_log_file below is a different file: the daemon's own output,
#      passed to x11vnc with -o, not this script's log
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# root check
if [ "$(id -u)" != "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script must be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

# logging
log_file="/var/log/x11vncmgr.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$1"
    local log_msg="$(date '+%Y-%m-%d %H:%M:%S') $msg"
    echo "$log_msg" >> "$log_file" 2>/dev/null || true
    if [[ "$msg" == ERROR:* ]]; then
        echo "$log_msg" >&2
    else
        echo "$log_msg"
    fi
}

# dependencies
for dep in iproute2 util-linux systemd coreutils grep apt libc-bin; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -abort"
        exit 1
    fi
done

# check ipv4 interfaces
list_ifaces() {
    ip -br link show 2>/dev/null | awk '$1 != "lo" {sub(/@.*/, "", $1); printf "%s %s\n", $1, ($2 == "UP") ? "UP" : "DOWN"}'
}

list_ipv4_ifaces() {
    local iface state
    while read -r iface state; do
        [ "$state" = UP ] || continue
        if ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '$4 != "" {found=1} END {exit !found}'; then
            printf '%s\n' "$iface"
        fi
    done < <(list_ifaces)
}

check_ipv4_interfaces() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if [ -n "$(list_ipv4_ifaces)" ]; then
            return 0
        fi
        if (( attempt == 1 )); then
            log "INFO: waiting for an interface with IPv4..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no interface with IPv4 -abort"
    exit 1
}

# check internet
check_internet() {
    local max_attempts=24 attempt=1

    while (( attempt <= max_attempts )); do
        if getent hosts www.google.com >/dev/null 2>&1; then
            return 0
        fi
        if (( attempt == 1 )); then
            log "INFO: waiting for internet..."
        fi
        attempt=$((attempt + 1))
        sleep 5
    done

    log "ERROR: no internet connection -abort"
    exit 1
}

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

display_num=":0"
xauth_path="/var/run/lightdm/root/:0"
vnc_passwd="/root/.vnc/passwd"
vnc_port="5900"
service_name="x11vnc"
service_file="/etc/systemd/system/${service_name}.service"
x11vnc_log_file="/var/log/x11vnc.log"

# ------------------------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------------------------

check_password_exists() {
    if [ ! -f "$vnc_passwd" ]; then
        x11vnc -storepasswd "$vnc_passwd"
    fi
}

verify_running() {
    if ! systemctl is-active --quiet "$service_name"; then
        log "ERROR: $service_name is not active -abort"
        exit 1
    fi

    if ! ss -tlnp | grep -q ":${vnc_port} "; then
        log "ERROR: port ${vnc_port} is not listening -abort"
        exit 1
    fi

    log "INFO: $service_name active; port ${vnc_port} listening"
}

verify_removed() {
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log "ERROR: $service_name is still active -abort"
        exit 1
    fi

    if [ -f "$service_file" ]; then
        log "ERROR: $(basename "$service_file") still exists -abort"
        exit 1
    fi

    log "INFO: $service_name uninstalled"
}

do_install() {
    if ! command -v x11vnc >/dev/null 2>&1; then
        check_ipv4_interfaces
        check_internet
        if ! apt_out=$(apt update 2>&1); then
            log "ERROR: apt update failed -abort"
            echo "$apt_out"
            exit 1
        fi

        if ! apt_out=$(apt install -y x11vnc 2>&1); then
            log "ERROR: failed to install x11vnc package -abort"
            echo "$apt_out"
            exit 1
        fi
    fi

    check_password_exists

    cat > "$service_file" <<EOF
[Unit]
Description=x11vnc remote desktop server
After=lightdm.service network.target
Requires=lightdm.service

[Service]
Type=forking
ExecStart=/usr/bin/x11vnc -display ${display_num} -auth ${xauth_path} -rfbauth ${vnc_passwd} -forever -shared -bg -repeat -noxrecord -noxfixes -o ${x11vnc_log_file}
ExecStop=/usr/bin/pkill -x x11vnc
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$service_name"

    verify_running
}

do_uninstall() {
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true

    if [ -f "$service_file" ]; then
        rm -f "$service_file"
        systemctl daemon-reload
    fi

    if command -v x11vnc >/dev/null 2>&1; then
        if ! apt_out=$(apt remove -y x11vnc 2>&1); then
            log "ERROR: failed to remove x11vnc package -abort"
            echo "$apt_out"
            exit 1
        fi
    fi

    if [ -f "$vnc_passwd" ]; then
        rm -f "$vnc_passwd"
    fi

    verify_removed

    rm -f "$x11vnc_log_file" "$log_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: x11vncmgr done"
    exit 0
}

do_start() {
    check_password_exists
    systemctl start "$service_name"

    log "INFO: $service_name started"

    do_status
}

do_stop() {
    systemctl stop "$service_name"

    log "INFO: $service_name stopped"
}

do_restart() {
    systemctl restart "$service_name"

    log "INFO: $service_name restarted"

    do_status
}

do_status() {
    if systemctl is-active --quiet "$service_name"; then
        local pid
        pid=$(systemctl show -p MainPID --value "$service_name")
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: [UP] $service_name (PID $pid)"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: [DOWN] $service_name"
    fi

    if ss -tlnp | grep -q ":${vnc_port} "; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: [UP] port ${vnc_port} listening"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: [DOWN] port ${vnc_port} not listening"
    fi
}

usage() {
    echo "Usage: $0 {--install|--uninstall|--start|--stop|--restart|--status}"
    exit 1
}

menu() {
    echo "x11vnc manager"
    echo "1) install"
    echo "2) uninstall"
    echo "3) start"
    echo "4) stop"
    echo "5) restart"
    echo "6) status"
    echo "0) exit"
    echo ""

    local choice
    read -r -p "Select an option: " choice

    case "$choice" in
        1) do_install ;;
        2) do_uninstall ;;
        3) do_start ;;
        4) do_stop ;;
        5) do_restart ;;
        6) do_status ;;
        0) ;;
        *) log "ERROR: invalid option -abort"; exit 1 ;;
    esac
}

# ------------------------------------------------------------------------------
# ACTIONS
# ------------------------------------------------------------------------------

# Start
log "EVENT: x11vncmgr start..."

if [ -z "${1:-}" ]; then
    menu
else
    case "$1" in
        --install)   do_install ;;
        --uninstall) do_uninstall ;;
        --start)     do_start ;;
        --stop)      do_stop ;;
        --restart)   do_restart ;;
        --status)    do_status ;;
        *)         usage ;;
    esac
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# End
log "EVENT: x11vncmgr done"
