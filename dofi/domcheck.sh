#!/bin/bash
# maravento.com
#
################################################################################
#
# Domains Check with Host
# Important:
# Ensure the input list has no 'http://', 'https://', or 'www.' prefixes.
# How to use:
# ./domcheck.sh my_domain_list.txt
# Optional (with parallel processes. By default: nproc x 4, max 200)
# ./domcheck.sh my_domain_list.txt 50
#
# NOTE on logging:
# - Writes to dofi.log (append-only, no rotation configured by this
#   script). Set up logrotate for this file if disk usage matters.
# - To clear it manually: truncate -s 0 dofi.log
#
################################################################################

# logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="$SCRIPT_DIR/dofi.log"
log() {
    local msg="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$log_file" 2>/dev/null || true
}

# check no-root
if [ "$(id -u)" == "0" ]; then
    log "[ERROR] This script should not be run as root."
    exit 1
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    log "Use: $0 <file_name> [parallel_processes]"
    exit 1
fi

infile="$1"

if [ "$#" -eq 2 ]; then
    if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
        log "Error: parallel_processes must be a positive integer."
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
    log "Error: 'host' command not found. Please install it (e.g., dnsutils/bind-tools)."
    exit 1
fi

if [ ! -f "$infile" ]; then
    log "File '$infile' does not exist."
    exit 1
fi

cleanup_tmp() {
    rm -f clean step2
}
trap cleanup_tmp EXIT

# Start
START_TIME=$(date +%s)
log "domcheck start..."

sed '/^$/d; /^[[:space:]]*$/d; /#/d' "$infile" | sed 's/\r//g; s/^\.//g' >clean
rm -f step2 fault.txt hit.txt

log "Step 1..."
if [ -s dnslookup ]; then
    awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup clean
else
    cat clean
fi | xargs -I {} -P "$PROCS" sh -c 'd="$1"; case "$d" in *[!a-zA-Z0-9._-]*) exit 0 ;; esac; if timeout 5 host "$d" >/dev/null 2>&1; then echo HIT "$d"; else echo FAULT "$d"; fi' _ {} >>dnslookup
sed '/^FAULT/d' dnslookup | awk '{print $2}' | awk '{print "."$1}' | sort -u >hit.txt
sed '/^HIT/d' dnslookup | awk '{print $2}' | awk '{print "."$1}' | sort -u >>fault.txt
sort -o fault.txt -u fault.txt
log "OK"

log "Step 2..."
sed 's/^\.//g' fault.txt | sort -u >step2
if [ -s dnslookup2 ]; then
    awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup2 step2
else
    cat step2
fi | xargs -I {} -P "$PROCS" sh -c 'd="$1"; case "$d" in *[!a-zA-Z0-9._-]*) exit 0 ;; esac; if timeout 5 host "$d" >/dev/null 2>&1; then echo HIT "$d"; else echo FAULT "$d"; fi' _ {} >>dnslookup2
sed '/^FAULT/d' dnslookup2 | awk '{print $2}' | awk '{print "."$1}' | sort -u >>hit.txt
sed '/^HIT/d' dnslookup2 | awk '{print $2}' | awk '{print "."$1}' | sort -u >fault.txt
log "hit.txt: domains successfully resolved"
log "fault.txt: unresolved domains"

# End
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

TOTAL=$(wc -l < clean)
HITS=$(wc -l < hit.txt)
FAULTS=$(wc -l < fault.txt)

log "Summary:"
log "  Input domains : $TOTAL"
log "  Resolved      : $HITS"
log "  Unresolved    : $FAULTS"
log "  Elapsed time  : ${ELAPSED}s"

log "domcheck done at: $(date)"
