#!/bin/bash
# by maravento.com

# BlackWord
# File Extensions/Patterns to Block

echo "BlackWord Start. Wait..."
printf "\n"

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
    for p in $(pidof -x $(basename $0)); do
        if [ "$p" -ne $$ ]; then
            echo "Script $0 is already running..."
            exit
        fi
    done
fi

### VARIABLES
wgetd='wget -q -c --no-check-certificate --retry-connrefused --timeout=10 --tries=4'

function rw() {
    curl -k -X GET --connect-timeout 10 --retry 1 -I "$1" &>/dev/null
    if [ $? -eq 0 ]; then
        $wgetd "$1" -O - >> bw_source.txt
    else
        echo ERROR "$1"
    fi
}
rw 'https://raw.githubusercontent.com/dannyroemhild/ransomware-fileext-list/refs/heads/master/fileextlist.txt' && sleep 1
rw 'https://raw.githubusercontent.com/eshlomo1/Ransomware-NOTE/refs/heads/main/ransomware-extension-list.txt' && sleep 1
rw 'https://raw.githubusercontent.com/giacomoarru/ransomware-extensions-2024/refs/heads/main/ransomware-extensions.txt' && sleep 1
rw 'https://raw.githubusercontent.com/kinomakino/ransomware_file_extensions/master/extensions.csv' && sleep 1
rw 'https://raw.githubusercontent.com/nspoab/malicious_extensions/refs/heads/main/list1' && sleep 1

# Debugging
grep -P '^[\x00-\x7F]*$' bw_source.txt | sed 's/^[^a-zA-Z0-9]*//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/[^a-zA-Z0-9]*$//' | sed '/ /d' | sed '/^$/d' | sort -u > bw_output.txt

# For Samba Veto Files
echo "veto files = $(cat {bw_output,bw_debug}.txt | sed 's/^/*./' | paste -sd '' - | sed 's/*/\/&/g; s/$/\//' | sort -u)" > bw_smb.txt
echo "Samba Add. Config: bw_smb.txt"

# For Squid Extensions/Patterns
cat {bw_output,bw_debug}.txt | sed -E 's/^\*\.\?//; s/^/\\./; s/(.*)/\1([a-zA-Z][0-9]*)?(\\?.*)?$/' | sort -u > bw_squid.txt
echo "ACL for Squid: bw_squid.txt"

echo "Done"
