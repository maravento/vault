#!/bin/bash
# by maravento.com

# Telemetry Block List

echo "Starting Telemetry Blocklist Update..."

# VARIABLES
debug=$(pwd)/debug
date=$(date +%d/%m/%Y" "%H:%M:%S)
regexd='([a-zA-Z0-9][a-zA-Z0-9-]{1,61}\.){1,}(\.?[a-zA-Z]{2,}){1,}'
wgetd='wget -q --show-progress -c --no-check-certificate --retry-connrefused --timeout=10 --tries=4'
xdesktop=$(xdg-user-dir DESKTOP)

# DELETE OLD REPOSITORY AND CREATE NEW
if [ -d $debug ]; then rm -rf $debug; fi
mkdir $debug && cd $debug

# DOWNLOAD
function urls() {
    $wgetd "$1" -O - >>updateurls.txt
}
urls 'https://gist.githubusercontent.com/changeme/a2e6aa686303eb47f3dc9f830fdae703/raw/24af43dd0fa9f920f10cdd5d2b3e74060596bf21/Mikrotik%2520-%2520Microsoft%2520telemetry%2520block' && sleep 1
urls 'https://gist.githubusercontent.com/JustinLloyd/f3609460e6ee14ca6a8a/raw/28bbbdb2a2810369da8c112e23e351c8300e1e78/hosts' && sleep 1
urls 'https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-blocklist.txt' && sleep 1
urls 'https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt' && sleep 1
urls 'https://raw.githubusercontent.com/AlexanderOnischuk/DeleteTelemetryWin10/master/DeleteTelemetryWin10.bat' && sleep 1
urls 'https://raw.githubusercontent.com/cedws/apple-telemetry/master/blacklist' && sleep 1
urls 'https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt' && sleep 1
urls 'https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy_v6.txt' && sleep 1
urls 'https://raw.githubusercontent.com/Forsaked/hosts/master/hosts' && sleep 1
urls 'https://raw.githubusercontent.com/Hurkamurka/Xiaomi-Telemetry-Blocklist-2/master/Xiaomi_Telemetry_paste.txt' && sleep 1
urls 'https://raw.githubusercontent.com/j-42/hosts/master/hosts' && sleep 1
urls 'https://raw.githubusercontent.com/kaabir/AdBlock_Hosts/master/hosts' && sleep 1
urls 'https://raw.githubusercontent.com/kevle1/Windows-Telemetry-Blocklist/master/windowsblock.txt' && sleep 1
urls 'https://raw.githubusercontent.com/kevle1/Xiaomi-Telemetry-Blocklist/master/xiaomiblock.txt' && sleep 1
urls 'https://raw.githubusercontent.com/mboutolleau/block-samsung-tv-telemetry/master/samsung_tv_telemetry_urls.txt' && sleep 1
urls 'https://raw.githubusercontent.com/root-host/Windows-Telemetry/master/domains3' && sleep 1
urls 'https://raw.githubusercontent.com/simeononsecurity/System-Wide-Windows-Ad-Blocker/main/Files/hosts.txt' && sleep 1
urls 'https://raw.githubusercontent.com/StevenBlack/hosts/master/data/add.2o7Net/hosts' && sleep 1
urls 'https://raw.githubusercontent.com/szotsaki/windows-telemetry-removal/master/WindowsTelemetryRemoval.bat' && sleep 1
urls 'https://raw.githubusercontent.com/W4RH4WK/Debloat-Windows-10/master/scripts/block-telemetry.ps1' && sleep 1
urls 'https://v.firebog.net/hosts/Easyprivacy.txt' && sleep 1
urls 'https://v.firebog.net/hosts/Prigent-Ads.txt' && sleep 1

# CAPTURING TELEMETRY DOMAINS
cd ..
find $debug -type f -execdir grep -oiE "$regexd" {} \; | sed '/[A-Z]/d' | sed '/0--/d' | sed -r '/[^a-zA-Z0-9.-]/d' | sed -r 's:(^\.*?(www|ftp|xxx|wvw)[^.]*?\.|^\.\.?)::gi' | awk '{print "."$1}' | sed -r '/^\.\W+/d' | sort -u >telemetry.txt
rm -rf $debug
echo "Done"
