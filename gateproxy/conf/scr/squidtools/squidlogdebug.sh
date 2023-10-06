#!/bin/bash
# by maravento.com

# Squid Log Debugging

# checking root
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
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

echo "Start Squid Log Debugging..."
echo -e
echo "Obtaining TLD, gTLDs, etc..."
function publicsuffix() {
  wget --no-check-certificate --timeout=10 --tries=1 --method=HEAD "$1" &>/dev/null
  if [ $? -eq 0 ]; then
    curl -s "$1" >>tmptld.txt

  else
    echo ERROR "$1"
  fi
}
publicsuffix 'https://raw.githubusercontent.com/publicsuffix/list/master/public_suffix_list.dat'
publicsuffix 'https://data.iana.org/TLD/tlds-alpha-by-domain.txt'
publicsuffix 'https://www.whoisxmlapi.com/support/supported_gtlds.php'
publicsuffix 'https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/sourcetlds.txt'

grep -v "//" tmptld.txt | sed '/^$/d; /#/d' | grep -v -P "[^a-z0-9_.-]" | sed 's/^\.//' | awk '{print "." $1}' | sort -u >tld.txt
echo OK

echo -e
echo "Debugging access.log..."
# example allow list (replace with yours) / lista de permitidos de ejemplo (reemplacela por la suya)
wget -c -q https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/allowurls.txt
# example deny list (replace with yours) / lista de denegados de ejemplo (reemplacela por la suya)
wget -c -q https://raw.githubusercontent.com/maravento/blackweb/master/bwupdate/lst/blockurls.txt
# joining lists / uniendo listas
sed '/^$/d; /#/d' {allowurls,blockurls}.txt | sort -u >urls.txt
acl="path_to_acl_to_check"
# Steps / Pasos
# Extract the domains from access.log / Extraer los dominios de access.log
# Compare them with the allowed list / Compararlos con la lista de permitidos
# Remove from the output www, protocols and others / Eliminar de la salida www, los protocolos y demás
# Remove from the output urls that do not have a valid TLD / Eliminar de la salida las urls que no tengan un TLD válido
grep -oP '[a-z]\w+?\.(\w+\.?){1,}' /var/log/squid/access.log | sed -r 's:(^\.*?(www|ftp|ftps|ftpes|sftp|pop|pop3|smtp|imap|http|https)[^.]*?\.|^\.\.?)::gi' | sed -r '/^.\W+/d' | awk '{print "." $1}' | sort -u >clean1.txt
grep -x -f <(sed 's/\./\\./g;s/^/.*/' tld.txt) <(grep -v -F -x -f tld.txt clean1.txt) | sort -u >clean2.txt
grep -x -f <(sed 's/\./\\./g;s/^/.*/' "$acl") <(grep -v -F -x -f "$acl" clean2.txt) | sort -u >clean3.txt
echo OK

echo -e
echo "DNS lockup..."
# parallel processes (adjust according to your resources) / procesos en paralelo (ajuste según sus recursos)
pp="500"
sed 's/^\.//g' clean3.txt >clean4.txt
if [ -s dnslookup.txt ]; then
  awk 'FNR==NR {seen[$2]=1;next} seen[$1]!=1' dnslookup.txt clean4.txt
else
  cat clean4.txt
fi | xargs -I {} -P "$pp" sh -c "if host {} >/dev/null; then echo HIT {}; else echo FAULT {}; fi" >>dnslookup.txt
sed '/^FAULT/d' dnslookup.txt | awk '{print $2}' | awk '{print "." $1}' | sort -u >out.txt
echo "Done"
