# [BlackShield](https://github.com/maravento)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <b>BlackShield</b> is an experimental project designed to block malicious patterns, including archival extensions associated with ransomware, malware, scraping, crawlers, bots, <a href="https://en.wikipedia.org/wiki/Internet_censorship_circumvention" target="_blank">circumvention</a>, Proxy, BitTorrent, Tor and other cybernetics. Its purpose is to prevent the spread of these items using access control lists and personalized rules.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <b>BlackShield</b> es un proyecto experimental diseñado para bloquear patrones maliciosos, incluyendo extensiones de archivo asociadas a ransomware, malware, scraping, crawlers, bots, <a href="https://en.wikipedia.org/wiki/Internet_censorship_circumvention" target="_blank">circumvention</a>, Proxy, BitTorrent, Tor y otras amenazas cibernéticas. Su objetivo es prevenir la propagación de estas amenazas usando listas de control de acceso y reglas personalizadas.
    </td>
  </tr>
</table>

## Requirements

---

**⚠️ WARNING:** Only tested on Ubuntu 24.04 LTS. Other versions or distros not tested, use at your own risk.

```bash
bash samba squid iptables ulogd2 ipset perl
```

## DOWNLOAD PROJECT

---

```bash
# Download
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python3 gitfolder.py https://github.com/maravento/vault/blackshield

# Install
cd blackshield
chmod +x blackshield.sh
./blackshield.sh
```

## FILE REFERENCE

---

| File | Description | Descripción |
|------|-------------|-------------|
| `acl/source/rw/rw.txt` | Administrator-defined blacklist. Entries are always included in the final ransomware extension list. | Lista negra definida por el administrador. Las entradas siempre se incluyen en la lista final de extensiones de ransomware. |
| `acl/source/rw/wl.txt` | Administrator-defined whitelist. Entries override external feeds and `rw.txt`. | Lista blanca definida por el administrador. Sus entradas tienen prioridad sobre las fuentes externas y sobre `rw.txt`. |
| `acl/output/squid/rwext.txt` | Generated Squid ACL for ransomware file extensions. | ACL generada para Squid con extensiones asociadas a ransomware. |
| `acl/output/squid/blockua.txt` | Generated Squid ACL for malicious User-Agent strings. | ACL generada para Squid con cadenas User-Agent maliciosas o sospechosas. |
| `acl/output/smb/smbveto.txt` | Generated Samba veto list based on ransomware extensions. | Lista veto generada para Samba basada en extensiones asociadas a ransomware. |
| `acl/source/smb/commonveto.txt` | Static Samba veto list for common unwanted file types. | Lista veto estática para Samba con tipos de archivo comunes no deseados. |
| `acl/tmplst/` | Temporary working directory. Created automatically when the script starts and deleted automatically, along with everything inside it, when the script finishes — whether it succeeds or fails partway through. Nothing here persists between runs. | Directorio de trabajo temporal. El script lo crea automáticamente al iniciar y lo elimina por completo, junto con todo su contenido, al finalizar — sea que termine bien o falle a mitad de camino. Nada de esto persiste entre corridas. |

## ⚠️ WARNING: BEFORE YOU CONTINUE

---

***RESULT IS NOT GUARANTEED. USE IT AT YOUR OWN RISK | NO SE GARANTIZA EL RESULTADO. USELO BAJO SU PROPIO RIESGO***

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     This project contains files that may generate false positives.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Este proyecto contiene archivos que pueden generar falsos positivos.
    </td>
  </tr>
</table>

## ⚠️ WARNING: LIST SIZE & PERFORMANCE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     The generated lists (<code>rwext.txt</code> for Squid, <code>smbveto.txt</code> for Samba) grow every time the script runs, since they aggregate several external sources plus your own <code>rw.txt</code>. As of this writing, <code>rwext.txt</code> holds over 5,600 patterns, and <code>smbveto.txt</code> packs all of them into a single <code>veto files</code> line.
     <br><br>
     Neither Squid nor Samba document an official maximum size for <code>url_regex</code>/<code>urlpath_regex</code> ACLs or for the <code>veto files</code> directive — we looked and didn't find one either. What <i>is</i> documented is the matching mechanism: Squid's regex ACLs are checked sequentially against every pattern in the list on every request, and Squid's own wiki/mailing list describe this ACL type as "slow", with CPU cost growing with both list size and traffic; faster ACL types (<code>dstdomain</code>, <code>dst</code>) are recommended wherever possible. Samba's <code>veto files</code> works the same way: every pattern is checked against every file/directory entry.
     <br><br>
     In practice, on a busy proxy or file server this can measurably increase CPU usage and latency. Test the generated lists in your own environment before relying on them in production — watch <code>squid -k parse</code> time and CPU under peak load, and directory-listing speed on Samba shares with many files — and prune <code>rw.txt</code>/<code>wl.txt</code> if the list grows past what your hardware handles comfortably.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Las listas generadas (<code>rwext.txt</code> para Squid, <code>smbveto.txt</code> para Samba) crecen cada vez que corre el script, porque agregan varias fuentes externas más tu propio <code>rw.txt</code>. Al momento de escribir esto, <code>rwext.txt</code> tiene más de 5.600 patrones, y <code>smbveto.txt</code> los empaqueta todos en una sola línea <code>veto files</code>.
     <br><br>
     Ni Squid ni Samba documentan un tamaño máximo oficial para las ACL <code>url_regex</code>/<code>urlpath_regex</code> ni para la directiva <code>veto files</code> — lo buscamos y tampoco lo encontramos. Lo que <i>sí</i> está documentado es el mecanismo de coincidencia: las ACL regex de Squid se revisan secuencialmente contra cada patrón de la lista en cada solicitud, y la propia wiki/lista de correo de Squid describe este tipo de ACL como "lenta", con un costo de CPU que crece tanto con el tamaño de la lista como con el tráfico; se recomienda usar tipos de ACL más rápidos (<code>dstdomain</code>, <code>dst</code>) cuando sea posible. El <code>veto files</code> de Samba funciona igual: cada patrón se revisa contra cada archivo/directorio.
     <br><br>
     En la práctica, en un proxy o servidor de archivos con tráfico alto esto puede aumentar de forma medible el uso de CPU y la latencia. Prueba las listas generadas en tu propio entorno antes de confiar en ellas en producción — vigila el tiempo de <code>squid -k parse</code> y el uso de CPU en horas pico, y la velocidad de listado de directorios en recursos Samba con muchos archivos — y poda <code>rw.txt</code>/<code>wl.txt</code> si la lista crece más de lo que tu hardware soporta cómodamente.
    </td>
  </tr>
