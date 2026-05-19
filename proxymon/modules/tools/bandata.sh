#!/bin/bash
# maravento.com

# Bandata for Squid Reports
# Data Plan for LocalNet

# Instructions:
# Default: max 1G (GBytes) day / 5G (GBytes) week / 20G (GBytes) month
# Adjust the variable "max_bandwidth_*", according to your needs
# Can use fractions. Eg: 0.3G, 1.0G, 2.9G etc
# Can use M (MBytes), B (Bytes) or G (GBytes). Eg: 50M, 1G etc
# bandata excludes weekends

printf "\n"
echo "Bandata for Squid Reports Start. Wait..."
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

### VARIABLES
# replace interface (e.g: enpXsX)
lan="eth1"
# server IP
serverip="192.168.0.10"
# range
range="192.168.0*"
# today
today=$(date +"%u")
# reorganize IP
reorganize="sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n"
# path to reports
report=/var/www/proxymon/lightsquid/report
# path to ACLs folder
acl_path=/etc/acl
acl_mac_path="$acl_path/acl_mac"
acl_squid_path="$acl_path/acl_squid"
acl_bandata_path="$acl_path/acl_bandata"
# Create main folder if doesn't exist
if [ ! -d "$acl_path" ]; then 
    mkdir -p "$acl_path"
fi
# Create subdirectories if they don't exist
[ -d "$acl_mac_path" ] || mkdir -p "$acl_mac_path"
[ -d "$acl_bandata_path" ] || mkdir -p "$acl_bandata_path"
# path to ACLs files
allow_list=$acl_bandata_path/allowdata.txt
block_list_day=$acl_bandata_path/banday.txt
block_list_week=$acl_bandata_path/banweek.txt
block_list_month=$acl_bandata_path/banmonth.txt
# Create ACLs files if doesn't exist
touch "$allow_list" "$block_list_day" "$block_list_week" "$block_list_month"

# =============================================================================
# UNIFI HOTSPOT (ENTERPRISE) — comment this block if not using Unifi hotspot
# =============================================================================
UNIFI_HOTSPOT_ENABLED=false
hotspot_path="/etc/unhotspot"
# =============================================================================

if [ "$UNIFI_HOTSPOT_ENABLED" = true ]; then
    [ -d "$hotspot_path" ] || mkdir -p "$hotspot_path"
fi

# clean ACLs
block_files=($block_list_day $block_list_week $block_list_month)
for file in "${block_files[@]}"; do
    if [ -f "$file" ]; then
        cat /dev/null > "$file" 2>/dev/null
    fi
done

### BANDATA DAY (daily)
echo "Running Bandata Day..."
max_bandwidth_day="1G"
max_bw_day=$(echo "$max_bandwidth_day" | tr '.' ',' | numfmt --from=iec)
# path to day report
day_logs=$report/$(date +"%Y%m%d")
# bandata day rule
if [[ "$today" -eq 6 || "$today" -eq 7 ]]; then
    echo "  ⏸️  Weekend Excluded"
    cat /dev/null >$block_list_day
else
    (
        cd $day_logs
        for file in $range; do
            if (($(awk <$file '/^total/ {print($2)}') > $max_bw_day)); then
                echo $file
            fi
        done
    ) >banout_day
    cat banout_day | grep -wvf $allow_list | $reorganize | uniq >$block_list_day
    
    day_count=$(wc -l < $block_list_day)
    if [ "$day_count" -gt 0 ]; then
        echo "  ⛔ Daily Blocked:"
        cat $block_list_day | sed 's/^/    /'
    else
        echo "  ✅ No daily blocks"
    fi
fi
echo "OK"

### BANDWIDTH WEEK (weekly MON-FRI)
echo "Running Bandata Week..."
max_bandwidth_week="5G"
max_bw_week=$(echo $max_bandwidth_week | tr '.' ',' | numfmt --from=iec)

