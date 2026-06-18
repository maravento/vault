#!/bin/bash
# maravento.com
#
################################################################################
#
# Domains Check with Host
# Requirements:
# - Bash 5.2.21
# - Ensure the input list has no 'http://', 'https://', or 'www.' prefixes.
# How to use:
# ./domcheck.sh my_domain_list.txt
# Optional (with parallel processes. By default 100)
# ./domcheck.sh my_domain_list.txt 50
#
################################################################################

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Use: $0 <file_name> [parallel_processes]"
    exit 1
fi

infile="$1"

if [ "$#" -eq 2 ]; then
    if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
        echo "Error: parallel_processes must be a positive integer."
        exit 1
    fi
    PROCS="$2"
else
    PROCS=$(($(nproc) * 4))
    MAX_PROCS=200
    if [ "$PROCS" -gt "$MAX_PROCS" ]; then
        PROCS="$MAX_PROCS"
    fi
fi

if ! command -v host >/dev/null 2>&1; then
    echo "Error: 'host' command not found. Please install it (e.g., dnsutils/bind-tools)."
    exit 1
fi

if [ ! -f "$infile" ]; then
    echo "File '$infile' does not exist."
    exit 1
fi

cleanup_tmp() {
    rm -f clean step2
}
trap cleanup_tmp EXIT

echo "Starting Debugging..."
sed '/^$/d; /^[[:space:]]*$/d; /#/d' "$infile" | sed 's/\r//g; s/^\.//g' >clean
rm -f dnslookup* step* fault.txt hit.txt >/dev/null 2>&1
echo "Step 1..."
if [ -s dnslookup ]; then
    awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup clean
else
    cat clean
fi | xargs -I {} -P "$PROCS" sh -c 'd="$1"; case "$d" in *[!a-zA-Z0-9._-]*) exit 0 ;; esac; if timeout 5 host "$d" >/dev/null 2>&1; then echo HIT "$d"; else echo FAULT "$d"; fi' _ {} >>dnslookup
sed '/^FAULT/d' dnslookup | awk '{print $2}' | awk '{print "."$1}' | sort -u >hit.txt
sed '/^HIT/d' dnslookup | awk '{print $2}' | awk '{print "."$1}' | sort -u >>fault.txt
sort -o fault.txt -u fault.txt
echo "OK"
echo "Step 2..."
sed 's/^\.//g' fault.txt | sort -u >step2
if [ -s dnslookup2 ]; then
    awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup2 step2
else
    cat step2
fi | xargs -I {} -P "$PROCS" sh -c 'd="$1"; case "$d" in *[!a-zA-Z0-9._-]*) exit 0 ;; esac; if timeout 5 host "$d" >/dev/null 2>&1; then echo HIT "$d"; else echo FAULT "$d"; fi' _ {} >>dnslookup2
sed '/^FAULT/d' dnslookup2 | awk '{print $2}' | awk '{print "."$1}' | sort -u >>hit.txt
sed '/^HIT/d' dnslookup2 | awk '{print $2}' | awk '{print "."$1}' | sort -u >fault.txt
comm -23 <(sed '/^$/d; /#/d; s/\r//g; s/^\.//' "$infile" | sort -u) <(sed 's/^\.//' hit.txt | sort -u) >outdiff.txt
echo "hit.txt: domains confirmed to resolve via DNS from your list"
echo "outdiff.txt: domains that did not resolve (non-existent, failed, or unchecked)"
echo "Done"
