#!/bin/bash
# by maravento.com

# Domains Check with Host

# Requirements:
# - Bash 5.2.21
# - Ensure the input list has no 'http://', 'https://', or 'www.' prefixes.

# How to use:
# ./domcheck.sh my_domain_list.txt
# Optional (with parallel processes. By default 100)
# ./domcheck.sh my_domain_list.txt 50

# Checks if at least one argument is provided
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Use: $0 <file_name> [parallel_processes]"
    exit 1
fi

# Check if an input file was provided
if [ "$#" -ne 1 ]; then
    echo "Use: $0 <file_name>"
    exit 1
fi

infile="$1"

# pp = parallel processes (high resource consumption!)
pp="${2:-100}"

# Check if the file exists
if [ ! -f "$infile" ]; then
    echo "File '$infile' does not exist."
    exit 1
fi

# Starting Debugging
echo "Starting Debugging..."
sed '/^$/d; /#/d' $infile | sed 's/^\.//g' >clean
rm dnslookup* step* fault.txt hit.txt >/dev/null 2>&1
echo "Step 1..."
if [ -s dnslookup ]; then
	awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup clean
else
	cat clean
fi | xargs -I {} -P $pp sh -c "if host {} >/dev/null; then echo HIT {}; else echo FAULT {}; fi" >>dnslookup
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
fi | xargs -I {} -P $pp sh -c "if host {} >/dev/null; then echo HIT {}; else echo FAULT {}; fi" >>dnslookup2
sed '/^FAULT/d' dnslookup2 | awk '{print $2}' | awk '{print "."$1}' | sort -u >>hit.txt
sed '/^HIT/d' dnslookup2 | awk '{print $2}' | awk '{print "."$1}' | sort -u >fault.txt
comm -23 <(sort $infile) <(sort hit.txt) >outdiff.txt
echo "hit.txt: existing domains from your list"
echo "outdiff.txt: non-existent domains removed"
echo "Done"
