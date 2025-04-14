#!/bin/bash
# by maravento.com

# CPU Limit (start / stop / status)

echo "CPU limit Starting. Wait..."
printf "\n"

# checking root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# checking dependencies (optional)
#pkgs='cpulimit'
#if apt-get install -qq $pkgs; then
#    true
#else
#    echo "Error installing $pkgs. Abort"
#    exit
#fi

start_limit() {
    # program name:
    read -p "Enter the program name: " program_name

    # PID capture
    pid=$(pgrep -f "$program_name")
    if [ -z "$pid" ]; then
        echo "PID was not found '$program_name'."
        exit 1
    fi

    # CPU %
    read -p "Enter the CPU % number for '$program_name' (0-100): " cpu_limit

    # Check CPU %
    if ! [[ "$cpu_limit" =~ ^[0-9]+$ ]] || [ "$cpu_limit" -lt 0 ] || [ "$cpu_limit" -gt 100 ]; then
        echo "Invalid percentage. It must be a number between 0 and 100"
        exit 1
    fi

    # Apply cpulimit to the program's PID
    cpulimit -l "$cpu_limit" -p "$pid" &
    echo "$cpu_limit% has been applied to the '$program_name' (PID: $pid)."
}

status_limit() {
  # Check CPU Limit
  if pgrep -x "cpulimit" >/dev/null; then
    # If PID check process
    if pgrep -ax "cpulimit" | awk '{print $1}' >/dev/null; then
      process=$(ps ho command --pid $(pgrep -ax "cpulimit" | awk '{print $6}'))
      echo "CPU Limit Active over $process"
    else
      echo "CPU Limit Active, but cannot get the associated process"
    fi
  else
    echo "No CPU Limit is currently active"
  fi
}

stop_limit() {
    # stop cpulimit
    pkill -x "cpulimit"
    echo "All CPU Limit have been stopped"
}

# start|stop|status

case "$1" in
    start)
        start_limit
        ;;
    stop)
        stop_limit
        ;;
    status)
        status_limit
        ;;
    *)
        echo "Uso: $0 {start|stop|status}"
        exit 1
        ;;
esac

exit 0
