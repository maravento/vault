# [PyDHCP](https://github.com/maravento)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>pydhcp</b> is an open-source IPv4 DHCP server written in Python, designed as a drop-in replacement for <a href="https://github.com/isc-projects/dhcp">isc-dhcp-server</a> — which reached End-of-Life (EOL) in 2022. It implements RFC 2131 over UDP 67/68, replicates the same functionality using compatible configuration syntax and lease file format under its own file paths, and runs as a native <code>systemd</code> service with an <code>init.d</code> wrapper included.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>pydhcp</b> es un servidor DHCP IPv4 de código abierto escrito en Python, diseñado como reemplazo directo de <a href="https://github.com/isc-projects/dhcp">isc-dhcp-server</a> — que alcanzó su fin de vida (EOL) en 2022. Implementa RFC 2131 sobre UDP 67/68, replica la misma funcionalidad usando sintaxis de configuración y formato de concesiones compatible bajo sus propias rutas de archivo, y corre como servicio <code>systemd</code> nativo con wrapper <code>init.d</code> incluido.
    </td>
  </tr>
</table>

## Scope

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>What pydhcp does:</b>
      <ul>
        <li>Python daemon implementing DHCP (RFC 2131) over UDP 67/68</li>
        <li>Reads <code>/etc/pydhcp/pydhcpd.conf</code> (compatible with <code>dhcpd.conf</code> format)</li>
        <li>Writes <code>/etc/pydhcp/pydhcpd.leases</code> (compatible with <code>dhcpd.leases</code> format)</li>
        <li>Supports the directives used by <a href="https://raw.githubusercontent.com/maravento/vault/master/pydhcp/tools/pyleases.sh">pyleases.sh</a> — nothing more</li>
        <li>Runs as a <code>systemd</code> service under the <code>pydhcpd</code> user</li>
        <li>Responds to <code>/etc/init.d/pydhcpd stop|start</code> (compatible wrapper)</li>
        <li>IPv4 only, single interface</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Lo que pydhcp hace:</b>
      <ul>
        <li>Demonio Python que implementa DHCP (RFC 2131) sobre UDP 67/68</li>
        <li>Lee <code>/etc/pydhcp/pydhcpd.conf</code> (compatible con el formato de <code>dhcpd.conf</code>)</li>
        <li>Escribe <code>/etc/pydhcp/pydhcpd.leases</code> (compatible con el formato de <code>dhcpd.leases</code>)</li>
        <li>Soporta las directivas usadas por <a href="https://raw.githubusercontent.com/maravento/vault/master/pydhcp/tools/pyleases.sh">pyleases.sh</a> — nada más</li>
        <li>Corre como servicio <code>systemd</code> bajo el usuario <code>pydhcpd</code></li>
        <li>Responde a <code>/etc/init.d/pydhcpd stop|start</code> (wrapper compatible)</li>
        <li>Solo IPv4, interfaz única</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>Out of scope (not implemented):</b>
      <ul>
        <li>IPv6</li>
        <li>LDAP</li>
        <li>DDNS</li>
        <li>Multiple interfaces</li>
        <li>BOOTP / PXE</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Fuera de alcance (no implementado):</b>
      <ul>
        <li>IPv6</li>
        <li>LDAP</li>
        <li>DDNS</li>
        <li>Múltiples interfaces</li>
        <li>BOOTP / PXE</li>
      </ul>
    </td>
  </tr>
</table>

## Repository Structure

---

```
pydhcp/
├── pydhcpd.py          # Daemon + all DHCP logic (DISCOVER/OFFER/REQUEST/ACK)
├── pydhcpd.conf        # Main config (replaces /etc/dhcp/dhcpd.conf)
├── pydhcpd.defaults    # Interface settings (replaces /etc/default/isc-dhcp-server)
├── pydhcpd.service     # systemd unit
├── pydhcpd.init        # init.d wrapper
├── pyinstall.sh        # Installer / uninstaller
└── tools/
    ├── pyleases.sh     # Optional ACL and lease manager (see Tools section)
    └── pywebmin.sh     # Optional Webmin module installer (see Tools section)
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Files generated at runtime (not included in the repository):
    </td>
    <td style="width: 50%; vertical-align: top;">
      Archivos generados en runtime (no incluidos en el repositorio):
    </td>
  </tr>
</table>

```
/etc/pydhcp/pydhcpd.leases   # Active leases database
/etc/pydhcp/pydhcpd.pid      # PID file
```

## Requirements

---

- Ubuntu 24.04 x64
- Python 3.8+
- systemd

## HOW TO USE

---

### Install

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Clone the repository and run the installer to deploy all files to their correct system paths:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Clona el repositorio y ejecuta el instalador para desplegar todos los archivos en sus rutas de sistema correctas:
    </td>
  </tr>
</table>

```bash
# Download
sudo apt install -y python-is-python3
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python gitfolder.py https://github.com/maravento/vault/pydhcp

