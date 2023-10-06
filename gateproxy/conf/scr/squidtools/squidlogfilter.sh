#!/bin/bash
# by maravento.com

# Squid Log Audit: Filtering IP and Words

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

# check dependencies
pkg='perl'
if apt-get -qq install $pkg; then
  echo "OK"
else
  echo "Error installing $pkg. Abort"
  exit
fi

echo "Start Log Audit: Filtering IP and Words..."
echo -e
read -p "Enter IP and press ENTER (e.g. 192.168.0.10): " IP
read -p "Enter the word and press ENTER (e.g. google): " WORD

IPNEW=$(echo "$IP" | grep -E '^(([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$')

if [ "$IPNEW" ]; then
  perl -pe 's/[\d\.]+/localtime($&)/e' /var/log/squid/access.log | grep "$IPNEW" | grep -i --color -E "$WORD"
else
  perl -pe 's/[\d\.]+/localtime($&)/e' /var/log/squid/access.log | grep -i --color -E "$WORD"
fi

if [ $? -gt 0 ]; then
  echo "There are no records of: $WORD"
else
  echo "Done"
fi