if [ "$today" -eq 1 ]; then
    week_logs="$report/$(date -d "last monday" +"%Y%m%d")"
    weekday_logs=$(for x in {0..4}; do
        date -d "last monday +$x days" +'%Y%m%d'
    done)
    folders=$(find "$report" -type f | grep -F -f <(echo -e "$weekday_logs"))
    totals=$(echo "$folders" | xargs -I {} awk '/^total:/{sub(".*/", "", FILENAME); print FILENAME" "$NF}' {})
    ips=$(echo "$totals" | awk '{ arr[$1]+=$2 } END { for (key in arr) printf("%s\t%s\n", arr[key], key) }' | sort -k1,1)
    echo "$ips" | awk -v max_bw_week="$max_bw_week" '$1 > max_bw_week {print $2}' | grep -wvf "$allow_list" | $reorganize | uniq >"$block_list_week"
    
    week_count=$(wc -l < $block_list_week)
    if [ "$week_count" -gt 0 ]; then
        echo "  ⛔ Weekly Blocked:"
        cat $block_list_week | sed 's/^/    /'
    else
        echo "  ✅ No weekly blocks"
    fi
else
    echo "  ⏸️  Weekly check runs on Monday only"
fi
echo "OK"
### BANDATA MONTH (monthly)
echo "Running Bandata Month..."
max_bandwidth_month="20G"
max_bw_month=$(echo $max_bandwidth_month | tr '.' ',' | numfmt --from=iec)
# path to month report
month_logs=$report/$(date +"%Y%m"*)
weekend_logs=$(
    for x in $(seq 0 9); do
        date -d "$x sun 5 week ago" +'%b %Y%m%d'
        date -d "$x sat 5 week ago" +'%b %Y%m%d'
    done | grep $(date +%b) | awk '{print $2}'
)
folders=$(find $month_logs -type f | grep -vf <(echo "$weekend_logs"))
totals=$(echo "$folders" | xargs -I {} awk '/^total:/{sub(".*/", "", FILENAME); print FILENAME" "$NF}' {})
ips=$(echo "$totals" | awk '{ arr[$1]+=$2 } END { for (key in arr) printf("%s\t%s\n", arr[key], key) }' | sort -k1,1)
echo "$ips" | awk '$1 > '$max_bw_month' {print $2}' | grep -wvf $allow_list | $reorganize | uniq >$block_list_month

month_count=$(wc -l < $block_list_month)
if [ "$month_count" -gt 0 ]; then
    echo "  ⛔ Monthly Blocked:"
    cat $block_list_month | sed 's/^/    /'
else
    echo "  ✅ No monthly blocks"
fi
echo "OK"

### IPSET/IPTABLES FOR BANDATA
echo "Running Ipset/Iptables Rules..."
ipset -L bandata >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ipset -! create bandata hash:net family inet hashsize 1024 maxelem 65536
else
    ipset -! flush bandata
fi

# NAT
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

# Load IPs to bandata
all_bans=$(cat $block_list_day $block_list_week $block_list_month | $reorganize | uniq)

if [ -n "$all_bans" ]; then
    for ip in $all_bans; do
        ipset -exist add bandata "$ip"
    done
    
    echo ""
    echo "📊 FINAL BAN SUMMARY:"
    echo "===================="
    ipset list bandata 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -V | while read ip; do
        # Check which category this IP belongs to
        if grep -q "^$ip$" $block_list_day 2>/dev/null; then
            cat_type="DAILY  "
        elif grep -q "^$ip$" $block_list_week 2>/dev/null; then
            cat_type="WEEKLY "
        elif grep -q "^$ip$" $block_list_month 2>/dev/null; then
            cat_type="MONTHLY"
        else
            cat_type="UNKNOWN"
        fi
        echo "  $ip [$cat_type]"
    done

    echo ""
    echo "Applying Iptables Rules..."
    
    iptables -I FORWARD 1 -i $lan -m set --match-set bandata src -p udp --dport 53 -j ACCEPT
    iptables -I FORWARD 2 -i $lan -m set --match-set bandata src -p tcp --dport 80 -j ACCEPT
    iptables -I FORWARD 3 -i $lan -m set --match-set bandata src -p tcp --dport 18081 -j ACCEPT
    iptables -I FORWARD 4 -i $lan -m set --match-set bandata src -j DROP 
    
    iptables -I INPUT 1 -i $lan -m set --match-set bandata src -p tcp --dport 18081 -j ACCEPT
    iptables -I INPUT 2 -i $lan -m set --match-set bandata src -j DROP
    
    iptables -t nat -I PREROUTING 1 -i $lan -m set --match-set bandata src -p tcp --dport 80 -j REDIRECT --to-port 18081