# Install
cd pydhcp
sudo bash pyinstall.sh
```

### Update & Remove

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To update or remove pydhcp, download the updated repository, enter the repository folder and run:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para actualizar o eliminar pydhcp, descargar el repositorio actualizado, ingresar a la carpeta del repositorio y ejecutar:
    </td>
  </tr>
</table>

```bash
cd pydhcp
sudo bash pyinstall.sh --update
# or
sudo bash pyinstall.sh --remove
```

| File | `--update` | `--remove` |
|------|-----------|------------|
| `pydhcpd.py` | ✅ overwritten | ✅ removed |
| `pydhcpd.service` | ✅ overwritten | ✅ removed |
| `pydhcpd.init` | ✅ overwritten | ✅ removed |
| `tools/pyleases.sh` | ✅ overwritten | ✅ removed |
| `tools/pywebmin.sh` | ✅ overwritten | ✅ removed |
| `pydhcpd.conf` | ⛔ preserved | ✅ removed |
| `pydhcpd.defaults` | ⛔ preserved | ✅ removed |
| `pydhcpd.leases` | ⛔ preserved | ✅ removed |
| `/var/log/pydhcpd.log` | ⛔ preserved | ✅ removed |
| `/etc/logrotate.d/pydhcpd` | ⛔ preserved | ✅ removed |

### Config

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The installer configures the interface, server IP, subnet, and pool range interactively. After installation, edit the configuration file only to add static host reservations or blocked MACs. Then restart the service to apply changes.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El instalador configura la interfaz, IP del servidor, subred y rango del pool de forma interactiva. Tras la instalación, edita el archivo de configuración solo para agregar reservas estáticas o MACs bloqueadas. Luego reinicia el servicio para aplicar los cambios.
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>Note:</b> <code>ping-check true</code> is enabled by default. The daemon sends a ping before each OFFER to verify the IP is not already in use. In environments with strict firewalls this may cause delays or false positives. To disable it, set <code>ping-check false;</code> in <code>/etc/pydhcp/pydhcpd.conf</code>.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Nota:</b> <code>ping-check true</code> está habilitado por defecto. El demonio envía un ping antes de cada OFFER para verificar que la IP no está en uso. En entornos con firewall estricto esto puede causar demoras o falsos positivos. Para desactivarlo, establece <code>ping-check false;</code> en <code>/etc/pydhcp/pydhcpd.conf</code>.
    </td>
  </tr>
</table>

| Description | Descripción | File / Archivo |
|-------------|-------------|----------------|
| Main configuration file | Archivo de configuración principal | `/etc/pydhcp/pydhcpd.conf` |
| Default interface settings | Configuración de interfaz por defecto | `/etc/pydhcp/pydhcpd.defaults` |
| Active leases database | Base de datos de concesiones activas | `/etc/pydhcp/pydhcpd.leases` |
| systemd unit | Unidad systemd | `/etc/systemd/system/pydhcpd.service` |
| init.d wrapper | Wrapper init.d | `/etc/init.d/pydhcpd` |

```bash
# Edit main config | Editar configuración principal
sudo nano /etc/pydhcp/pydhcpd.conf

# Restart service | Reiniciar servicio
sudo systemctl restart pydhcpd

# Check status | Verificar estado
sudo systemctl status pydhcpd

# View active leases | Ver concesiones activas
cat /etc/pydhcp/pydhcpd.leases

# Reload config without restart (SIGHUP) | Recargar configuración sin reiniciar (SIGHUP)
sudo systemctl reload pydhcpd

# View logs | Ver logs
sudo journalctl -u pydhcpd -f

