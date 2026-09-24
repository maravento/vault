#!/bin/bash
# maravento.com
#
################################################################################
#
# File Report
# ------------
# Brief: Disk usage report for headless servers, readable in a browser.
# Asks for the folder to scan, defaulting to /home/<local_user>, and writes
# a timestamped HTML report owned by the non-root local user.
#
# Requirements:
# - Run as root (sudo) to read every file of the scanned folder.
# - Packages: findutils, util-linux (script will check if missing).
#
# Output:
# - /home/<local_user>/Report/filereport_TIMESTAMP.html
#
# Report content:
# - Top 30 extensions by size, with file count and share of the total.
# - Top 30 folders by size, with file count.
# - Top 50 largest files, with full path.
#
################################################################################

set -uo pipefail

# path for cron
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# root check
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root -- abort"
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock")
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "ERROR: script $(basename "$0") is already running -- abort"
    exit 1
fi

# local_user detection
detect_local_user() {
    local uid_min uid_max
    local user uid best_user="" best_uid=999999

    uid_min=$(awk '/^UID_MIN/{print $2}' /etc/login.defs 2>/dev/null)
    uid_max=$(awk '/^UID_MAX/{print $2}' /etc/login.defs 2>/dev/null)
    uid_min=${uid_min:-1000}
    uid_max=${uid_max:-60000}

    while IFS=: read -r user _ uid _ _ _ shell; do
        [ "$user" = "root" ] && continue
        [ -z "$uid" ] && continue
        [ "$uid" -lt "$uid_min" ] && continue
        [ "$uid" -gt "$uid_max" ] && continue

        case "$shell" in
            */false|*/nologin) continue ;;
        esac

        id -nG "$user" 2>/dev/null | grep -qw sudo || continue

        if [ "$uid" -lt "$best_uid" ]; then
            best_uid="$uid"
            best_user="$user"
        fi
    done </etc/passwd

    [ -n "$best_user" ] || return 1
    echo "$best_user"
}

if ! local_user=$(detect_local_user); then
    echo "ERROR: No valid local user found. Create one with sudo access."
    exit 1
fi
echo "Using local user: $local_user"

# dependencies
for dep in findutils util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "ERROR: dependency '$dep' is not installed -- abort" >&2
        exit 1
    fi
done

echo "File Report Start. Wait..."

# VARIABLES
# target folder to scan (default: the local user's home)
read -r -p "Enter the folder to scan [/home/$local_user]: " scan_answer
targetfolder="${scan_answer:-/home/$local_user}"
if [ ! -d "$targetfolder" ]; then
    echo "ERROR: folder '$targetfolder' does not exist -- abort"
    exit 1
fi

# report directory (owned by user)
report_dir="/home/${local_user}/Report"
mkdir -p "$report_dir"
chown "$local_user:$local_user" "$report_dir"
chmod 0755 "$report_dir"
report_file="${report_dir}/filereport_$(date +%F-%H_%M_%S).html"

# REPORT
scan_list=$(mktemp)
trap 'rm -f "$scan_list"' EXIT
find "$targetfolder" -type f -printf '%s\t%p\n' 2>/dev/null > "$scan_list"
total_files=$(wc -l < "$scan_list")
total_bytes=$(awk -F'\t' '{s+=$1} END{printf "%.0f", s+0}' "$scan_list")

