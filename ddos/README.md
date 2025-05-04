# [DDoS Deflate](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        DDoS Deflate is a lightweight script designed to mitigate distributed denial of service (DDoS) attacks on Linux servers by monitoring the number of active connections per IP address. IP addresses that exceed a predefined threshold will be blocked, reducing the load caused by malicious traffic.
    </td>
    <td style="width: 50%; white-space: nowrap;">
        DDoS Deflate es un script liviano, diseñado para mitigar ataques de denegación de servicio distribuido (DDoS) en servidores Linux al monitorear la cantidad de conexiones activas por dirección IP. Las IP que excedan un umbral predefinido serán bloqueadas, reduciendo la carga causada por el tráfico malicioso.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/ddos
```

## ORIGINAL PROJECT

---

| Author | Contributors | Version | Last Update |
| :----: | :----: | :----: | :----: |
| [Zaf](mailto:zaf@vsnl.com) | [Colin Mollenhour](mailto:colin@mollenhour.com) | 0.6 | 2012 |

## Requirements

---

- bash iptables dnsutils net-tools
- Ubuntu 20.04/22.04/24.04 x64

## HOW TO USE

---

### Install

```bash
wget -qO ddosinstall.sh https://raw.githubusercontent.com/maravento/vault/master/ddos/ddosinstall.sh && chmod +x ddosinstall.sh && sudo ./ddosinstall.sh
```

### Remove

```bash
sudo rm -rf /usr/local/ddos && sudo crontab -l | grep -v '/usr/local/ddos/ddos.sh' | sudo crontab -
```

### Configuration

<table>
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        The script runs every minute. If an IP reaches 150 simultaneous active connections, it will be banned for 600 seconds (10 minutes). You can modify this behavior by editing the <code>/usr/local/ddos/ddos.conf</code> file and changing the values of <code>BAN_LIMIT=150</code> and <code>BAN_PERIOD=600</code>. By default, the IPs of the system running DDoS-Deflate are excluded from banning.
    </td>
    <td style="width: 50%; white-space: nowrap;">
        El script se ejecuta cada minuto. Si una IP alcanza 150 conexiones activas simultáneamente, será baneada durante 600 segundos (10 minutos). Puede modificar este comportamiento, editando el archivo <code>/usr/local/ddos/ddos.conf</code> y cambiando los valores de <code>BAN_LIMIT=150</code> y <code>BAN_PERIOD=600</code>. Por defecto, las IPs del sistema que ejecuta DDoS-Deflate están excluidas del baneo. 
    </td>
  </tr>
</table>

| Description | Descripción | File |
|-------------|-------------|------|
| Check the banned IPs at: | Consulte las IPs baneadas en: | `/usr/local/ddos/ddos.log` |
| Check the configuration at: | Consulte la configuración en: | `/usr/local/ddos/ddos.conf` |
| Add IP addresses to the whitelist at: | Agregue direcciones IPs a la lista blanca en: | `/usr/local/ddos/ignore` |

### Logs

```bash
grep ddos.sh /var/log/syslog

Apr 22 14:11:01 user CRON[669435]: (root) CMD (/usr/local/ddos/ddos.sh &> /dev/null)
Apr 22 14:12:01 user CRON[669486]: (root) CMD (/usr/local/ddos/ddos.sh &> /dev/null)

cat /usr/local/ddos/ddos.log

Banned the following ip addresses on mar 22 abr 2025 11:21:01 -05
BANNED: 192.168.1.126 with 151 connections ()

Banned the following ip addresses on mar 22 abr 2025 11:59:02 -05
BANNED: 192.168.1.143 with 356 connections ()
BANNED: 104.91.161.199 with 166 connections (a104-91-161-199.deploy.static.akamaitechnologies.com.)

```

## End-of-Life (EOL) | End-of-Support (EOS)

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     This project has reached EOL - EOS. No longer supported or updated.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Este proyecto a alcanzado EOL - EOS. Ya no cuenta con soporte o actualizaciones.
    </td>
  </tr>
</table>

## PROJECT LICENSES

---

[![License: Artistic-1.0](https://img.shields.io/badge/License-Artistic%201.0-0298c3.svg)](https://github.com/maravento/vault/blob/master/ddos/LICENSE)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
