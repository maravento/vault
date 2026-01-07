#!/bin/bash
# maravento.com

#========================================
# SQUID ANALYSIS TOOL
# squidtools.sh
#========================================
# This script provides a unified interface for analyzing Squid proxy logs.
# It contains five main functions:
#
# 1) squid_filter
#    - Allows the user to search the Squid access log for a specific IP
#      and/or keyword.
#    - Converts numeric timestamps in the log to human-readable dates.
#    - Results are saved to squid_filter.log in the current directory.
#
# 2) squid_audit
#    - Searches the Squid cache log for events where "clientAccessCheckDone" occurred.
#    - Converts numeric timestamps to human-readable dates.
#    - Requires debug_options "ALL,1 33,2 28,9" to be enabled in squid.conf.
#      If not enabled, the function exits with an informative error.
#    - Results are saved to squid_audit.log in the current directory.
#
# 3) squid_traffic
#    - Generates a traffic report from the Squid access log for a specified
#      analysis period (default 72 hours).
#    - Lists IP addresses and the number of hits to external domains.
#    - Flags IPs exceeding a configurable alert threshold.
#    - Results are saved to squid_traffic.log in the current directory.
#
# 4) squid_global
#    - Exports comprehensive Squid access log data to CSV format for a specified
#      analysis period (default 72 hours).
#    - Includes detailed fields: date, time, IP, method, HTTP code, size, cache status,
#      URL, domain, status classification, and error type categorization.
#    - Results are saved to squid_global.csv in the current directory.
#
# 5) squid_stats
#    - Generates comprehensive statistics and analytics from the Squid access log
#      for a specified analysis period (default 72 hours).
#    - Produces detailed metrics including performance data, cache hit rates, status
#      code analysis, bandwidth usage, top clients/domains, and error analysis.
#    - Generates both CSV (squid_stats.csv) and HTML (squid_stats.html) reports.
#
# All logs are written to the current working directory, and the script
# informs the user where to find the output files after execution.

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

# DEPENDENCY CHECK
# Check if Squid (basic or OpenSSL version) is installed
if ! dpkg -s squid &>/dev/null && ! dpkg -s squid-openssl &>/dev/null; then
  echo "❌ 'Squid (basic or OpenSSL version)' is not installed. Run:"
  echo "sudo apt install squid or sudo apt install squid-openssl"
  exit 1
fi

# Check other dependencies
DEPENDENCIES="perl"
for pkg in $DEPENDENCIES; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    echo "❌ '$pkg' is not installed. Run:"
    echo "sudo apt install $pkg"
    exit 1
  fi
done

# LOG FILE CHECK
# Modified to include all log files (current and rotated)
ACCESS_LOG="/var/log/squid/access.log*"
CACHE_LOG="/var/log/squid/cache.log*"

# Verify at least one access log file exists
if ! ls /var/log/squid/access.log* 1> /dev/null 2>&1; then
    echo "❌ Access log not found: /var/log/squid/access.log*"
    exit 1
fi

# Verify at least one cache log file exists
if ! ls /var/log/squid/cache.log* 1> /dev/null 2>&1; then
    echo "❌ Cache log not found: /var/log/squid/cache.log*"
    exit 1
fi

# TIMING
SCRIPT_START=$(date +%s)

# FUNCTIONS
squid_filter() {
    LOG_FILE="squid_filter.log"
    echo "=== Squid Filter ===" > "$LOG_FILE"

    read -p "Enter IP (e.g. 192.168.0.10) or leave empty: " IP
    read -p "Enter the word to search (e.g. google): " WORD

    IPNEW=$(echo "$IP" | grep -E '^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$')

    if [[ "$IPNEW" ]]; then
        cat $ACCESS_LOG 2>/dev/null | perl -pe 's/[\d\.]+/localtime($&)/e' \
        | grep "$IPNEW" \
        | grep -i -E "$WORD" >> "$LOG_FILE"
    else
        cat $ACCESS_LOG 2>/dev/null | perl -pe 's/[\d\.]+/localtime($&)/e' \
        | grep -i -E "$WORD" >> "$LOG_FILE"
    fi

    if [ $? -gt 0 ]; then
        echo "No records found for: $WORD" >> "$LOG_FILE"
    else
        echo "Done" >> "$LOG_FILE"
    fi

    echo "Results saved to $(pwd)/$LOG_FILE"
}

