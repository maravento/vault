#!/bin/bash
# maravento.com

# BlackShield
# File Extensions/Patterns/User-Agents/Hex-String to Block

echo "Blackshield Start. Wait..."
printf "\n"

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

### VARIABLES
wgetd='wget -q -c --no-check-certificate --retry-connrefused --timeout=10 --tries=4'
output=

# Bad User-Agents
$wgetd bad-user-agents.list "https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/refs/heads/master/_generator_lists/bad-user-agents.list"
sed -E 's/\\//g; s#/#-#g' bad-user-agents.list >> acl/squid/blockua.txt
sort -o acl/squid/blockua.txt -u acl/squid/blockua.txt
rm -f bad-user-agents.list
echo "Bad User-Agents for Squid: blockua.txt"

# Ransomware
function rw() {
    curl -k -X GET --connect-timeout 10 --retry 1 -I "$1" &>/dev/null
    if [ $? -eq 0 ]; then
        $wgetd "$1" -O - >> source_lst.txt
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
grep -P '^[\x00-\x7F]*$' source_lst.txt | sed 's/^[^a-zA-Z0-9]*//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/[^a-zA-Z0-9]*$//' | sed '/ /d' | sed '/^$/d' | sort -u > acl/squid/output_lst.txt
rm -f source_lst.txt

# For Squid Extensions/Patterns
cat acl/squid/{output_lst,debug_lst}.txt | sed -E 's/^\*\.\?//; s/^/\\./; s/(.*)/\1([a-zA-Z][0-9]*)?(\\?.*)?$/' | sort -u > acl/squid/rwext.txt
echo "Ransomware ACL for Squid: rwext.txt"

# For Samba Veto Files
echo "veto files = $(cat acl/squid/{output_lst,debug_lst}.txt | sed 's/^/*./' | paste -sd '' - | sed 's/*/\/&/g; s/$/\//' | sort -u)" > acl/smb/ransom_veto.txt
echo "RansomwareACL for Samba: ransom_veto.txt"

rm -f acl/squid/{output_lst,debug_lst}.txt

echo "Done"
