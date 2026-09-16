#!/bin/bash
# maravento.com
#
################################################################################
#
# x11vncmgr.sh
# Manages x11vnc as a systemd service:
# install, uninstall, start, stop, status, restart
# Must be run as root (sudo)
#
# Usage: x11vncmgr.sh [install|uninstall|start|stop|restart|status]
#
#   install    Install x11vnc, create the VNC password if missing, create and
#              enable the systemd service, and start it
#   uninstall  Stop and disable the service, remove the service file, remove
#              the x11vnc package, remove the password file, and clear logs
#   start      Start the service
#   stop       Stop the service
#   restart    Restart the service
#   status     Show whether the service is active and the port is listening
#
#   Run with no arguments for an interactive menu with the same options.
#
# NOTE on logging:
# - This script's own actions are logged to /var/log/x11vncmgr.log
#   (rewritten on each run).
# - x11vnc_log_file (below) is unrelated: it is where the x11vnc daemon itself
#   writes its own runtime output (passed via -o to x11vnc), not this
#   script's own log.
#
################################################################################

set -uo pipefail

display_num=":0"
xauth_path="/var/run/lightdm/root/:0"
vnc_passwd="/root/.vnc/passwd"
vnc_port="5900"
service_name="x11vnc"
service_file="/etc/systemd/system/${service_name}.service"
x11vnc_log_file="/var/log/x11vnc.log"

# logging
log_file="/var/log/x11vncmgr.log"
{ > "$log_file"; } 2>/dev/null || true
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# root check
if [ "$(id -u)" != "0" ]; then
    log "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    log "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# dependencies
for dep in iproute2 util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        log "ERROR: dependency '$dep' is not installed -- abort"
        exit 1
    fi
done

check_password_exists() {
    if [ ! -f "$vnc_passwd" ]; then
        x11vnc -storepasswd "$vnc_passwd"
    fi
}

verify_running() {
    if ! systemctl is-active --quiet "$service_name"; then
        log "ERROR: $service_name is not active."
        exit 1
    fi

    if ! ss -tlnp | grep -q ":${vnc_port} "; then
        log "ERROR: port ${vnc_port} is not listening."
        exit 1
    fi

    log "$service_name is active and listening on port ${vnc_port}."
}

verify_removed() {
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log "ERROR: $service_name is still active."
        exit 1
    fi

    if [ -f "$service_file" ]; then
        log "ERROR: $service_file still exists."
        exit 1
    fi

    log "$service_name uninstalled."
}

do_install() {
    if ! command -v x11vnc >/dev/null 2>&1; then
        if ! apt_out=$(apt update 2>&1); then
            log "ERROR: apt update failed."
            echo "$apt_out"
            exit 1
        fi

        if ! apt_out=$(apt install -y x11vnc 2>&1); then
            log "ERROR: failed to install x11vnc package."
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
ExecStop=/usr/bin/pkill x11vnc
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
            log "ERROR: failed to remove x11vnc package."
            echo "$apt_out"
            exit 1
        fi
    fi

    if [ -f "$vnc_passwd" ]; then
        rm -f "$vnc_passwd"
    fi

    verify_removed

    rm -f "$x11vnc_log_file" "$log_file"
    exit 0
}

do_start() {
    check_password_exists
    systemctl start "$service_name"

    log "Service started."

    do_status
}

do_stop() {
    systemctl stop "$service_name"

    log "Service stopped."
}

do_restart() {
    systemctl restart "$service_name"

    log "Service restarted."

    do_status
}

do_status() {
    if systemctl is-active --quiet "$service_name"; then
        local pid
        pid=$(systemctl show -p MainPID --value "$service_name")
        echo "[UP] $service_name (PID $pid)"
    else
        echo "[DOWN] $service_name"
    fi

    if ss -tlnp | grep -q ":${vnc_port} "; then
        echo "[UP] port ${vnc_port} listening"
    else
        echo "[DOWN] port ${vnc_port} not listening"
    fi
}

usage() {
    echo "Usage: $0 {install|uninstall|start|stop|restart|status}"
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
        0) exit 0 ;;
        *) echo "Invalid option."; exit 1 ;;
    esac
}

# Start
log "x11vncmgr start..."

if [ -z "${1:-}" ]; then
    menu
else
    case "$1" in
        install)   do_install ;;
        uninstall) do_uninstall ;;
        start)     do_start ;;
        stop)      do_stop ;;
        restart)   do_restart ;;
        status)    do_status ;;
        *)         usage ;;
    esac
fi

# End
log "x11vncmgr done at: $(date '+%Y-%m-%d %H:%M:%S')"