</table>

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Open the terminal and run:
    </td>
    <td style="width: 50%; vertical-align: top;">
     Abra el terminal y ejecute:
    </td>
  </tr>
</table>

```bash
sudo mkdir -p /etc/acl
sudo find acl/ -type f -exec cp {} /etc/acl/ \;
sudo find /etc/acl/ -type f -exec chmod 644 {} \;
```

### Squid Rules

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Modify your file <code>/etc/squid/squid.conf</code> and add the following rules:
    </td>
    <td style="width: 50%; vertical-align: top;">
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

# Block: patterns
acl blockpatterns url_regex -i "/etc/acl/blockpatterns.txt"
http_access deny workdays blockpatterns

# Block: User-Agents
acl bad_useragents browser -i "/etc/acl/blockua.txt"
http_access deny bad_useragents

# Block: web3
acl web3 dstdomain "/etc/acl/web3domains.txt"
http_access deny web3

# Block: IPv4
acl no_ipv4 dstdom_regex -i ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$
http_access deny no_ipv4
# Block: IPv6
acl no_ipv6 dstdom_regex -i ^\[?[0-9a-f:]+\]?$
http_access deny no_ipv6

# And finally deny all other access to this proxy
http_access deny all
```

### Samba Rules

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Modify your <code>/etc/samba/smb.conf</code> file and add the list to the </code>veto files</code> directive to block the patterns and extensions. e.g:
    </td>
    <td style="width: 50%; vertical-align: top;">
     Modifique su archivo <code>/etc/samba/smb.conf</code> y agregue la lista a la directiva </code>veto files</code> para bloquear los patrones y extensiones. ej:
    </td>
  </tr>
</table>

```bash
   include = /etc/acl/smbveto.txt
   # or
   # Optional (includes common extensions):
   include = /etc/acl/commonveto.txt
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Important:
      <ul>
        <li>You cannot include more than one list in <code>smb.conf</code> for the <code>veto files</code> directive.</li>
        <li><code>vetofiles.txt</code> is generated automatically by <code>blackshield.sh</code>, merging <code>ransom_veto.txt</code> (updated dynamically) and <code>common_veto.txt</code> (static. You can add or remove extensions manually).</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      Importante:
      <ul>
        <li>No puede incluir más de una lista en <code>smb.conf</code> para la directiva <code>veto files</code>.</li>
        <li><code>vetofiles.txt</code> se genera automáticamente con <code>blackshield.sh</code>, unificando <code>ransom_veto.txt</code> (se actualiza dinámicamente) y <code>common_veto.txt</code> (estática. Puede agregar o quitar extensiones manualmente).</li>
      </ul>
    </td>
  </tr>
</table>

### Iptables Rules (Not Recommended)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     This project contains ACLs with non-exclusive strings, which can generate false positives, and Iptables firewall rules that slow down traffic and may not get the desired results. Note that string matching is intensive, unreliable, so you should consider it as a last resort.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Este proyecto contiene ACLs con cadenas no exclusivas, que pueden generar falsos positivos y reglas de firewall Iptables que ralentizan el tráfico y puede no obtener los resultados deseados. Tenga en cuenta que la coincidencia de cadenas es intensiva, poco confiable, por tanto debe considerarla como último recurso.
    </td>
  </tr>
</table>

#### Global Variables

```bash
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
hstring=$(curl -s https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/source/ipt/hexstring.txt)
for string in $(echo -e "$hstring" | sed -e '/^#/d' -e 's:#.*::g'); do
    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'Illegal-HexString'
    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
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
bt=$(curl -s https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/source/ipt/torrent.txt)
for string in $(echo -e "$bt" | sed -e '/^#/d' -e 's:#.*::g'); do
    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'BitTorrent'
    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
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
tor=$(curl -s https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackshield/acl/source/ipt/tor.txt)
for string in `echo -e "$tor" | sed -e '/^#/d' -e 's:#.*::g'`; do
    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'Tor'
    iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
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
- [kinomakino - ransomware_file_extensions](https://github.com/kinomakino/ransomware_file_extensions/blob/master/extensions.csv) (optional)
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

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
