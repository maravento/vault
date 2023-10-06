#!/bin/bash
# by maravento.com

# Lock Scripts

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

randa=$(($RANDOM % 3 + 1))
pid_execute=$(ps -eo pid,comm | grep $0 | egrep -o '[0-9]+')
if [[ "${pid_execute:-NO_VALUE}" != "NO_VALUE" ]]; then
    echo "$0 $@" | at now + "$randa" min
    exit
    echo "Lock Start: $(date)" | tee -a /var/log/syslog
fi
