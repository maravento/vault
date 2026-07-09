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
#   (append-only, no rotation configured by this script).
#   To clear it manually: truncate -s 0 /var/log/x11vncmgr.log
# - LOG_FILE (below) is unrelated: it is where the x11vnc daemon itself
#   writes its own runtime output (passed via -o to x11vnc), not this
#   script's own log.
#
################################################################################

set -e

DISPLAY_NUM=":0"
XAUTH_PATH="/var/run/lightdm/root/:0"
VNC_PASSWD="/root/.vnc/passwd"
VNC_PORT="5900"
SERVICE_NAME="x11vnc"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
LOG_FILE="/var/log/x11vnc.log"

# logging
log_file="/var/log/x11vncmgr.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR: This script must be run as root (sudo)."
        exit 1
    fi
}

check_password_exists() {
    if [ ! -f "$VNC_PASSWD" ]; then
        x11vnc -storepasswd "$VNC_PASSWD"
    fi
}

verify_running() {
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        log "ERROR: $SERVICE_NAME is not active."
        exit 1
    fi

    if ! ss -tlnp | grep -q ":${VNC_PORT} "; then
        log "ERROR: port ${VNC_PORT} is not listening."
        exit 1
    fi

    log "$SERVICE_NAME is active and listening on port ${VNC_PORT}."
}

verify_removed() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        log "ERROR: $SERVICE_NAME is still active."
        exit 1
    fi

    if [ -f "$SERVICE_FILE" ]; then
        log "ERROR: $SERVICE_FILE still exists."
        exit 1
    fi

    log "$SERVICE_NAME uninstalled."
}

do_install() {
    require_root

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

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=x11vnc remote desktop server
After=lightdm.service network.target
Requires=lightdm.service

[Service]
Type=forking
ExecStart=/usr/bin/x11vnc -display ${DISPLAY_NUM} -auth ${XAUTH_PATH} -rfbauth ${VNC_PASSWD} -forever -shared -bg -repeat -noxrecord -noxfixes -o ${LOG_FILE}
ExecStop=/usr/bin/pkill x11vnc
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"

    verify_running
}

do_uninstall() {
    require_root

    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true

    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    if command -v x11vnc >/dev/null 2>&1; then
        if ! apt_out=$(apt remove -y x11vnc 2>&1); then
            log "ERROR: failed to remove x11vnc package."
            echo "$apt_out"
            exit 1
        fi
    fi

    if [ -f "$VNC_PASSWD" ]; then
        rm -f "$VNC_PASSWD"
    fi

    verify_removed

    rm -f "$LOG_FILE" "$log_file"
    exit 0
}

do_start() {
    require_root
    check_password_exists
    systemctl start "$SERVICE_NAME"

    log "Service started."

    do_status
}

do_stop() {
    require_root
    systemctl stop "$SERVICE_NAME"

    log "Service stopped."
}

do_restart() {
    require_root
    systemctl restart "$SERVICE_NAME"

    log "Service restarted."

    do_status
}

do_status() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        local pid
        pid=$(systemctl show -p MainPID --value "$SERVICE_NAME")
        echo "[UP] $SERVICE_NAME (PID $pid)"
    else
        echo "[DOWN] $SERVICE_NAME"
    fi

    if ss -tlnp | grep -q ":${VNC_PORT} "; then
        echo "[UP] port ${VNC_PORT} listening"
    else
        echo "[DOWN] port ${VNC_PORT} not listening"
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

if [ -z "$1" ]; then
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
log "x11vncmgr done at: $(date)"
