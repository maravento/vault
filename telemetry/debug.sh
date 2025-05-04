#!/bin/bash
# maravento.com

# Telemetry Block List

echo "Telemetry Blocklist Update..."

# VARIABLES
debug=$(pwd)/debug
regexd='([a-zA-Z0-9][a-zA-Z0-9-]{1,61}\.){1,}(\.?[a-zA-Z]{2,}){1,}'
wgetd='wget -q --show-progress -c --no-check-certificate --retry-connrefused --timeout=10 --tries=4'

# DELETE OLD REPOSITORY AND CREATE NEW
if [ -d $debug ]; then rm -rf $debug; fi
mkdir $debug && cd $debug

# DOWNLOAD TELEMETRY
function urls() {
    $wgetd "$1" -O - >> urls
}
    urls 'https://gist.githubusercontent.com/changeme/a2e6aa686303eb47f3dc9f830fdae703/raw/24af43dd0fa9f920f10cdd5d2b3e74060596bf21/Mikrotik%2520-%2520Microsoft%2520telemetry%2520block' && sleep 1
    urls 'https://gist.githubusercontent.com/JustinLloyd/f3609460e6ee14ca6a8a/raw/28bbbdb2a2810369da8c112e23e351c8300e1e78/hosts' && sleep 1
    urls 'https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-blocklist.txt' && sleep 1
    urls 'https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt' && sleep 1
    urls 'https://perflyst.github.io/PiHoleBlocklist/AmazonFireTV.txt' && sleep 1
    urls 'https://perflyst.github.io/PiHoleBlocklist/android-tracking.txt' && sleep 1
    urls 'https://perflyst.github.io/PiHoleBlocklist/SessionReplay.txt' && sleep 1
    urls 'https://perflyst.github.io/PiHoleBlocklist/SmartTV-AGH.txt' && sleep 1
    urls 'https://perflyst.github.io/PiHoleBlocklist/SmartTV.txt' && sleep 1
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
find $debug -type f -execdir grep -oiE "$regexd" {} \; | sed '/[A-Z]/d' | sed '/0--/d' | sed -r '/[^a-zA-Z0-9.-]/d' | sed -r 's:(^\.*?(www|ftp|xxx|wvw)[^.]*?\.|^\.\.?)::gi' | awk '{print "."$1}' | sed -r '/^\.\W+/d' | sort -u > capture
rm -rf $debug
echo "OK"

# DOWNLOAD TLDs
echo "Download TLDs..."
$wgetd https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/sourcetlds.txt
function publicsuffix() {
    curl -k -X GET --connect-timeout 10 --retry 1 -I "$1" &>/dev/null
    if [ $? -eq 0 ]; then
        $wgetd "$1" -O - >> sourcetlds.txt
    else
        echo ERROR "$1"
    fi
}
    publicsuffix 'https://raw.githubusercontent.com/publicsuffix/list/master/public_suffix_list.dat'
    publicsuffix 'https://data.iana.org/TLD/tlds-alpha-by-domain.txt'
    publicsuffix 'https://www.whoisxmlapi.com/support/supported_gtlds.php'
echo "OK"

# DEBUGGING TLDS
echo "Debugging TLDs..."
$wgetd https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/tools/parse_domain_tld.py
grep -v "//"  sourcetlds.txt | sed '/^$/d; /#/d' | grep -v -P "[^a-z0-9_.-]" | sed 's/^\.//' | awk '{print "." $1}' | sort -u > tlds.txt
grep -Fvxf <(cat tlds.txt) <(python parse_domain_tld.py | awk '{print "." $1}') | sort -u > out.txt
echo "OK"

echo "DNS Lockup..."
# DNS LOCKUP
# FAULT: Unexist/Fail domain
# HIT: Exist domain
# pp = parallel processes (high resource consumption!)
pp="200"

sed 's/^\.//g' out.txt | sort -u > step
if [ -s dnslookup ]; then
    awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup step
else
    cat step
fi | xargs -I {} -P "$pp" sh -c "if host {} >/dev/null; then echo HIT {}; else echo FAULT {}; fi" >> dnslookup
sed '/^FAULT/d' dnslookup | awk '{print $2}' | awk '{print "." $1}' > hit.txt
sed '/^HIT/d' dnslookup | awk '{print $2}' | awk '{print "." $1}' >> fault.txt
sort -u hit.txt > telemetry.txt

echo "Done"
