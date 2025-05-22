#!/bin/bash
# maravento.com

# Mass decompression with password
# https://www.maravento.com/2020/05/descompresion-masiva-de-archivos.html

echo "Unzip Files With Pass Starting. Wait..."
printf "\n"

# checking no-root
if [ "$(id -u)" == "0" ]; then
    echo "❌ This script should not be run as root."
    exit 1
fi

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
  for p in $(pidof -x $(basename $0)); do
    if [ "$p" -ne $$ ]; then
      echo "Script $0 is already running..."
      exit
    fi
  done
fi

# Check if 'multiverse' repository is available in APT
if ! apt-cache policy | grep -qE '/multiverse'; then
    echo "⚠️ The 'multiverse' repository is not enabled"
    echo "run: sudo add-apt-repository multiverse && sudo apt update"
    exit 1
fi

# Dependencies
if ! command -v 7z >/dev/null 2>&1; then
    echo "⚠️ 7z is not installed"
    echo "run: sudo apt install p7zip-full p7zip-rar"
    exit 1
fi

### PASSWORDS
# add and replace "passfoo, passbar, www.passfoobar.com, etc" with the passwords of your files to unzip
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
for f in *.@(gz|rar|zip|zip.001|7z|7z.001); do
  [[ ("$f" =~ \.part[[:digit:]]+\.rar$) && ! ("$f" =~ \.part0*1\.rar$) ]] && continue
  for p in "${passw[@]}"; do
    7z t -p"$p" "$f" &>/dev/null
    if [ $? -eq 0 ]; then
      echo "password match: $p"
      7z x -y -p"$p" "$f" -aoa &>/dev/null
      break
    else
      echo "test passwd: $p"
    fi
  done
done
