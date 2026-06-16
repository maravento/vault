#!/bin/bash
# maravento.com
#
################################################################################
#
# Simple DNS Domain Checker
# -------------------------
# This lightweight script checks whether domains listed in a local file
# resolve via DNS using the `host` command. It is optimized for small to medium
# domain lists where fast, one-pass resolution is sufficient.
#
# Results:
# - `exists.txt`: Domains that successfully resolved
# - `not_exists.txt`: Domains that did not resolve
#
# Configuration:
# - Set the input list by editing the `list` variable inside the script.
# - Parallel execution is based on available CPU cores × 4 for performance.
#
# Notes:
# - Unlike more advanced scripts, this version does not retry failed domains
#   or perform input sanitization. It assumes the input list is already clean.
# - Ideal for quick checks or small domain validation tasks.
#
################################################################################

trap "echo -e '\nProcess interrupted by user'; exit 1" INT

list="mylist.txt"

if [ ! -f "$list" ]; then
    echo "The file '$list' does not exist."
    exit 1
fi

> exists.txt
> not_exists.txt

PROCS=$(($(nproc) * 4))

check_domain() {
    original="$1"
    clean="$original"
    while [[ "$clean" == .* ]]; do
        clean="${clean#.}"
    done
    if timeout 5 host "$clean" > /dev/null 2>&1; then
        echo "$original exists"
        echo "$original" >> exists.txt
    else
        echo "$original does NOT exist"
        echo "$original" >> not_exists.txt
    fi
}
export -f check_domain

cat "$list" | xargs -n 1 -P "$PROCS" -I {} bash -c 'check_domain "$@"' -- {}