# View logs via syslog (log-facility local7) | Ver logs por syslog (log-facility local7)
grep pydhcpd /var/log/syslog
```

### Tools

---

#### pyleases

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>pyleases.sh</b> — Advanced DHCP lease and ACL manager for pydhcpd. Parses <code>pydhcpd.leases</code>, detects unauthorized clients, rebuilds <code>pydhcpd.conf</code> from ACL files, and restarts the daemon. Designed for environments enforcing DHCP-based access control.<br><br>
      ACL directories: <code>/etc/acl/acl_mac/</code> (authorized: <code>mac-proxy.txt</code>, <code>mac-transparent.txt</code>, <code>mac-unlimited.txt</code>) and <code>/etc/acl/acl_dhcp/</code> (blocked: <code>blockdhcp.txt</code>).<br>
      Entry format: <code>a;MAC;IP;HOSTNAME;</code> — hotspot: <code>a;MAC;IP;HOSTNAME;END_TIME_EPOCH;</code>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>pyleases.sh</b> — Gestor avanzado de concesiones y ACLs DHCP para pydhcpd. Parsea <code>pydhcpd.leases</code>, detecta clientes no autorizados, reconstruye <code>pydhcpd.conf</code> a partir de archivos ACL y reinicia el demonio. Diseñado para entornos que aplican control de acceso basado en DHCP.<br><br>
      Directorios ACL: <code>/etc/acl/acl_mac/</code> (autorizados: <code>mac-proxy.txt</code>, <code>mac-transparent.txt</code>, <code>mac-unlimited.txt</code>) y <code>/etc/acl/acl_dhcp/</code> (bloqueados: <code>blockdhcp.txt</code>).<br>
      Formato: <code>a;MAC;IP;HOSTNAME;</code> — hotspot: <code>a;MAC;IP;HOSTNAME;END_TIME_EPOCH;</code>
    </td>
  </tr>
</table>

```bash
sudo bash tools/pyleases.sh
```

> **Mobile device limitations when `UNIFI_HOTSPOT_ENABLED=true`**
>
> If this option is enabled together with DHCP option 252 (WPAD), be aware of the following constraints on Android and iOS:
>
> - **WPAD not supported**: Android and iOS ignore DHCP option 252. The proxy must be configured manually on each device.
> - **Captive portal probes**: Android probes `connectivitycheck.gstatic.com`; iOS probes `captive.apple.com`. If these are blocked or intercepted, the device reports "connected without internet" even when the proxy is working correctly. Add these domains to the Squid whitelist without authentication.
> - **App proxy bypass**: Most apps on Android and iOS bypass the system proxy and connect directly. Only browsers reliably honor the manual proxy setting. Without SSL bump, direct HTTPS traffic cannot be redirected.
> - **MAC randomization**: Android 10+ and iOS 14+ use a randomized MAC address per network by default. A randomized MAC will never match an ACL entry and the device will be treated as an unauthorized client on every connection. Users must disable MAC randomization for the network before connecting, so the real hardware MAC is registered.
>
> These are platform limitations, not defects in pydhcpd or pyleases.sh.

#### pywebmin

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>pywebmin.sh</b> — Optional installer for a PyDHCP module for Webmin. Provides a web interface to manage the pydhcpd daemon: service control (start/stop/restart), active leases table, and configuration file editor. Requires Webmin to be installed on the system.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>pywebmin.sh</b> — Instalador opcional de un módulo PyDHCP para Webmin. Proporciona una interfaz web para administrar el demonio pydhcpd: control del servicio (start/stop/restart), tabla de concesiones activas y editor del archivo de configuración. Requiere que Webmin esté instalado en el sistema.
    </td>
  </tr>
</table>

```bash
# Install | Instalar
sudo bash tools/pywebmin.sh install

# Uninstall | Desinstalar
sudo bash tools/pywebmin.sh uninstall
```

### DHCP Iptables Rules

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Add the following rules to allow DHCP traffic on both interfaces. The WAN rules cover the case where the server itself acts as a DHCP client toward an upstream router. The LAN rules allow the server to assign IP addresses to local clients.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Agregue las siguientes reglas para permitir el tráfico DHCP en ambas interfaces. Las reglas de WAN cubren el caso en el que el propio servidor actúa como cliente DHCP hacia un enrutador ascendente. Las reglas de LAN permiten al servidor asignar direcciones IP a clientes locales.
    </td>
  </tr>
</table>

```bash
# WAN — DHCP client (server requests an IP from an upstream DHCP server)
iptables -A OUTPUT -o $wan -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A INPUT  -i $wan -p udp --sport 67 --dport 68 -j ACCEPT

