#!/bin/bash
# by maravento.com

# Mass decompression with password
# https://www.maravento.com/2020/05/descompresion-masiva-de-archivos.html

echo "Unzip files with pass. Wait..."
printf "\n"

# checking script execution
if pidof -x $(basename $0) >/dev/null; then
  for p in $(pidof -x $(basename $0)); do
    if [ "$p" -ne $$ ]; then
      echo "Script $0 is already running..."
      exit
    fi
  done
fi

# check dependencies
# On Ubuntu Software, activate "multiverse" repo
pkgs='p7zip-full p7zip-rar'
if apt-get install -qq $pkgs; then
  echo "OK"
else
  echo "Error installing $pkgs. Abort"
  exit
fi

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
