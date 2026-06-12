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

# Root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "Script $(basename "$0") is already running"
    exit 1
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
# UNIFI HOTSPOT (ENTERPRISE) - comment this block if not using Unifi hotspot
# =============================================================================
UNIFI_HOTSPOT_ENABLED=false
hotspot_path="/etc/uhotspot"
# =============================================================================

if [ "$UNIFI_HOTSPOT_ENABLED" = true ]; then
    [ -d "$hotspot_path" ] || mkdir -p "$hotspot_path"
fi

# clean ACLs
: > "$block_list_day"
: > "$block_list_week"
: > "$block_list_month"

### BANDATA DAY (daily)
echo "Running Bandata Day..."
max_bandwidth_day="1G"
max_bw_day=$(LC_ALL=C numfmt --from=iec "${max_bandwidth_day/,/.}")
# path to day report
day_logs=$report/$(date +"%Y%m%d")
# bandata day rule
if [[ "$today" -eq 6 || "$today" -eq 7 ]]; then
    echo "Weekend Excluded"
else
    if [ ! -d "$day_logs" ]; then
        echo "Day report folder not found: $day_logs"
        : > "$block_list_day"
    else
        (
            cd "$day_logs"
            shopt -s nullglob
            for file in $range; do
                total=$(awk '$1=="total:" {print $2}' "$file")
                if [ -n "$total" ] && (( total > max_bw_day )); then
                    echo "$file"
                fi
            done
        ) | grep -wvf "$allow_list" | $reorganize | uniq > "$block_list_day"
    fi
    
    day_count=$(wc -l < "$block_list_day")
    if [ "$day_count" -gt 0 ]; then
        echo "Daily Blocked:"
        sed 's/^/    /' "$block_list_day"
    else
        echo "No daily blocks"
    fi
fi
echo "OK"

### BANDWIDTH WEEK (weekly MON-FRI)
echo "Running Bandata Week..."
max_bandwidth_week="5G"
max_bw_week=$(LC_ALL=C numfmt --from=iec "${max_bandwidth_week/,/.}")

