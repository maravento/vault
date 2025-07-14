#!/bin/bash
# maravento.com

# Squid Cache Log Audit: Regular Expressions Check

# IMPORTANT BEFORE USE
# Enable the debug_log directive in squid.conf with the following settings:
# debug_options ALL,1 33,2 28,9

echo "Squid Log Audit Start. Wait..."
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

### SQUID AUDIT
echo "Squid Log Audit: Regular Expressions Check..."
echo -e
read -p "Enter the word and press ENTER (e.g.: video): " WORD
perl -pe 's/[\d\.]+/localtime($&)/e' /var/log/squid/cache.log | grep -i "clientAccessCheckDone" | grep -i --color=always -E "$WORD"

if [ $? -gt 0 ]; then
  echo "There are no records of: $WORD"
else
  echo "Done"
fi