row_ext=$(awk -F'\t' '
    { name = $2; sub(/.*\//, "", name)
      if (name ~ /.\./) { ext = tolower(name); sub(/.*\./, "", ext) } else ext = "(none)"
      count[ext]++; bytes[ext] += $1 }
    END { for (e in count) printf "%d\t%s\t%d\n", bytes[e], e, count[e] }' "$scan_list" |
    sort -t "$(printf '\t')" -k1,1nr | head -30 |
    awk -F'\t' -v total="$total_bytes" '{share = (total>0 ? $1*100/total : 0); avg = ($3>0 ? $1/$3 : 0); printf "<tr><td>%s</td><td class=\"bar-cell\"><div class=\"bar\"><span style=\"width:%.1f%%\"></span></div></td><td>%d</td><td>%.1f</td><td>%.1f</td><td>%.1f%%</td></tr>\n", $2, share, $3, avg/1048576, $1/1048576, share}')

row_dir=$(awk -F'\t' '{ dir = $2; sub(/\/[^\/]*$/, "", dir); bytes[dir] += $1; count[dir]++ }
    END { for (d in bytes) printf "%d\t%s\t%d\n", bytes[d], d, count[d] }' "$scan_list" |
    sort -t "$(printf '\t')" -k1,1nr | head -30 |
    awk -F'\t' '{printf "<tr><td>%s</td><td>%d</td><td>%.1f</td></tr>\n", $2, $3, $1/1048576}')

row_file=$(sort -t "$(printf '\t')" -k1,1nr "$scan_list" | head -50 |
    awk -F'\t' '{printf "<tr><td>%s</td><td>%.1f</td></tr>\n", $2, $1/1048576}')

{
    cat <<'HTMLHEAD'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>File Report</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
           background: #f5f7fa; color: #2c3e50; line-height: 1.6; padding: 20px; }
    .container { max-width: 1200px; margin: 0 auto; background: white;
                 box-shadow: 0 2px 10px rgba(0,0,0,0.1); border-radius: 8px; }
    .header { background: linear-gradient(to bottom, #553c7b, #3b2a5a); color: white;
              padding: 30px; border-radius: 8px 8px 0 0; }
    .header h1 { font-size: 2em; margin-bottom: 10px; }
    .header .info { opacity: 0.9; font-size: 0.95em; word-break: break-all; }
    .summary { padding: 25px; background: #f8f9fa; border-bottom: 1px solid #e9ecef; }
    .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; }
    .summary-item { background: white; padding: 15px; border-radius: 6px; border-left: 4px solid #553c7b; }
    .summary-item strong { display: block; color: #553c7b; font-size: 0.85em;
                           text-transform: uppercase; margin-bottom: 5px; }
    .summary-item span { font-size: 1.3em; font-weight: bold; color: #2c3e50; }
    .content { padding: 25px; }
    .content h2 { margin: 25px 0 15px; color: #2c3e50; border-bottom: 2px solid #553c7b; padding-bottom: 8px; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 10px; }
    th { background: #553c7b; color: white; padding: 12px; text-align: left; font-weight: 600; font-size: 0.9em; }
    td { padding: 10px 12px; border-bottom: 1px solid #e9ecef; font-size: 0.9em; word-break: break-all; }
    tr:hover td { background: #f8f9fa; }
    .bar { background: #e9ecef; border-radius: 4px; height: 8px; width: 100%; min-width: 120px; }
    .bar span { display: block; height: 100%; border-radius: 4px; background: #553c7b; }
    .bar-cell { width: auto; padding-right: 1.5rem; text-align: left; }
    td:nth-child(n+2), th:nth-child(n+2) { text-align: right; white-space: nowrap; }
    .footer { padding: 15px 25px; background: #f8f9fa; border-top: 1px solid #e9ecef;
              font-size: 0.85em; color: #7f8c8d; border-radius: 0 0 8px 8px; }
</style>
</head>
<body>
<div class="container">
HTMLHEAD
    echo '<div class="header">'
    echo '<h1>File Report</h1>'
    echo "<div class=\"info\">$targetfolder</div>"
    echo '</div>'
    echo '<div class="summary"><div class="summary-grid">'
    echo "<div class=\"summary-item\"><strong>Files</strong><span>$total_files</span></div>"
    echo "<div class=\"summary-item\"><strong>Total size</strong><span>$(awk -v b="$total_bytes" 'BEGIN{printf "%.1f", b/1048576}') MB</span></div>"
    echo "<div class=\"summary-item\"><strong>Date</strong><span>$(date '+%Y-%m-%d %H:%M')</span></div>"
    echo '</div></div>'
    echo '<div class="content">'
    echo '<h2>Top 30 extensions by size</h2>'
    echo '<table><tr><th>Extension</th><th class="bar-cell"></th><th>Files</th><th>Avg. size (MB)</th><th>Total size (MB)</th><th>Share</th></tr>'
    echo "$row_ext"
    echo '</table>'
    echo '<h2>Top 30 folders by size</h2>'
    echo '<table><tr><th>Folder</th><th>Files</th><th>Size (MB)</th></tr>'
    echo "$row_dir"
    echo '</table>'
    echo '<h2>Top 50 largest files</h2>'
    echo '<table><tr><th>File</th><th>Size (MB)</th></tr>'
    echo "$row_file"
    echo '</table>'
    echo '</div>'
    echo "<div class=\"footer\">Generated by filereport.sh on $(date '+%Y-%m-%d %H:%M:%S')</div>"
    echo '</div></body></html>'
} > "$report_file"

chown "$local_user:$local_user" "$report_file"
echo "Done. Report: $report_file"