else
    echo "✅ There are no IPs in bandata"
fi

echo "Done"
printf "\n"

# ==============================================================================
# FUNCTION: update_lightsquid_realname
# ==============================================================================
# Generates realname.cfg and skipuser.cfg for Lightsquid reports.
#
# Reads MAC-based ACL files from $acl_mac_path (format: IP;MAC;HOSTNAME) and
# maps IP addresses to hostnames. Excluded ACLs are written to skipuser.cfg.
#
# If UNIFI_HOTSPOT_ENABLED=true, also processes mac-hotspot.txt
# (format: a;MAC;IP;HOSTNAME;END_TIME_EPOCH) from $hotspot_path.
#
# OUTPUT:
#     realname.cfg  → "IP HOSTNAME" (included users)
#     skipuser.cfg  → "IP HOSTNAME" (excluded users)
#
# EXCLUDE ACLS:
#     The variable 'exclude_acls' defines which ACL files are excluded from
#     realname.cfg and redirected to skipuser.cfg instead.
#     Example: exclude_acls="$acl_mac_path/mac-transparent.txt $acl_mac_path/mac-unlimited.txt"
#
# To enable this feature, uncomment the call at the end of the script:
#     update_lightsquid_realname
# ==============================================================================

# UPDATE REALNAME FOR LIGHTSQUID DATA SET
update_lightsquid_realname() {
    realname=/var/www/proxymon/lightsquid/realname.cfg
    skipuser=/var/www/proxymon/lightsquid/skipuser.cfg
    # Define ACLs to exclude from reports (set to empty string if none). Example:
    # exclude_acls=""
    # exclude_acls="file1.txt"
    # exclude_acls="file1.txt file2.txt file3.txt"
    exclude_acls="$acl_mac_path/mac-transparent.txt $acl_mac_path/mac-unlimited.txt"

    process_hotspot() {
        [ -f "$hotspot_path/mac-hotspot.txt" ] || return
        awk -F';' '
            $3 != "0.0.0.0" {
                print $3, $4
            }
        ' "$hotspot_path/mac-hotspot.txt"
    }

    process_acl_debug() {
        if find $acl_mac_path -maxdepth 1 -type f -iname 'mac-*' | grep -q .; then
            if [ -n "$exclude_acls" ]; then
                exclude_pattern=$(echo "$exclude_acls" | sed 's/ /|/g')
                find $acl_mac_path -maxdepth 1 -type f -iname 'mac-*' \
                | grep -vE "$exclude_pattern" \
                | xargs cat 2>/dev/null
            else
                find $acl_mac_path -maxdepth 1 -type f -iname 'mac-*' -exec cat {} + 2>/dev/null
            fi \
            | cut -d";" -f3- \
            | sed -r 's/[;]+/ /g'
        fi
    }

    process_skipuser() {
        if [ -n "$exclude_acls" ]; then
            exclude_pattern=$(echo "$exclude_acls" | sed 's/ /|/g')
            find $acl_mac_path -maxdepth 1 -type f -iname 'mac-*' \
            | grep -E "$exclude_pattern" \
            | xargs cat 2>/dev/null \
            | cut -d";" -f3- \
            | sed -r 's/[;]+/ /g'
        fi
    }

    hotspot_out=""
    if [ "$UNIFI_HOTSPOT_ENABLED" = true ]; then
        hotspot_out=$(process_hotspot | sort -V)
    fi

    acl_out=$(process_acl_debug | sort -V)
    skip_out=$(process_skipuser | sort -V)

    final_output=$( {
        echo "$hotspot_out"
        echo "$acl_out"
    } | sed '/^$/d' | sort -n -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n | uniq )

    skip_output=$(echo "$skip_out" | sed '/^$/d' | sort -n -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n | uniq)

    if [ -z "$final_output" ]; then
        echo "  ℹ️  No MAC data processed for realname.cfg"
    else
        echo "$final_output" > "$realname"
    fi

    if [ -z "$skip_output" ]; then
        echo "  ℹ️  No excluded data for skipuser.cfg"
    else
        echo "$skip_output" > "$skipuser"
    fi
}
# ==============================================================================
# EXECUTE FUNCTION (commented by default)
# ==============================================================================
# To enable Lightsquid realname generation, uncomment the line below:
#
# update_lightsquid_realname
