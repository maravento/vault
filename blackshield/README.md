# [BlackShield](https://www.maravento.com/)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>BlackShield</b> is an experimental project designed to block malicious patterns, including archival extensions associated with ransomware, malware, scraping, crawlers, bots, <a href="https://en.wikipedia.org/wiki/Internet_censorship_circumvention" target="_blank">circumvention</a>, Proxy, BitTorrent, Tor and other cybernetics. Its purpose is to prevent the spread of these items using access control lists and personalized rules.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>BlackShield</b> es un proyecto experimental diseñado para bloquear patrones maliciosos, incluyendo extensiones de archivo asociadas a ransomware, malware, scraping, crawlers, bots, <a href="https://en.wikipedia.org/wiki/Internet_censorship_circumvention" target="_blank">circumvention</a>, Proxy, BitTorrent, Tor y otras amenazas cibernéticas. Su objetivo es prevenir la propagación de estas amenazas usando listas de control de acceso y reglas personalizadas.
    </td>
  </tr>
</table>

## DEPENDENCIES

---

```bash
bash samba squid iptables ulogd2 ipset perl
```

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/blackshield
```

## ⚠️ WARNING: BEFORE YOU CONTINUE

---

***RESULT IS NOT GUARANTEED. USE IT AT YOUR OWN RISK | NO SE GARANTIZA EL RESULTADO. USELO BAJO SU PROPIO RIESGO***

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     This project contains files that may generate false positives.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Este proyecto contiene archivos que pueden generar falsos positivos.
    </td>
  </tr>
</table>

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Open the terminal and run:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Abra el terminal y ejecute:
    </td>
  </tr>
</table>

```bash
cd blackshield
chmod +x blackshield.sh
./blackshield.sh
sudo mkdir -p /etc/acl
sudo find acl/ -type f -exec cp {} /etc/acl/ \;
sudo find /etc/acl/ -type f -exec chmod 644 {} \;
```

### Squid Rules

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Modify your file <code>/etc/squid/squid.conf</code> and add the following rules:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Modifique su archivo <code>/etc/squid/squid.conf</code> y agregue las siguientes reglas:
    </td>
  </tr>
</table>

```bash
# Block: Ransomware Extensions/Patterns
acl block_ransomware urlpath_regex -i "/etc/acl/rwext.txt"
http_access deny block_ransomware

# Block: mime_type
acl block_mime rep_mime_type -i "/etc/acl/blockmime.txt"
http_reply_access deny block_mime

# Block: ext
acl block_ext urlpath_regex -i "/etc/acl/blockext.txt"
http_access deny block_ext

# Block: punycode
acl block_punycode dstdom_regex -i \.xn--.*
http_access deny block_punycode

# Block: Invalid file extensions 
acl invalid_ext urlpath_regex -i \.[a-zA-Z0-9]+(\.[a-zA-Z0-9]+)*$
http_access deny invalid_ext

# Block: Blockwords
acl block_words url_regex -i "/etc/acl/blockwords.txt"
http_access deny block_words

# Block: User-Agents
acl bad_useragents browser -i "/etc/acl/blockua.txt"
http_access deny bad_useragents

# Block: IP
acl no_ip url_regex -i ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$
http_access deny no_ip

# And finally deny all other access to this proxy
http_access deny all
```

### Samba Rules

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Modify your <code>/etc/samba/smb.conf</code> file and add the list to the </code>veto files</code> directive to block the patterns and extensions. e.g:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Modifique su archivo <code>/etc/samba/smb.conf</code> y agregue la lista a la directiva </code>veto files</code> para bloquear los patrones y extensiones. ej:
    </td>
  </tr>
</table>

```bash
   include = /etc/acl/ransom_veto.txt
   
   # Optional (includes ransomware and common extensions):
   include = /etc/acl/vetofiles.txt
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      Important:
      <ul>
        <li>You cannot include more than one list in <code>smb.conf</code> for the <code>veto files</code> directive.</li>
        <li>Use the <code>acl/smb/merge_veto.sh</code> script to merge the <code>ransom_veto.txt</code> (updated with <code>blackshield.sh</code>) and <code>common_veto.txt</code> (static. You can add or remove extensions manually) lists.</li>
      </ul>
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Importante:
      <ul>
        <li>No puede incluir más de una lista en <code>smb.conf</code> para la directiva <code>veto files</code>.</li>
        <li>Use el script <code>acl/smb/merge_veto.sh</code> para unificar las listas <code>ransom_veto.txt</code> (se actualiza con <code>blackshield.sh</code>) y <code>common_veto.txt</code> (estática. Puede agregar o quitar extensiones manualmente).</li>
      </ul>
    </td>
  </tr>
</table>

### Iptables Rules (Not Recommended)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     This project contains ACLs with non-exclusive strings, which can generate false positives, and Iptables firewall rules that slow down traffic and may not get the desired results. Note that string matching is intensive, unreliable, so you should consider it as a last resort.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Este proyecto contiene ACLs con cadenas no exclusivas, que pueden generar falsos positivos y reglas de firewall Iptables que ralentizan el tráfico y puede no obtener los resultados deseados. Tenga en cuenta que la coincidencia de cadenas es intensiva, poco confiable, por tanto debe considerarla como último recurso.
    </td>
  </tr>
