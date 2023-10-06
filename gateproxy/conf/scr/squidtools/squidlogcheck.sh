#!/bin/bash
# by maravento.com

# Squid Log Audit: Regular Expressions Check

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

echo "Squid Log Audit: Regular Expressions Check..."
echo -e
read -p "Enter the word and press ENTER (e.g.: video): " WORD
perl -pe 's/[\d\.]+/localtime($&)/e' /var/log/squid/access.log | grep -i "clientAccessCheckDone" | grep -i --color -E "$WORD"

if [ $? -gt 0 ]; then
  echo "There are no records of: $WORD"
else
  echo "Done"
fi