if [ "$today" -eq 1 ]; then
    week_dirs=()
    for x in {0..4}; do
        d="$report/$(date -d "last monday +$x days" +'%Y%m%d')"
        [ -d "$d" ] && week_dirs+=("$d")
    done

    if [ ${#week_dirs[@]} -eq 0 ]; then
        echo "No weekday report folders found for last week"
        : > "$block_list_week"
    else
        folders=$(find "${week_dirs[@]}" -maxdepth 1 -type f -name "$range")
        totals=$(echo "$folders" | xargs -r -I {} awk '/^total:/{sub(".*/", "", FILENAME); print FILENAME" "$NF}' {})
        ips=$(echo "$totals" | awk '{ arr[$1]+=$2 } END { for (key in arr) printf("%s\t%s\n", arr[key], key) }' | sort -k1,1)
        echo "$ips" | awk -v max="$max_bw_week" '$1 > max {print $2}' | grep -wvf "$allow_list" | $reorganize | uniq > "$block_list_week"
    fi

    week_count=$(wc -l < "$block_list_week")
    if [ "$week_count" -gt 0 ]; then
        echo "Weekly Blocked:"
        sed 's/^/    /' "$block_list_week"
    else
        echo "No weekly blocks"
    fi
else
    echo "Weekly check runs on Monday only"
fi
echo "OK"

### BANDATA MONTH (monthly)
echo "Running Bandata Month..."
max_bandwidth_month="20G"
max_bw_month=$(LC_ALL=C numfmt --from=iec "${max_bandwidth_month/,/.}")

# Build weekday directories for current month (excluding weekends)
month_prefix=$(date +"%Y%m")
days_in_month=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%d)
month_dirs=()
for d in $(seq -w 1 "$days_in_month"); do
    day_path="$report/${month_prefix}${d}"
    [ -d "$day_path" ] || continue
    dow=$(date -d "${month_prefix:0:4}-${month_prefix:4:2}-${d}" +%u)
    [ "$dow" -ge 6 ] && continue
    month_dirs+=("$day_path")
done

if [ ${#month_dirs[@]} -eq 0 ]; then
    echo "No weekday report folders found for current month"
    : > "$block_list_month"
else
    folders=$(find "${month_dirs[@]}" -maxdepth 1 -type f -name "$range")
    totals=$(echo "$folders" | xargs -r -I {} awk '/^total:/{sub(".*/", "", FILENAME); print FILENAME" "$NF}' {})
    ips=$(echo "$totals" | awk '{ arr[$1]+=$2 } END { for (key in arr) printf("%s\t%s\n", arr[key], key) }' | sort -k1,1)
    echo "$ips" | awk -v max="$max_bw_month" '$1 > max {print $2}' | grep -wvf "$allow_list" | $reorganize | uniq > "$block_list_month"
fi

month_count=$(wc -l < "$block_list_month")
if [ "$month_count" -gt 0 ]; then
    echo "Monthly Blocked:"
    sed 's/^/    /' "$block_list_month"
else
    echo "No monthly blocks"
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
    echo "FINAL BAN SUMMARY:"
    ipset list bandata 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -V | while read ip; do
        # Check which category this IP belongs to
        if grep -q "^$ip$" $block_list_day 2>/dev/null; then
            cat_type="DAILY"
        elif grep -q "^$ip$" $block_list_week 2>/dev/null; then
            cat_type="WEEKLY"
        elif grep -q "^$ip$" $block_list_month 2>/dev/null; then
            cat_type="MONTHLY"
        else
            cat_type="UNKNOWN"
        fi
        echo "  $ip [$cat_type]"
    done

    echo ""
    echo "Applying Iptables Rules..."
    
    iptables -C FORWARD -i "$lan" -m set --match-set bandata src -p udp --dport 53 -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 1 -i "$lan" -m set --match-set bandata src -p udp --dport 53 -j ACCEPT

    iptables -C FORWARD -i "$lan" -m set --match-set bandata src -p tcp --dport 80 -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 2 -i "$lan" -m set --match-set bandata src -p tcp --dport 80 -j ACCEPT

    iptables -C FORWARD -i "$lan" -m set --match-set bandata src -p tcp --dport 18081 -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 3 -i "$lan" -m set --match-set bandata src -p tcp --dport 18081 -j ACCEPT

    iptables -C FORWARD -i "$lan" -m set --match-set bandata src -j DROP 2>/dev/null || \
    iptables -I FORWARD 4 -i "$lan" -m set --match-set bandata src -j DROP


    iptables -C INPUT -i "$lan" -m set --match-set bandata src -p tcp --dport 18081 -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -i "$lan" -m set --match-set bandata src -p tcp --dport 18081 -j ACCEPT

    iptables -C INPUT -i "$lan" -m set --match-set bandata src -j DROP 2>/dev/null || \
    iptables -I INPUT 2 -i "$lan" -m set --match-set bandata src -j DROP

    iptables -t nat -C PREROUTING -i "$lan" -m set --match-set bandata src -p tcp --dport 80 -j REDIRECT --to-port 18081 2>/dev/null || \
    iptables -t nat -I PREROUTING 1 -i "$lan" -m set --match-set bandata src -p tcp --dport 80 -j REDIRECT --to-port 18081

else
    echo "There are no IPs in bandata"
fi

echo "Done"
printf "\n"

# Generates realname.cfg and skipuser.cfg for Lightsquid reports.
# ACL format expected: a;MAC;IP;HOSTNAME;
# Output format: "IP HOSTNAME"
update_lightsquid_realname() {
    local realname=/var/www/proxymon/lightsquid/realname.cfg
    local skipuser=/var/www/proxymon/lightsquid/skipuser.cfg
    # Files to exclude from realname.cfg (sent to skipuser.cfg instead).
    # Use filenames only, space-separated. Empty string disables exclusion.
    local exclude_acls="mac-transparent.txt mac-unlimited.txt"

    # Extract "IP HOSTNAME" from ACL line "a;MAC;IP;HOSTNAME;"
    extract_ip_hostname() {
        awk -F';' 'NF >= 4 && $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $3, $4}'
    }

    # Check if a basename matches the exclude list (exact match, no regex)
    is_excluded() {
        local basename="$1"
        local f
        for f in $exclude_acls; do
            [ "$basename" = "$f" ] && return 0
        done
        return 1
    }

    process_hotspot() {
        [ -f "$hotspot_path/mac-hotspot.txt" ] || return
        awk -F';' '$3 != "0.0.0.0" && NF >= 4 {print $3, $4}' "$hotspot_path/mac-hotspot.txt"
    }

    process_acls() {
        local mode="$1"  # "include" or "exclude"
        local file
        find "$acl_mac_path" -maxdepth 1 -type f -iname 'mac-*' | while read -r file; do
            local bn
            bn=$(basename "$file")
            if [ "$mode" = "include" ]; then
                is_excluded "$bn" && continue
            else
                is_excluded "$bn" || continue
            fi
            extract_ip_hostname < "$file"
        done
    }

    local sort_ips="sort -u -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n"
    local hotspot_out="" acl_out skip_out

    if [ "$UNIFI_HOTSPOT_ENABLED" = true ]; then
        hotspot_out=$(process_hotspot)
    fi
    acl_out=$(process_acls include)
    skip_out=$(process_acls exclude)

    local final_output skip_output
    final_output=$(printf "%s\n%s\n" "$hotspot_out" "$acl_out" | sed '/^$/d' | $sort_ips)
    skip_output=$(printf "%s\n" "$skip_out" | sed '/^$/d' | $sort_ips)

    if [ -z "$final_output" ]; then
        echo "  No MAC data processed for realname.cfg"
    else
        echo "$final_output" > "$realname"
    fi

    if [ -z "$skip_output" ]; then
        echo "  No excluded data for skipuser.cfg"
    else
        echo "$skip_output" > "$skipuser"
    fi
}
# ==============================================================================
# EXECUTE FUNCTION (commented by default)
# ==============================================================================
# To enable Lightsquid realname generation, uncomment the line below:
#
#update_lightsquid_realname