squid_audit() {
    LOG_FILE="squid_audit.log"
    echo "=== Squid Audit ===" > "$LOG_FILE"

    # Check debug_options in squid.conf
    SQUID_CONF="/etc/squid/squid.conf"  # Adjust for your system
    REQUIRED_DEBUG="ALL,1 33,2 28,9"

    if ! grep -q "^debug_options\s\+$REQUIRED_DEBUG" "$SQUID_CONF"; then
        echo "❌ ERROR: debug_options $REQUIRED_DEBUG is not enabled in $SQUID_CONF" | tee -a "$LOG_FILE"
        echo "Please enable this line and restart Squid before running this script." >> "$LOG_FILE"
        echo "Results saved to $(pwd)/$LOG_FILE"
        return
    fi

    read -p "Enter the word to search (e.g.: video): " WORD

    cat $CACHE_LOG 2>/dev/null | perl -pe 's/[\d\.]+/localtime($&)/e' \
    | grep -i "clientAccessCheckDone" \
    | grep -i -E "$WORD" >> "$LOG_FILE"

    if [ $? -gt 0 ]; then
        echo "No records found for: $WORD" >> "$LOG_FILE"
    else
        echo "Done" >> "$LOG_FILE"
    fi

    echo "Results saved to $(pwd)/$LOG_FILE"
}

squid_traffic() {
    # Ask user for period
    read -p "Enter the number of hours to analyze (default 72): " USER_HOURS
    PERIOD_HOURS=${USER_HOURS:-72}

    # Variables specific to this block
    MIN_HITS=${MIN_HITS:-20}
    ALERT_THRESHOLD=${ALERT_THRESHOLD:-300}
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    LOG_FILE="$SCRIPT_DIR/squid_traffic.log"

    # Initialize log file
    echo "============================================================" > "$LOG_FILE"
    echo "           SQUID TRAFFIC ANALYSIS REPORT" >> "$LOG_FILE"
    echo "============================================================" >> "$LOG_FILE"
    echo "Analysis started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "Configuration:" >> "$LOG_FILE"
    echo "  • Minimum hits   : $MIN_HITS" >> "$LOG_FILE"
    echo "  • Alert threshold: $ALERT_THRESHOLD" >> "$LOG_FILE"
    echo "  • Analysis period: ${PERIOD_HOURS}H" >> "$LOG_FILE"
    echo "  • Access log     : /var/log/squid/access.log* (all files)" >> "$LOG_FILE"
    echo "------------------------------------------------------------" >> "$LOG_FILE"
    printf "%-8s %-15s %-60s\n" "Hits" "IP" "URL" >> "$LOG_FILE"
    echo "------------------------------------------------------------" >> "$LOG_FILE"

    # Verify access log exists
    if ! ls /var/log/squid/access.log* 1> /dev/null 2>&1; then
        echo "❌ ERROR: Access log file not found: /var/log/squid/access.log*" | tee -a "$LOG_FILE"
        echo "Results saved to $LOG_FILE"
        return
    fi

    # Calculate cutoff timestamp
    NOW=$(date +%s)
    PERIOD=$((PERIOD_HOURS*3600))
    CUTOFF=$((NOW - PERIOD))

    # Generate traffic report
    cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {
        match($7, /https?:\/\/([^\/]+)/, arr)
        if (arr[1] != "") print $3, arr[1]
    }' \
    | sort \
    | uniq -c \
    | sort -nr \
    | awk -v min="$MIN_HITS" '{if($1>=min) printf "%-8s %-15s %-60s\n", $1, $2, $3}' \
    >> "$LOG_FILE"

    # Check for alerts
    ALERT_IPS=$(awk -v th="$ALERT_THRESHOLD" '$1 >= th {print $0}' "$LOG_FILE")
    if [[ -n "$ALERT_IPS" ]]; then
        ALERT_COUNT=$(echo "$ALERT_IPS" | wc -l)
        ALERT_MSG="🚨 ALERT: $ALERT_COUNT IP(s) exceed threshold of $ALERT_THRESHOLD hits"
        echo -e "$ALERT_MSG" | tee -a "$LOG_FILE"
    else
        INFO_MSG="✅ No IPs exceed the alert threshold of $ALERT_THRESHOLD hits"
        echo -e "$INFO_MSG" | tee -a "$LOG_FILE"
    fi

    echo "Results saved to $LOG_FILE"
}

