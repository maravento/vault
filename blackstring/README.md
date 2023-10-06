# [BlackString](https://www.maravento.com/)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

**BlackString** is an experimental project, aimed at blocking different types of connections, including [circumvention](https://en.wikipedia.org/wiki/Internet_censorship_circumvention), Proxy, BitTorrent, Tor, etc., which use a combination of secure communications with VPN obfuscation technologies, SSH and HTTP Proxy and they retransmit and re-assemble, making it very difficult to detect and block them. To achieve this, we use the Wireshark and tcpdump tools, which allow the capture and analysis of the data flow, both incoming and outgoing, to extract the strings of these connections and block them.

**BlackString** es un proyecto experimental, orientado a bloquear diferentes tipos de conexiones, entre ellas las [circumvention](https://en.wikipedia.org/wiki/Internet_censorship_circumvention), Proxy, BitTorrent, Tor, etc., que utilizan una combinación de comunicaciones seguras con tecnologías de ofuscación VPN, SSH y HTTP Proxy y hacen retransmisión y re-ensamblado, siendo muy difícil su detección y bloqueo. Para lograrlo utilizamos las herramientas Wireshark y tcpdump, que permiten la captura y análisis del flujo de datos, tanto de llegada como de salida, para extraer las cadenas de estas conexiones y bloquearlas.

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/blackstring"
```

## DEPENDENCIES

---

```bash
iptables ulogd2 ipset squid perl bash
```

## ⚠️ WARNING: BEFORE YOU CONTINUE

---

***RESULT IS NOT GUARANTEED. USE IT AT YOUR OWN RISK / NO SE GARANTIZA EL RESULTADO. USELO BAJO SU PROPIO RIESGO***

This project contains ACLs with non-exclusive strings, which can generate false positives, and Iptables firewall rules that slow down traffic and may not get the desired results. Note that string matching is intensive, unreliable, so you should consider it as a last resort. / Este proyecto contiene ACLs con cadenas no exclusivas, que pueden generar falsos positivos y reglas de firewall Iptables que ralentizan el tráfico y puede no obtener los resultados deseados. Tenga en cuenta que la coincidencia de cadenas es intensiva, poco confiable, por tanto debe considerarla como último recurso.

## HOW TO USE

---

### Global Variables

```bash
iptables=/sbin/iptables
ipset=/sbin/ipset
```

### Replace LAN (eth1)

```bash
ip -o link | awk '$2 != "lo:" {print $2, $(NF-2)}'
enp2s1: 08:00:27:XX:XX:XX
enp2s0: 94:18:82:XX:XX:XX
# example variable
lan=enp2s1
```

### [Ultrasurf](https://ultrasurf.us/) Rules

#### With Hex String (Not Recommended) / Con Hex-String (No Recomendada)

```bash
# Lock: Hex-String
hstring=$(curl -s https://raw.githubusercontent.com/maravento/vault/master/blackstring/hexstring.txt)
for string in $(echo -e "$hstring" | sed -e '/^#/d' -e 's:#.*::g'); do
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'Illegal-HexString'
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
done
```

#### Out NFLOG (/var/log/ulog/syslogemu.log)

```bash
Jul  8 18:42:33 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=94.46.155.193 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18048 DF PROTO=TCP SPT=56343 DPT=443 SEQ=2920450070 ACK=3653769687 WINDOW=16450 ACK PSH FIN URGP=0 MARK=0
Jul  8 18:42:34 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=151.139.69.135 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18050 PROTO=TCP SPT=56346 DPT=443 SEQ=2476213996 ACK=447728801 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  8 18:42:35 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=151.139.73.119 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18055 DF PROTO=TCP SPT=56348 DPT=443 SEQ=3555696871 ACK=3035932859 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  8 18:42:36 user Illegal-HexString IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=151.139.32.110 LEN=281 TOS=00 PREC=0x00 TTL=127 ID=18056 PROTO=TCP SPT=56344 DPT=443 SEQ=473128300 ACK=2213965853 WINDOW=16450 ACK PSH FIN URGP=0 MARK=0
```

#### Block with Squid (Recommended)

Tested on: US v21.32 | Squid Cache v5.2

```bash
# INSERT YOUR OWN RULE(S) HERE TO ALLOW ACCESS FROM YOUR CLIENTS

# Block IP/CIDR
# Download ACL: https://raw.githubusercontent.com/maravento/blackip/master/bipupdate/blst/blackcidr.txt
acl blackcidr dst "/path_to/blackcidr.txt"
http_access deny blackcidr

# Exclude your IP/CIDR addresses
acl allowip dst "/path_to/allowip.txt"
http_access allow allowip

# Block All IP/CIDR
acl no_ip url_regex -i [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}
http_access deny no_ip
```

##### Important About Block IP Rule with Squid

- It is faster to block these IPs with a proxy, like [Squid-Cache](http://www.squid-cache.org/). For more information, visit the [BlackIP](https://github.com/maravento/blackip) project / Es más rápido bloquear estas IPs con un proxy, como [Squid-Cache](http://www.squid-cache.org/). Para mayor información, visite el proyecto [BlackIP](https://github.com/maravento/blackip)
- You can also block the domains related using [Blackweb](https://github.com/maravento/blackweb) / También puede bloquear los dominios relacionados usando [Blackweb](https://github.com/maravento/blackweb)

#### Block with Ipset/Iptables

For more information, visit the [BlackIP](https://github.com/maravento/blackip) project / Para mayor información, visite el proyecto [BlackIP](https://github.com/maravento/blackip)

#### Increase Protection

To increase protection against this type of applications, it is recommended [Dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) and [Zeek](https://docs.zeek.org/en/master/) / Para incrementar la protección contra este tipo de aplicaciones, se recomienda [Dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) y [Zeek](https://docs.zeek.org/en/master/)

### BitTorrent Protocol Rule

```bash
# Lock: BitTorrent Protocol
bt=$(curl -s https://raw.githubusercontent.com/maravento/vault/master/blackstring/torrent.txt)
for string in $(echo -e "$bt" | sed -e '/^#/d' -e 's:#.*::g'); do
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'BitTorrent'
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
done
```

#### Out NFLOG (/var/log/ulog/syslogemu.log)

```bash
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=172.98.67.7 LEN=116 TOS=00 PREC=0x00 TTL=127 ID=3227 PROTO=UDP SPT=16762 DPT=45371 LEN=96 MARK=0
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=172.98.67.7 LEN=108 TOS=00 PREC=0x00 TTL=127 ID=3228 DF PROTO=TCP SPT=62056 DPT=45371 SEQ=2452061326 ACK=1316214515 WINDOW=16562 ACK PSH URGP=0 MARK=0
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=82.217.81.73 LEN=108 TOS=00 PREC=0x00 TTL=127 ID=3230 DF PROTO=TCP SPT=62054 DPT=40115 SEQ=375153779 ACK=4197543778 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:36:12 user BitTorrent IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=217.209.151.82 LEN=116 TOS=00 PREC=0x00 TTL=127 ID=3231 PROTO=UDP SPT=16762 DPT=12589 LEN=96 MARK=0
```

#### Block with Squid

```bash
acl blockmime rep_mime_type "^application/x-bittorrent$"
http_reply_access deny blockmime
acl blockext urlpath_regex "\.torrent([a-zA-Z][0-9]*)?(\?.*)?$"
http_access deny blockext
```

For more information, visit the [BlackIP](https://github.com/maravento/blackip) project / Para mayor información, visite el proyecto [BlackIP](https://github.com/maravento/blackip)

### Tor Rule (Brave)

```bash
# Lock: Tor
tor=$(curl -s https://raw.githubusercontent.com/maravento/vault/master/blackstring/tor.txt)
for string in `echo -e "$tor" | sed -e '/^#/d' -e 's:#.*::g'`; do
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j NFLOG --nflog-prefix 'Tor'
    $iptables -A FORWARD -i $lan -m string --hex-string "|$string|" --algo kmp -j DROP
done

```

#### Out NFLOG (/var/log/ulog/syslogemu.log)

```bash
Jul  9 09:53:57 adminred Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5068 DF PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:53:58 adminred Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5071 DF PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:54:00 adminred Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5075 DF PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
Jul  9 09:54:03 adminred Tor IN=enp2s1 OUT=enp2s0 MAC=94:18:82:XX:XX:XX:08:00:27:XX:XX:XX:08:00 SRC=192.168.1.27 DST=171.25.193.25 LEN=243 TOS=00 PREC=0x00 TTL=127 ID=5077 PROTO=TCP SPT=62143 DPT=443 SEQ=1821560764 ACK=2127432945 WINDOW=16450 ACK PSH URGP=0 MARK=0
```

#### Important About Ports (Tor, BitTorrent, etc)

It is recommended to block p2p, tor ports, etc., with [Ipset](https://manpages.debian.org/ipset/ipset.8). For more information visit [Blockports](https://www.maravento.com/2020/06/blackports.html) / Se recomienda bloquear los puertos p2p, tor, etc., con [Ipset](https://manpages.debian.org/ipset/ipset.8). Para mayor información visite el post [Blockports](https://www.maravento.com/2020/06/blackports.html)

```bash
# BLOCKPORTS (Remove or add ports to block TCP/UDP):
# Echo (7), CHARGEN (19), FTP (20, 21), SSH (22), TELNET (23), SMTP/SSMTP/IMAP/IMAPS/POP3/POP3S/POP3PASS (25,106,143,465,587,993,110,995), 6to4 (41,43,44,58,59,60,3544), FINGER (79), SSDP (2869,1900,5000), RDP-MS WBT Server - Windows Terminal Serve (3389), RFB-VNC (5900), TOR Ports (9001,9050,9150), Brave Tor (8008,8443,9001:9004,9090,9101:9103,9030,9031,9050,9132:9159), IBM HTTP Server administration default (TCP/UDP 8008), SqueezeCenter/Cherokee/Openfire (9090), Multicast DNS (5353), Link-Local Multicast LLMNR (5355), IPP (631), DCOM TCP Port & RPC Endpoint Mapper & RDC/DCE [Endpoint Mapper] – Microsoft networks (135), WinRM TCP Ports HTTP/HTTPS (5985:5986), TFTP (69) Trojans (10080), IRC (6660-6669), Trojans/Metasploit (4444), SQL inyection/XSS (8088, 8888), bittorrent (6881-6889 58251-58252,58687,6969) others P2P (1337,2760,4662,4672), RFC 2131 DHCP BOOTP protocol (67,68), Cryptomining (3333,5555,6666,7777,8848,9999,14444,14433,45560), Lightweight Directory Access protocol (LDAP) (389,636,3268,3269,10389,10636), Kerberos (88), WINS (42,1512), SUN.RPC - rpcbind [Remote Procedure Calls] (111), Barkley r-services and r-commands [e.g., rlogin, rsh, rexec] (512-514), Microsoft SQL Server [ms-sql-s] (1433), Microsoft SQL Monitor [ms-sql-m] (1434), TFTP (69), SNMP (161), VoIP - H.323 (1719/UDP 1720/TCP), Microsoft Point-to-Point Tunneling Protocol PPTP - VPN (1723), SIP (5060, 5061), SANE network scanner (6566), RTSP Nat Slipstreaming (TCP 554,5060:5061,1719:1720)

BP=$(curl -s https://raw.githubusercontent.com/maravento/gateproxy/master/acl/blockports.txt)

$ipset -L blockports >/dev/null 2>&1
if [ $? -ne 0 ]; then
        $ipset -! create blockports bitmap:port range 0-65535
    else
        $ipset -! flush blockports
fi
for blports in $(echo "$BP" | sort -V -u); do
    $ipset -! add blockports $blports
done
$iptables -w -t mangle -A PREROUTING -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -w -t mangle -A PREROUTING -m set --match-set blockports src,dst -j DROP
$iptables -w -A INPUT -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -w -A INPUT -m set --match-set blockports src,dst -j DROP
$iptables -w -A FORWARD -m set --match-set blockports src,dst -j NFLOG --nflog-prefix 'blockports'
$iptables -w -A FORWARD -m set --match-set blockports src,dst -j DROP
```

### Important About Source (SRC)

To avoid congestion (of the log and server that manages local network) due to the high level of processing, it is necessary to block local IP address that is generating this traffic. You can do it with [Ipset](https://manpages.debian.org/ipset/ipset.8): / Para evitar la congestión (del log y del servidor que administra la red local) por el alto nivel de procesamiento, es necesario bloquear la dirección IP local que está generando este tráfico. Puede hacerlo con [Ipset](https://manpages.debian.org/ipset/ipset.8):

```bash
#!/bin/bash
### BANIP ###
# example words list:
blockwords=$(curl -s https://raw.githubusercontent.com/maravento/gateproxy/master/acl/blockwords.txt)
# path to banip.txt
BIP=/path_to/banip.txt
# ban time (10 min = 600 seconds)
bantime="600"
# syslogemu (log)
syslogemu=/var/log/ulog/syslogemu.log
# localrange (replace "192.168.*" with the first two octets of your local network range)
localrange="192.168.*"
# add matches to banip.txt
perl -MDate::Parse -ne "print if/^(.{15})\s/&&str2time(\$1)>time-$bantime" $syslogemu | grep -F "$blockwords" | grep -Pio 'src=[^\s]+' | grep -Po $localrange > $BIP
# Ipset Rule for BanIP
$ipset flush banip
$ipset -N -! banip hash:net maxelem 1000000
for ip in $(cat $BIP); do
    $ipset -A banip $ip
done
$iptables -t mangle -A PREROUTING -m set --match-set banip src,dst -j DROP
$iptables -A INPUT -m set --match-set banip src,dst -j DROP
$iptables -A FORWARD -m set --match-set banip src,dst -j DROP
```

Save the script and schedule it in the crontab to run each 10 min. Adjust the ruler and task time according to your needs. Example: / Guarde el script y prográmelo en el crontab para que se ejecute cada 10 minutos. Ajuste el tiempo de la regla y tarea según sus necesidades. Ejemplo:

```bash
sudo crontab -l | { cat; echo "*/10 * * * * /path_to_script/banip.sh"; } | sudo crontab -
```

### Algorithms Used

- [bm](https://en.wikipedia.org/wiki/Boyer%E2%80%93Moore_string-search_algorithm)
- [kmp](https://en.wikipedia.org/wiki/Knuth%E2%80%93Morris%E2%80%93Pratt_algorithm)

### String Capture

- [tcpdump](https://github.com/the-tcpdump-group/tcpdump)
- [tcpdump-cheat-sheet](https://cdn.comparitech.com/wp-content/uploads/2019/06/tcpdump-cheat-sheet.jpg)
- [wireshark](https://www.wireshark.org/)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
