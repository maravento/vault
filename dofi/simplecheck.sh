#!/bin/bash
# maravento.com

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

# Handle Ctrl+C to cleanly exit
trap "echo -e '\nProcess interrupted by user'; exit 1" INT

# Name of the domain list to check
list="mylist.txt"

# Check if the file exists
if [ ! -f "$list" ]; then
    echo "The file '$list' does not exist."
    exit 1
fi

# Clear previous output
> exists.txt
> not_exists.txt

# Determine number of parallel processes
#   PROCS=$(($(nproc)))      # Conservative (network-friendly)
#   PROCS=$(($(nproc) * 2))  # Balanced
#   PROCS=$(($(nproc) * 4))  # Aggressive (default)
#   PROCS=$(($(nproc) * 8))  # Extreme (8 or higher, use with caution)
#
# Example: Core i5 with 4 physical cores and 8 threads (Hyper-Threading)
#   nproc          → 8
#   PROCS=$((8 * 4)) → 32 parallel queries
#
# Adjust based on:
# - Your CPU
# - Your network (bandwidth/latency)
# - Desired balance between speed and system load
PROCS=$(($(nproc) * 4))

# Function to check a domain
check_domain() {
    original="$1"              # Preserve original format, including dot
    clean="${original#.}"      # Remove leading dot for the query

    if host "$clean" > /dev/null 2>&1; then
        echo "$original exists"
        echo "$original" >> exists.txt
    else
        echo "$original does NOT exist"
        echo "$original" >> not_exists.txt
    fi
}

export -f check_domain

# Run in parallel
cat "$list" | xargs -n 1 -P "$PROCS" bash -c 'check_domain "$0"'