squid_global() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CSV_FILE="$SCRIPT_DIR/squid_global.csv"

    echo "⚠️  WARNING: Generating this CSV may take some time depending on log size."
    read -p "Enter the number of hours to analyze (default 72): " PERIOD_HOURS
    PERIOD_HOURS=${PERIOD_HOURS:-72}

    if ! ls /var/log/squid/access.log* 1> /dev/null 2>&1; then
        echo "❌ ERROR: Access log not found: /var/log/squid/access.log*"
        return
    fi

    START=$(date +%s)
    NOW=$(date +%s)
    PERIOD=$((PERIOD_HOURS * 3600))
    CUTOFF=$((NOW - PERIOD))

    echo "⏳ Starting CSV export..."
    echo "date,time,ip,method,http_code,size,cache_status,url,domain,status,error_type" > "$CSV_FILE"

    cat $ACCESS_LOG 2>/dev/null | gawk -v cutoff="$CUTOFF" '
    function extract_domain(u,    d, h) {
        if (u == "" || u == "-")
            return "-"
        if (u ~ /^https?:\/\//) {
            delete d
            if (match(u, /https?:\/\/([^\/:]+)/, d))
                return d[1]
            else
                return u
        }
        if (u ~ /^[^\/:]+:[0-9]+$/) {
            split(u, h, ":")
            return h[1]
        }
        return u
    }

    $1 > cutoff {
        dt = strftime("%Y-%m-%d,%H:%M:%S", $1)
        ip = $3
        code = $4
        size = $5
        method = $6
        url = $7
        cache = $9

        split(code, c, "/")
        status_code = c[2]
        if (status_code == "") status_code = "000"
        if (method == "-") method = "UNKNOWN"

        # Classify error types
        if (status_code == "000") {
            status = "ERROR"
            error_type = "CONNECTION_FAIL"
        } else if (status_code >= 400) {
            status = "ERROR"
            error_type = "HTTP_ERROR"
        } else {
            status = "OK"
            error_type = "-"
        }

        domain = extract_domain(url)
        print dt","ip","method","status_code","size","cache","url","domain","status","error_type
    }' >> "$CSV_FILE"

    echo "✅ CSV export completed: $CSV_FILE"
}

