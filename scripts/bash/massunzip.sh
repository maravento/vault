#!/bin/bash
# maravento.com
#
################################################################################
#
# Mass decompression with password
# https://www.maravento.com/2020/05/descompresion-masiva-de-archivos.html
#
################################################################################

set -uo pipefail

# check no-root
if [ "$(id -u)" == "0" ]; then
    echo "[ERROR] This script should not be run as root."
    exit 1
fi

# prevent overlapping runs
SCRIPT_LOCK="/var/lock/$(basename "$0" .sh).lock"
exec 200>"$SCRIPT_LOCK"
if ! flock -n 200; then
    echo "[ERROR] Script $(basename "$0") is already running"
    exit 1
fi

echo "Unzip Files With Pass Starting. Wait..."

if ! apt-cache policy | grep -qE '/multiverse'; then
    echo "The 'multiverse' repository is not enabled. Run:"
    echo "sudo add-apt-repository multiverse && sudo apt update"
    exit 1
fi

if ! command -v 7z >/dev/null 2>&1; then
    echo "7z is not installed. Run:"
    echo "sudo apt install p7zip-full p7zip-rar"
    exit 1
fi

### PASSWORDS
# add and replace "passfoo, passbar, etc" with the passwords of your files to unzip
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

### CHECK
found_files=0
for f in *.@(gz|rar|zip|zip.001|7z|7z.001); do
    found_files=1
    [[ ("$f" =~ \.part[[:digit:]]+\.rar$) && ! ("$f" =~ \.part0*1\.rar$) ]] && continue

    matched=0
    for p in "${passw[@]}"; do
        if 7z t -p"$p" "$f" &>/dev/null; then
            echo "password match '$f': $p"
            if ! 7z x -y -p"$p" "$f" -aoa &>/dev/null; then
                echo "Extraction failed: $f"
            fi
            matched=1
            break
        else
            echo "test passwd '$f': $p"
        fi
    done

    if [ "$matched" -eq 0 ]; then
        echo "No password matched for: $f"
    fi
done

if [ "$found_files" -eq 0 ]; then
    echo "No compressed files found in current directory."
fi