# LAN — DHCP server (server assigns IPs to local clients)
iptables -A INPUT  -i $lan -p udp --sport 68 --dport 67 -j ACCEPT
iptables -A OUTPUT -o $lan -p udp --sport 67 --dport 68 -j ACCEPT
```

## Replacing isc-dhcp-server

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The following table maps <code>isc-dhcp-server</code> paths to their <code>pydhcp</code> equivalents:
    </td>
    <td style="width: 50%; vertical-align: top;">
      La siguiente tabla mapea las rutas de <code>isc-dhcp-server</code> con sus equivalentes en <code>pydhcp</code>:
    </td>
  </tr>
</table>

| isc-dhcp-server | pydhcp |
|-----------------|--------|
| `/etc/dhcp/dhcpd.conf` | `/etc/pydhcp/pydhcpd.conf` |
| `/var/lib/dhcp/dhcpd.leases` | `/etc/pydhcp/pydhcpd.leases` |
| `/etc/default/isc-dhcp-server` | `/etc/pydhcp/pydhcpd.defaults` |
| `/var/run/dhcpd.pid` | `/etc/pydhcp/pydhcpd.pid` |
| `/etc/systemd/system/isc-dhcp-server.service` | `/etc/systemd/system/pydhcpd.service` |
| `/etc/init.d/isc-dhcp-server` | `/etc/init.d/pydhcpd` |
| `systemctl restart isc-dhcp-server` | `systemctl restart pydhcpd` |

### Logs

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Log output format differs between servers but the behavior is equivalent. The following examples show the three main scenarios.<br>
      <em>Note: isc-dhcp-server shows the hostname starting from OFFER; pydhcpd shows it from DISCOVER onward.</em>
    </td>
    <td style="width: 50%; vertical-align: top;">
      El formato de log difiere entre servidores pero el comportamiento es equivalente. Los siguientes ejemplos muestran los tres escenarios principales.<br>
      <em>Nota: isc-dhcp-server muestra el hostname a partir del OFFER; pydhcpd lo muestra desde el DISCOVER.</em>
    </td>
  </tr>
</table>

#### Path

| Resource | isc-dhcp-server | pydhcpd |
|----------|-----------------|---------|
| Log file | `/var/log/syslog` | `/var/log/pydhcpd.log` |
| Log rotation | `/etc/logrotate.d/rsyslog` | `/etc/logrotate.d/pydhcpd` |
| journald | `journalctl -u isc-dhcp-server` | `journalctl -u pydhcpd` |

#### Scenario

| Scenario / Escenario | isc-dhcp-server | pydhcpd |
|----------------------|-----------------|---------|
| Authorized client with static IP (renewal) / Cliente autorizado con IP estática (renovación) | `DHCPREQUEST for 192.168.10.50 (192.168.10.2) from aa:bb:cc:dd:ee:ff via enp2s0`<br>`DHCPACK on 192.168.10.50 to aa:bb:cc:dd:ee:ff (FOO) via enp2s0` | `REQUEST from aa:bb:cc:dd:ee:ff (FOO)`<br>`ACK aa:bb:cc:dd:ee:ff → 192.168.10.50 (lease 2592000s)` |
| Unknown client entering the block pool / Cliente desconocido ingresando al pool de bloqueo | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0`<br>`DHCPOFFER on 192.168.10.230 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0`<br>`DHCPREQUEST for 192.168.10.230 (192.168.10.2) from bb:cc:dd:ee:ff:aa (BAR) via enp2s0`<br>`DHCPACK on 192.168.10.230 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)`<br>`OFFER bb:cc:dd:ee:ff:aa → 192.168.10.230`<br>`REQUEST from bb:cc:dd:ee:ff:aa (BAR)`<br>`ACK bb:cc:dd:ee:ff:aa → 192.168.10.230 (lease 120s)` |
| Blocked client - pool exhausted / Cliente bloqueado - pool agotado | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0: network 192.168.10.0/24: no free leases` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)`<br>`No IP available for bb:cc:dd:ee:ff:aa` |

#### Authoritative

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      When <code>authoritative;</code> is set, the server sends NAK to clients that request an IP assigned by a rogue DHCP server on the same network. The rogue may win the OFFER race, but the authoritative server destroys the lease by sending NAK to the REQUEST — forcing the client to rediscover and obtain the correct IP. This behavior is equivalent between isc-dhcp-server and pydhcpd.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Cuando se configura <code>authoritative;</code>, el servidor envía NAK a clientes que solicitan una IP asignada por un servidor DHCP no autorizado en la misma red. El rogue puede ganar la carrera del OFFER, pero el servidor autoritativo destruye el arrendamiento enviando NAK al REQUEST — forzando al cliente a redescubrir y obtener la IP correcta. Este comportamiento es equivalente entre isc-dhcp-server y pydhcpd.
    </td>
  </tr>
</table>

| | isc-dhcp-server (rogue) | pydhcpd (authoritative) |
|--|-------------------------|-------------------------|
| Rogue offers IP to client | `DHCPOFFER on 192.168.10.222 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | — |
| Client requests rogue IP | `DHCPREQUEST for 192.168.10.222 (192.168.10.249) from bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | `REQUEST from bb:cc:dd:ee:ff:aa (BAR)` |
| Rogue acknowledges | `DHCPACK on 192.168.10.222 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | — |
| Authoritative server rejects | — | `NAK → bb:cc:dd:ee:ff:aa` |
| Client rediscovers | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)` |

## ORIGINAL PROJECT

---

| Project | Version | EOL Date |
| :-----: | :-----: | :------: |
| [ISC DHCP](https://github.com/isc-projects/dhcp) | 4.4.3-P1-4ubuntu2 | 2022 |

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