</table>

#### Global Variables

```bash
iptables=/sbin/iptables
ipset=/sbin/ipset
# Replace LAN (eth1)
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}'
enp2s1: 08:00:27:XX:XX:XX
enp2s0: 94:18:82:XX:XX:XX
# example variable
lan=enp2s1
```

#### Hex String Rule

```bash
# Block: Hex-String
hstring=$(curl -s https://raw.githubusercontent.com/maravento/vault/master/blackshield/acl/ipt/hexstring.txt)
for string in $(echo -e "$hstring" | sed -e '/^#/d' -e 's:#.*::g'); do
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'Illegal-HexString'
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
done
```

#### HexString NFLOG (/var/log/ulog/syslogemu.log)

```bash
Jul  8 18:42:33 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=94.46.155.193 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18048 DF PROTO=TCP SPT=56343 DPT=443 SEQ=2920450070 ACK=3653769687 WINDOW=16450 ACK PSH FIN URGP=0 MARK=0
Jul  8 18:42:34 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=151.139.69.135 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18050 PROTO=TCP SPT=56346 DPT=443 SEQ=2476213996 ACK=447728801 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  8 18:42:35 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=151.139.73.119 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18055 DF PROTO=TCP SPT=56348 DPT=443 SEQ=3555696871 ACK=3035932859 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  8 18:42:36 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=151.139.32.110 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18056 PROTO=TCP SPT=56344 DPT=443 SEQ=473128300 ACK=2213965853 WINDOW=16450 ACK PSH FIN URGP=0 MARK=0
```

#### BitTorrent Rule

```bash
# Lock: BitTorrent Protocol
bt=$(curl -s https://raw.githubusercontent.com/maravento/vault/master/blackshied/acl/ipt/torrent.txt)
for string in $(echo -e "$bt" | sed -e '/^#/d' -e 's:#.*::g'); do
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'BitTorrent'
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
done
```

#### BitTorrent NFLOG (/var/log/ulog/syslogemu.log)

```bash
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=172.98.67.7 LEN=116 TOS=00 PREC=0x00 TTL=127 ID=3227 PROTO=UDP SPT=16762 DPT=45371 LEN=96 MARK=0
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=172.98.67.7 LEN=108 TOS=00 PREC=0x00 TTL=127 ID=3228 DF PROTO=TCP SPT=62056 DPT=45371 SEQ=2452061326 ACK=1316214515 WINDOW=16562 ACK PSH URGP=0 MARK=0
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=82.217.81.73 LEN=108 TOS=00 PREC=0x00 TTL=127 ID=3230 DF PROTO=TCP SPT=62054 DPT=40115 SEQ=375153779 ACK=4197543778 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=217.209.151.82 LEN=116 TOS=00 PREC=0x00 TTL=127 ID=3231 PROTO=UDP SPT=16762 DPT=12589 LEN=96 MARK=0
```

#### Tor Rule

```bash
# Lock: Tor
tor=$(curl -s https://raw.githubusercontent.com/maravento/vault/master/blackshield/acl/ipt/tor.txt)
for string in `echo -e "$tor" | sed -e '/^#/d' -e 's:#.*::g'`; do
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'Tor'
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
done
```

#### Tor NFLOG (/var/log/ulog/syslogemu.log)

```bash
Jul  9 09:53:57 user Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5068 DF PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:53:58 user Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5071 DF PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:54:00 user Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5075 DF PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:54:03 user Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5077 PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
```

## SOURCES

---

### Ransomware

- [dannyroemhild - ransomware-fileext-list](https://github.com/dannyroemhild/ransomware-fileext-list/blob/master/fileextlist.txt)
- [eshlomo1 - Ransomware-NOTE](https://github.com/eshlomo1/Ransomware-NOTE/blob/main/ransomware-extension-list.txt)
- [giacomoarru - ransomware-extensions-2024](https://github.com/giacomoarru/ransomware-extensions-2024/blob/main/ransomware-extensions.txt)
- [kinomakino - ransomware_file_extensions](https://github.com/kinomakino/ransomware_file_extensions/blob/master/extensions.csv)
- [nspoab - malicious_extensions](https://github.com/nspoab/malicious_extensions/blob/main/list1)

### Malicious User-Agents

- [mitchellkrogza - bad-user-agents](https://raw.githubusercontent.com/mitchellkrogza/nginx-ultimate-bad-bot-blocker/refs/heads/master/_generator_lists/bad-user-agents.list)

## TOOLS

---

### String Capture

- [tcpdump](https://github.com/the-tcpdump-group/tcpdump)
- [tcpdump-cheat-sheet](https://cdn.comparitech.com/wp-content/uploads/2019/06/tcpdump-cheat-sheet.jpg)
- [wireshark](https://www.wireshark.org/)

### Algorithms Used

- [bm](https://en.wikipedia.org/wiki/Boyer%E2%80%93Moore_string-search_algorithm)
- [kmp](https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm)

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