squid_stats() {
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CSV_FILE="$SCRIPT_DIR/squid_stats.csv"
    HTML_FILE="$SCRIPT_DIR/squid_stats.html"

    echo "⚠️  WARNING: Generating stats may take some time depending on log size."
    read -p "Enter the number of hours to analyze (default 72): " PERIOD_HOURS
    PERIOD_HOURS=${PERIOD_HOURS:-72}

    if ! ls /var/log/squid/access.log* 1> /dev/null 2>&1; then
        echo "❌ ERROR: Access log not found: /var/log/squid/access.log*"
        return
    fi

    START=$(date +%s)
    NOW=$(date +%s)
    PERIOD=$((PERIOD_HOURS * 3600))
    CUTOFF=$((NOW - PERIOD))

    echo "⏳ Generating comprehensive statistics..."
    echo "Metric,Value" > "$CSV_FILE"

    # === BASIC METRICS ===
    TOTAL_REQUESTS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff' | wc -l)
    UNIQUE_IPS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {print $3}' | sort -u | wc -l)
    UNIQUE_DOMAINS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {print $7}' | sed -E 's#^https?://([^/:]+).*#\1#' | sort -u | wc -l)
    DATA_MB=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {sum+=$5} END {printf "%.2f", sum/1048576}')
    DATA_GB=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {sum+=$5} END {printf "%.2f", sum/1073741824}')

    # === STATUS CODE ANALYSIS ===
    SUCCESS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && $4 ~ /\/200/' | wc -l)
    REDIRECTS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && $4 ~ /\/30[0-9]/' | wc -l)
    CLIENT_ERRORS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && $4 ~ /\/40[0-9]/' | wc -l)
    SERVER_ERRORS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && $4 ~ /\/50[0-9]/' | wc -l)
    CACHE_HITS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && $4 ~ /HIT/' | wc -l)
    CACHE_MISS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && $4 ~ /MISS/' | wc -l)

    # === PERCENTAGES ===
    SUCCESS_PCT=$(awk -v s="$SUCCESS" -v t="$TOTAL_REQUESTS" 'BEGIN {if (t>0) printf "%.2f", (s/t)*100; else print 0}')
    CACHE_HIT_PCT=$(awk -v h="$CACHE_HITS" -v t="$TOTAL_REQUESTS" 'BEGIN {if (t>0) printf "%.2f", (h/t)*100; else print 0}')
    ERROR_PCT=$(awk -v e="$((CLIENT_ERRORS + SERVER_ERRORS))" -v t="$TOTAL_REQUESTS" 'BEGIN {if (t>0) printf "%.2f", (e/t)*100; else print 0}')

    # === PERFORMANCE METRICS ===
    AVG_RESPONSE_SIZE=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {sum+=$5; count++} END {if (count>0) printf "%.2f", sum/count/1024; else print 0}')
    REQ_PER_HOUR=$(awk -v t="$TOTAL_REQUESTS" -v h="$PERIOD_HOURS" 'BEGIN {printf "%.0f", t/h}')
    BANDWIDTH_MBPS=$(awk -v mb="$DATA_MB" -v h="$PERIOD_HOURS" 'BEGIN {printf "%.2f", (mb*8)/(h*3600)}')

    # === WRITE CSV ===
    echo "Analysis period (hours),$PERIOD_HOURS" >> "$CSV_FILE"
    echo "Total requests,$TOTAL_REQUESTS" >> "$CSV_FILE"
    echo "Requests per hour,$REQ_PER_HOUR" >> "$CSV_FILE"
    echo "Unique client IPs,$UNIQUE_IPS" >> "$CSV_FILE"
    echo "Unique domains accessed,$UNIQUE_DOMAINS" >> "$CSV_FILE"
    echo "Total data transferred,${DATA_GB} GB (${DATA_MB} MB)" >> "$CSV_FILE"
    echo "Average bandwidth,${BANDWIDTH_MBPS} Mbps" >> "$CSV_FILE"
    echo "Average response size,${AVG_RESPONSE_SIZE} KB" >> "$CSV_FILE"
    echo "Successful requests (2xx),${SUCCESS} (${SUCCESS_PCT}%)" >> "$CSV_FILE"
    echo "Redirects (3xx),${REDIRECTS}" >> "$CSV_FILE"
    echo "Client errors (4xx),${CLIENT_ERRORS}" >> "$CSV_FILE"
    echo "Server errors (5xx),${SERVER_ERRORS}" >> "$CSV_FILE"
    echo "Total errors,$(($CLIENT_ERRORS + $SERVER_ERRORS)) (${ERROR_PCT}%)" >> "$CSV_FILE"
    echo "Cache hits,${CACHE_HITS} (${CACHE_HIT_PCT}%)" >> "$CSV_FILE"
    echo "Cache misses,${CACHE_MISS}" >> "$CSV_FILE"

    # === TOP LISTS ===
    TOP_IPS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {count[$3]++; bytes[$3]+=$5} END {
        for (ip in count) printf "%s (%d req/%.1fMB) ", ip, count[ip], bytes[ip]/1048576
    }' | tr ' ' '\n' | sort -t'(' -k2 -nr | head -5 | tr '\n' ' ')
    echo "Top 5 client IPs,$TOP_IPS" >> "$CSV_FILE"

    TOP_DOMAINS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff {
        gsub(/^https?:\/\//, "", $7); gsub(/\/.*/, "", $7)
        count[$7]++; bytes[$7]+=$5
    } END {
        for (domain in count) printf "%s (%d req/%.1fMB) ", domain, count[domain], bytes[domain]/1048576
    }' | tr ' ' '\n' | sort -t'(' -k2 -nr | head -5 | tr '\n' ' ')
    echo "Top 5 domains by requests,$TOP_DOMAINS" >> "$CSV_FILE"

    TOP_ERROR_DOMAINS=$(cat $ACCESS_LOG 2>/dev/null | awk -v cutoff="$CUTOFF" '$1 > cutoff && ($4 ~ /\/40[0-9]/ || $4 ~ /\/50[0-9]/) {
        gsub(/^https?:\/\//, "", $7); gsub(/\/.*/, "", $7)
        errors[$7]++
    } END {
        for (domain in errors) printf "%s (%d errors) ", domain, errors[domain]
    }' | tr ' ' '\n' | sort -t'(' -k2 -nr | head -5 | tr '\n' ' ')
    echo "Top 5 error domains,$TOP_ERROR_DOMAINS" >> "$CSV_FILE"

    # === GENERATE HTML REPORT ===
    {
        echo "<!DOCTYPE html>"
        echo "<html lang='en'>"
        echo "<head>"
        echo "<meta charset='UTF-8'>"
        echo "<meta name='viewport' content='width=device-width, initial-scale=1.0'>"
        echo "<title>Squid Proxy Statistics - Enhanced Report</title>"
        echo "<style>"
        echo "body { font-family: 'Segoe UI', sans-serif; background: #f5f7fa; color: #333; margin: 0; padding: 20px; }"
        echo ".container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 4px 20px rgba(0,0,0,0.1); }"
        echo "h1 { text-align: center; color: #2c3e50; margin-bottom: 30px; font-size: 2.5em; }"
        echo ".stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px; }"
        echo ".stat-card { background: #fff; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); border-left: 4px solid #3498db; }"
        echo ".stat-card h3 { color: #2c3e50; margin-bottom: 15px; border-bottom: 2px solid #ecf0f1; padding-bottom: 8px; }"
        echo ".metric { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid #f1f1f1; }"
        echo ".metric:last-child { border-bottom: none; }"
        echo ".metric-name { font-weight: 600; color: #555; }"
        echo ".metric-value { color: #27ae60; font-weight: bold; }"
        echo ".error { color: #e74c3c !important; }"
        echo ".warning { color: #f39c12 !important; }"
        echo "table { width: 100%; border-collapse: collapse; margin: 20px 0; background: white; border-radius: 8px; overflow: hidden; }"
        echo "th, td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #f1f1f1; }"
        echo "th { background: #3498db; color: white; font-weight: 600; }"
        echo "tr:nth-child(even) { background-color: #f8f9fa; }"
        echo "tr:hover { background-color: #e3f2fd; }"
        echo ".timestamp { text-align: center; color: #777; margin-top: 30px; font-style: italic; }"
        echo ".section-title { color: #2c3e50; font-size: 1.5em; margin: 30px 0 15px 0; padding-bottom: 10px; border-bottom: 2px solid #3498db; }"
        echo "</style>"
        echo "</head>"
        echo "<body>"
        echo "<div class='container'>"
        echo "<h1>📊 Squid Proxy Statistics</h1>"
        
        # Main stats grid
        echo "<div class='stats-grid'>"
        echo "<div class='stat-card'>"
        echo "<h3>📈 General Overview</h3>"
        echo "<div class='metric'><span class='metric-name'>Analysis Period</span><span class='metric-value'>$PERIOD_HOURS hours</span></div>"
        echo "<div class='metric'><span class='metric-name'>Total Requests</span><span class='metric-value'>$(printf "%'d" $TOTAL_REQUESTS)</span></div>"
        echo "<div class='metric'><span class='metric-name'>Requests/Hour</span><span class='metric-value'>$REQ_PER_HOUR</span></div>"
        echo "<div class='metric'><span class='metric-name'>Unique IPs</span><span class='metric-value'>$UNIQUE_IPS</span></div>"
        echo "<div class='metric'><span class='metric-name'>Unique Domains</span><span class='metric-value'>$UNIQUE_DOMAINS</span></div>"
        echo "</div>"

        echo "<div class='stat-card'>"
        echo "<h3>💾 Bandwidth & Performance</h3>"
        echo "<div class='metric'><span class='metric-name'>Total Data</span><span class='metric-value'>${DATA_GB} GB</span></div>"
        echo "<div class='metric'><span class='metric-name'>Average Bandwidth</span><span class='metric-value'>${BANDWIDTH_MBPS} Mbps</span></div>"
        echo "<div class='metric'><span class='metric-name'>Avg Response Size</span><span class='metric-value'>${AVG_RESPONSE_SIZE} KB</span></div>"
        echo "<div class='metric'><span class='metric-name'>Cache Hit Rate</span><span class='metric-value'>${CACHE_HIT_PCT}%</span></div>"
        echo "</div>"

        echo "<div class='stat-card'>"
        echo "<h3>✅ Status Analysis</h3>"
        echo "<div class='metric'><span class='metric-name'>Success Rate</span><span class='metric-value'>${SUCCESS_PCT}%</span></div>"
        echo "<div class='metric'><span class='metric-name'>Successful (2xx)</span><span class='metric-value'>$SUCCESS</span></div>"
        echo "<div class='metric'><span class='metric-name'>Redirects (3xx)</span><span class='metric-value warning'>$REDIRECTS</span></div>"
        echo "<div class='metric'><span class='metric-name'>Client Errors (4xx)</span><span class='metric-value error'>$CLIENT_ERRORS</span></div>"
        echo "<div class='metric'><span class='metric-name'>Server Errors (5xx)</span><span class='metric-value error'>$SERVER_ERRORS</span></div>"
        echo "</div>"
        echo "</div>"

        # Detailed table
        echo "<h2 class='section-title'>📋 Detailed Metrics</h2>"
        echo "<table>"
        echo "<tr><th>Metric</th><th>Value</th></tr>"
        tail -n +2 "$CSV_FILE" | while IFS=, read -r metric value; do
            if [[ "$metric" == *"error"* ]] || [[ "$metric" == *"Error"* ]]; then
                echo "<tr><td>$metric</td><td class='error'>$value</td></tr>"
            elif [[ "$metric" == *"Cache"* ]] && [[ "$value" == *"%"* ]]; then
                echo "<tr><td>$metric</td><td class='metric-value'>$value</td></tr>"
            else
                echo "<tr><td>$metric</td><td>$value</td></tr>"
            fi
        done
        echo "</table>"

        echo "<p class='timestamp'>Generated on $(date)</p>"
        echo "</div></body></html>"
    } > "$HTML_FILE"

    END=$(date +%s)
    echo "✅ Stats CSV generated: $CSV_FILE"
    echo "✅ Stats HTML generated: $HTML_FILE"
    echo "📊 Summary: $TOTAL_REQUESTS requests, ${SUCCESS_PCT}% success rate, ${CACHE_HIT_PCT}% cache hit rate"
}

# MAIN MENU
echo "================ SQUID ANALYSIS TOOL ================"
echo "Select an option:"
echo "1) Squid Filter"
echo "2) Squid Audit"
echo "3) Squid Traffic (Report with alerts)"
echo "4) Squid Global CSV export"
echo "5) Squid Stats CSV export"
read -p "Enter choice [1-5]: " CHOICE

case "$CHOICE" in
    1) squid_filter ;;
    2) squid_audit ;;
    3) squid_traffic ;;
    4) squid_global ;;
    5) squid_stats ;;
    *) echo "Invalid option" ;;
esac

SCRIPT_END=$(date +%s)
echo "⏱ Total script duration: $((SCRIPT_END - SCRIPT_START)) seconds"
