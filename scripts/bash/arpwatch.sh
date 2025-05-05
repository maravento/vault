#!/bin/bash
# maravento.com

# ARP Watch
# Usage: sudo ./arpwatch.sh start | stop | status
# To exclude MAC addresses, list them in: /etc/arpwatch/exclude.txt
# Global log (all interfaces, ignoring exclude.txt): /var/log/arpwatch/arpwatch.log
# To uninstall: sudo apt remove --purge arpwatch && sudo rm -rf /etc/arpwatch /var/log/arpwatch

echo "ArpWatch starting. Wait..."
printf "\n"

# Root permission check
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# Check for required packages (optional)
pkgs='arpwatch libnotify-bin'
if apt-get install -qq $pkgs; then
    true
else
    echo "Error installing $pkgs. Aborting."
    exit
fi

# Disable default systemd arpwatch service if it's enabled
if systemctl is-enabled --quiet arpwatch.service; then
    systemctl disable --now arpwatch.service
fi

local_user=$(who | grep -m 1 '(:0)' | awk '{print $1}' || who | head -1 | awk '{print $1}')
LOGDIR="/var/log/arpwatch"
mkdir -p "$LOGDIR"
PIDFILE="/run/arpwatch-wrapper.pid"
TAIL_PID="/run/arpwatch-tail.pid"
ARPWATCH_PIDS="/run/arpwatch-instances.pid"
UNIFIED_LOG="$LOGDIR/arpwatch.log"
touch "$UNIFIED_LOG"

# Define the whitelist file (exclude.txt) with MAC addresses that should be ignored by notifications
# Each line in the exclude.txt must contain a MAC address (format: xx:xx:xx:xx:xx:xx)
# When a new ARP event is detected, if the MAC is in the exclude.txt, no notification will be sent
WHITELIST="/etc/arpwatch/exclude.txt"
mkdir -p /etc/arpwatch
[[ -f "$WHITELIST" ]] || touch "$WHITELIST"

start() {
    echo "Starting arpwatch on active interfaces..."
    
    if [[ -f "$PIDFILE" ]]; then
        echo "arpwatch is already running."
        return
    fi
    
    > "$ARPWATCH_PIDS"
    interfaces=$(ip -o link show | grep 'state UP' | cut -d: -f2 | tr -d ' ' | grep -v '^lo$')
    
    # Inicia arpwatch para cada interfaz
    for iface in $interfaces; do
        LOGFILE="$LOGDIR/arpwatch_$iface.log"
        > "$LOGFILE"
        
        if ! pgrep -f "arpwatch -i $iface" > /dev/null; then
            echo "Running: /usr/sbin/arpwatch -i $iface -f /var/lib/arpwatch/arp_$iface.dat -d"
            /usr/sbin/arpwatch -i "$iface" -f "/var/lib/arpwatch/arp_$iface.dat" -d >> "$LOGFILE" 2>&1 &
            arp_pid=$!
            
            if [ $? -ne 0 ]; then
                echo "Failed to start arpwatch on interface $iface. Check log for details."
            else
                echo "arpwatch started on interface: $iface with PID: $arp_pid"
                echo "$arp_pid" >> "$ARPWATCH_PIDS"
            fi
        else
            echo "arpwatch is already running for interface $iface"
        fi
    done
    
    # Monitor logs y enviar notificaciones
    tail_pids=()
    for iface in $interfaces; do
        LOGFILE="$LOGDIR/arpwatch_$iface.log"
        
        tail -n0 -F "$LOGFILE" | while read -r line; do
            if [[ "$line" =~ new\ station|changed\ ethernet|flip-flop|duplicate ]]; then
                mac=$(echo "$line" | grep -o -i -E '([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}')
                if ! grep -iq "$mac" "$WHITELIST"; then
                    msg="[$iface] $line"
                    sudo -u "$local_user" DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$local_user")/bus notify-send -i checkbox "ARPWatch" "$msg"
                    echo "$(date +'%F %T') $msg" >> "$UNIFIED_LOG"
                fi
            fi
        done > "$LOGFILE" 2>&1 &

        tail_pid=$!
        tail_pids+=("$tail_pid")
        echo "Background monitoring started for interface $iface with PID: $tail_pid"
    done

    # Guardar todos los PIDs de los tails en un archivo
    for pid in "${tail_pids[@]}"; do
        echo "$pid" >> "$TAIL_PID"
    done

    # Almacenar el PID de la función principal
    echo "$tail_pids" >> "$PIDFILE"
    echo "arpwatch service successfully started in background."
}

stop() {
    if [[ -f "$PIDFILE" ]]; then
        echo "Stopping arpwatch..."

        # Detener el proceso de tail si existe
        [[ -f "$TAIL_PID" ]] && kill $(cat "$TAIL_PID") 2>/dev/null && rm -f "$TAIL_PID" && echo "Stopped monitoring process"

        # Matar procesos arpwatch
        [[ -f "$ARPWATCH_PIDS" ]] && while read -r pid; do kill -9 "$pid" 2>/dev/null && echo "Stopped arpwatch process: $pid"; done < "$ARPWATCH_PIDS" && rm -f "$ARPWATCH_PIDS"

        # Matar el script específico
        for pid in $(ps -ef | grep "[b]ash ./arpwatch.sh start" | awk '{print $2}'); do
            kill -9 "$pid" 2>/dev/null && echo "Stopped arpwatch.sh process: $pid"
        done

        # Eliminar archivo PID principal
        rm -f "$PIDFILE"
        echo "All arpwatch processes have been stopped."
    else
        echo "arpwatch is not running."
    fi
}

status() {
    if [[ -f "$PIDFILE" ]]; then
        echo "arpwatch script is running with PID: $(cat "$PIDFILE")"
        
        if [[ -f "$TAIL_PID" ]]; then
            echo "Monitoring process running with PID: $(cat "$TAIL_PID")"
        else
            echo "Monitoring process is not running."
        fi
        
        if [[ -f "$ARPWATCH_PIDS" ]]; then
            echo "arpwatch instances running:"
            cat "$ARPWATCH_PIDS"
        else
            echo "No arpwatch instances are currently running."
        fi
    else
        echo "arpwatch is not running."
    fi
}

case "$1" in
    start) start ;;
    stop) stop ;;
    status) status ;;
    *) echo "Usage: $0 {start|stop|status}" ;;
esac

