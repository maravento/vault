#!/bin/bash
# maravento.com
#
################################################################################
#
# massunzip -- mass decompression of password-protected archives
# FILE: massunzip.sh
#
# DESCRIPTION:
# Mass decompression of password-protected archives in the current
# directory, trying a predefined list of passwords against each file.
#
# USAGE:
# ./massunzip.sh
# Run (as a non-root user) from the directory containing the archives.
#
# NOTE:
# The password list inside this script holds placeholders, not real
# credentials. Replace them with your own passwords before running it.
#
################################################################################

set -uo pipefail

# ------------------------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------------------------

# no-root check
if [ "$(id -u)" == "0" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: This script should not be run as root -abort" >&2
    exit 1
fi

# prevent overlapping runs
script_lock="/var/lock/$(basename "$0" .sh).lock"
(umask 077; : >> "$script_lock") || {
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: cannot open $(basename "$script_lock") -abort" >&2
    exit 1
}
exec 200>"$script_lock"
if ! flock -n 200; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: script $(basename "$0") is already running -abort" >&2
    exit 1
fi

if ! apt-cache policy | grep -qE '/multiverse'; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: multiverse off; sudo add-apt-repository multiverse" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: multiverse: then sudo apt update -abort" >&2
    exit 1
fi

# dependencies
for dep in p7zip-full p7zip-rar util-linux; do
    if ! dpkg -s "$dep" &>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: dependency '$dep' is not installed -abort" >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------------------------

# PASSWORDS
# These passwords are placeholders, not credentials for real archives.
# Replace them with your archive passwords before running this script.
# This editable example list is intentionally kept inside the script.
shopt -s extglob nullglob nocaseglob
passw=(
  passfoo
  passbar
  www.passfoobar.com
  banana
  chocolate
  whiskey
  vodka
  icecream
)

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# start
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: massunzip start..."

# CHECK
# Try the configured passwords against each supported archive
found_files=0
for f in *.@(gz|rar|zip|zip.001|7z|7z.001); do
    found_files=1
    [[ ("$f" =~ \.part[[:digit:]]+\.rar$) && ! ("$f" =~ \.part0*1\.rar$) ]] && continue

    matched=0
    for p in "${passw[@]}"; do
        if 7z t -p"$p" "$f" &>/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: password match '$f': $p"
            if ! 7z x -y -p"$p" "$f" -aoa &>/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: extraction failed: $f -alert"
            fi
            matched=1
            break
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: password test failed for '$f': $p"
        fi
    done

    if [ "$matched" -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: no password matched for: $f -alert"
    fi
done

if [ "$found_files" -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') INFO: no compressed files found in current directory"
fi

# ------------------------------------------------------------------------------
# END
# ------------------------------------------------------------------------------

# end
echo "$(date '+%Y-%m-%d %H:%M:%S') EVENT: massunzip done"
