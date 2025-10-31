#!/bin/bash
# maravento.com
#
# Port Kill
# check port with: sudo netstat -lnp | grep "port"

echo "Port Kill Starting. Wait..."
printf "\n"

# check root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

# check script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

# check SO
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
if [[ "$UBUNTU_ID" != "ubuntu" || ( "$UBUNTU_VERSION" != "22.04" && "$UBUNTU_VERSION" != "24.04" ) ]]; then
    echo "Unsupported system. Use at your own risk"
    # exit 1
fi

### PORT KILL
read -p "Enter Port Number to close: " port
kill $(lsof -t -i:"$port") &>/dev/null
if [ $? -gt 0 ]; then
    echo "There are no records of $port"
else
    echo "Done"
fi
