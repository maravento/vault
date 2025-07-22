#!/bin/bash
# maravento.com

# Bandata for LightSquid
# Data Plan for LocalNet
# https://www.maravento.com/2022/10/lightsquid.html

# Instructions:
# Default: max 1G (GBytes) day / 5G (GBytes) week / 20G (GBytes) month
# Adjust the variable "max_bandwidth_*", according to your needs
# Can use fractions. Eg: 0.3G, 1.0G, 2.9G etc
# Can use M (MBytes), B (Bytes) or G (GBytes). Eg: 50M, 1G etc
# bandata excludes weekends

echo "Bandata for LightSquid Start. Wait..."
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
range="192.168*"
# today
today=$(date +"%u")
# reorganize IP
reorganize="sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n"
# path to reports
report=/var/www/lightsquid/report
# path to ACLs folder
aclroute=/etc/acl
# Create folder if doesn't exist
if [ ! -d $aclroute ]; then mkdir -p $aclroute; fi &>/dev/null
# path to ACLs files
allow_list=$aclroute/allowdata.txt
block_list_day=$aclroute/banday.txt
block_list_week=$aclroute/banweek.txt
block_list_month=$aclroute/banmonth.txt
# Create ACLs files if doesn't exist
if [[ ! -f {$allow_list,$block_list_day,$block_list_week,$block_list_month} ]]; then touch {$allow_list,$block_list_day,$block_list_week,$block_list_month}; fi

### BANDATA DAY (1G daily)
echo "Running Bandata Day..."
max_bandwidth_day="1G"
max_bw_day=$(echo "$max_bandwidth_day" | tr '.' ',' | numfmt --from=iec)
# path to day report
day_logs=$report/$(date +"%Y%m%d")
# bandata day rule
if [[ "$today" -eq 6 || "$today" -eq 7 ]]; then
    echo "Weekend Excluded"
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
fi
echo "OK"

### BANDWIDTH WEEK (5G weekly MON-FRI)
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
fi
echo "OK"

### BANDATA MONTH (20G monthly = 5G weekly x 4 weeks)
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
echo "OK"

### IPSET/IPTABLES FOR BANDATA
echo "Running Ipset/Iptables Rules..."
ipset -L bandata >/dev/null 2>&1
if [ $? -ne 0 ]; then
    ipset -! create bandata hash:net family inet hashsize 1024 maxelem 65536
else
    ipset -! flush bandata
fi

# Load IPs to bandata
all_bans=$(cat $block_list_day $block_list_week $block_list_month | $reorganize | uniq)

if [ -n "$all_bans" ]; then
    echo "$all_bans" | while read ip; do
        ipset -! add bandata "$ip"
        ipset list bandata | sed -n '/Members:/,/^$/p' | sed '/^$/d'
    done

    echo "Applying iptables rules..."

    # NAT
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    # Allow HTTP Virtualhost (18880/TCP)
    iptables -I INPUT -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 18880 -j ACCEPT
    iptables -I FORWARD -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 18880 -j ACCEPT
    iptables -I INPUT -p tcp -s $serverip --sport 18880 -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -I FORWARD -p tcp -s $serverip --sport 18880 -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Allow HTTPs Virtualhost (18443/TCP) - Optional -
    #iptables -I INPUT -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 18880 -j ACCEPT
    #iptables -I FORWARD -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 18880 -j ACCEPT
    #iptables -I INPUT -p tcp -s $serverip --sport 18443 -m state --state ESTABLISHED,RELATED -j ACCEPT
    #iptables -I FORWARD -p tcp -s $serverip --sport 18443 -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Allow DNS (53/UDP)
    iptables -I INPUT -i $lan -m set --match-set bandata src -p udp --dport 53 -j ACCEPT
    iptables -I FORWARD -i $lan -m set --match-set bandata src -p udp --dport 53 -j ACCEPT
    # Redirect HTTP (80,8080/TCP) Proxy (Squid 3128)
    iptables -t nat -I PREROUTING -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 80,8080,3128 -j DNAT --to-destination $serverip:18880
    # Soft Block: DoT (TCP/853), HTTPs (TCP/443)
    iptables -I INPUT -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 853,443 -j REJECT --reject-with tcp-reset
    iptables -I FORWARD -i $lan -m set --match-set bandata src -p tcp -m multiport --dports 853,443 -j REJECT --reject-with tcp-reset
    # Hard Drop: all for bandata
    #iptables -I INPUT -i $lan -m set --match-set bandata src -j DROP
    #iptables -I FORWARD -i $lan -m set --match-set bandata src -j DROP
    iptables -I FORWARD -i $lan -m set --match-set bandata src -j LOG --log-prefix "BANDATA: "
else
    echo "There are no IPs in bandata"
fi

# Update realname config file (optional)
realname=/var/www/lightsquid/realname.cfg
find $aclroute -maxdepth 1 -type f -iname 'mac-*' ! -iname 'mac-unlimited.txt' -exec cat {} + | cut -d";" -f3- | sed -r 's/[;]+/ /g' | sort -n -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4 > $realname
echo "Done"
