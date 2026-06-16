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
        <li>Supports a subset of <code>isc-dhcp-server</code> directives (see <a href="#config">Config</a> section for the full list)</li>
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
        <li>Soporta un subconjunto de directivas de <code>isc-dhcp-server</code> (ver sección <a href="#config">Config</a> para la lista completa)</li>
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
├── pydhcpd.service     # systemd unit
├── pyinstall.sh        # Installer / uninstaller
├── init.d/
│   └── pydhcpd         # init.d wrapper (replaces /etc/init.d/isc-dhcp-server)
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
/etc/pydhcp/default/pydhcpd       # Interface and daemon settings (created by installer, preserved on update)
/etc/pydhcp/pydhcpd.leases        # Active leases database
/etc/pydhcp/pydhcpd.pid           # PID file
/etc/pydhcp/tools/pyleases.env    # pyleases environment (auto-generated on first run)
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
| `init.d/pydhcpd` | ✅ overwritten | ✅ removed |
| `tools/pyleases.sh` | ✅ overwritten | ✅ removed |
| `tools/pywebmin.sh` | ✅ overwritten | ✅ removed |
| `pydhcpd.conf` | ⛔ preserved | ✅ removed |
| `default/pydhcpd` | ⛔ preserved | ✅ removed |
| `pydhcpd.leases` | ⛔ preserved | ✅ removed |
| `tools/pyleases.env` | ⛔ preserved | ✅ removed |
| `/var/log/pydhcpd.log` | ⛔ preserved | ✅ removed |
| `/etc/logrotate.d/pydhcpd` | ⛔ preserved | ✅ removed |
| system user/group `pydhcpd` | ⛔ preserved | ✅ removed |

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
</table>

| Description | Descripción | File |
|-------------|-------------|------|
| Main configuration file | Archivo de configuración principal | `/etc/pydhcp/pydhcpd.conf` |
| Default interface settings | Configuración de interfaz por defecto | `/etc/pydhcp/default/pydhcpd` |
| Active leases database | Base de datos de concesiones activas | `/etc/pydhcp/pydhcpd.leases` |
| pyleases environment (auto-generated on first run) | Entorno de pyleases (auto-generado en primera corrida) | `/etc/pydhcp/tools/pyleases.env` |
| systemd unit | Unidad systemd | `/etc/systemd/system/pydhcpd.service` |
| init.d wrapper | Wrapper init.d | `/etc/init.d/pydhcpd` |

```bash
# Edit main config | Editar configuración principal
sudo nano /etc/pydhcp/pydhcpd.conf

# Restart service | Reiniciar servicio
sudo systemctl restart pydhcpd

# Check status | Verificar estado
sudo systemctl status pydhcpd
# ● pydhcpd.service - pydhcpd - Python DHCP Daemon
#      Loaded: loaded (/etc/systemd/system/pydhcpd.service; enabled; preset: enabled)
#      Active: active (running) since Tue 2026-06-09 17:51:49 -05; 17s ago
#        Docs: https://github.com/maravento/vault/tree/master/pydhcp
#    Main PID: 2356158 (python3)
#       Tasks: 3 (limit: 76240)
#      Memory: 11.0M (peak: 11.6M)
#         CPU: 331ms
#      CGroup: /system.slice/pydhcpd.service
#              └─2356158 /usr/bin/python3 /etc/pydhcp/pydhcpd.py
# jun 09 17:51:49 host python3[2356158]: 2026-06-09 17:51:49,070 [INFO] Config loaded: 10 static hosts, 5 blocked MACs
# jun 09 17:51:49 host python3[2356158]: 2026-06-09 17:51:49,071 [INFO] Leases loaded: 0 entries
# jun 09 17:51:49 host python3[2356158]: 2026-06-09 17:51:49,071 [INFO] pydhcpd started (pid 2356158, interface eth0)
# jun 09 17:51:49 host python3[2356158]: 2026-06-09 17:51:49,072 [INFO] Listening on eth0 (DHCP port 67)
# jun 09 17:51:52 host python3[2356158]: 2026-06-09 17:51:52,316 [INFO] DISCOVER from aa:bb:cc:dd:ee:ff (FooBar)
# jun 09 17:51:52 host python3[2356158]: 2026-06-09 17:51:52,316 [WARNING] Blocked: aa:bb:cc:dd:ee:ff (deny blockdhcp)
# jun 09 17:52:02 host python3[2356158]: 2026-06-09 17:52:02,086 [INFO] DISCOVER from bb:cc:dd:ee:ff:aa (<no hostname>)
# jun 09 17:52:02 host python3[2356158]: 2026-06-09 17:52:02,154 [INFO] OFFER bb:cc:dd:ee:ff:aa → 192.168.10.231
# jun 09 17:52:02 host python3[2356158]: 2026-06-09 17:52:02,264 [INFO] REQUEST from bb:cc:dd:ee:ff:aa (<no hostname>)
# jun 09 17:52:02 host python3[2356158]: 2026-06-09 17:52:02,283 [INFO] ACK bb:cc:dd:ee:ff:aa → 192.168.10.231 (lease 60s)
# jun 09 17:52:15 host python3[2356158]: 2026-06-09 17:52:15,391 [INFO] DISCOVER from cc:dd:ee:ff:aa:bb (BazHost)
# jun 09 17:52:15 host python3[2356158]: 2026-06-09 17:52:15,391 [WARNING] No IP available for cc:dd:ee:ff:aa:bb
# jun 09 17:53:02 host python3[2356158]: 2026-06-09 17:53:02,173 [INFO] Lease expired: 192.168.10.230

# View active leases | Ver concesiones activas
cat /etc/pydhcp/pydhcpd.leases

# Reload config without restart (SIGHUP) | Recargar configuración sin reiniciar (SIGHUP)
sudo systemctl reload pydhcpd

# Test configuration syntax without starting the daemon
sudo /etc/pydhcp/pydhcpd.py --test

# View logs (journald) | Ver logs (journald)
sudo journalctl -u pydhcpd -f

# View logs (file) | Ver logs (archivo)
sudo tail -f /var/log/pydhcpd.log
```

> **Note:** `ping-check true` is enabled in the shipped `pydhcpd.conf`. The daemon sends a ping before each OFFER to verify the IP is not already in use. In environments with strict firewall rules blocking ICMP, the ping will always time out silently and `ping-check` will have no effect. To disable it, set `ping-check false;` in `/etc/pydhcp/pydhcpd.conf`. If using `pyleases.sh`, set `PING_CHECK_ENABLED=false` in `pyleases.env` instead — the script regenerates `pydhcpd.conf` on every run.
>
> **Nota:** `ping-check true` viene activado en el `pydhcpd.conf` enviado. El demonio envía un ping antes de cada OFFER para verificar que la IP no está en uso. En entornos con reglas de firewall estrictas que bloquean ICMP, el ping siempre expirará sin respuesta y `ping-check` no tendrá ningún efecto. Para desactivarlo, establece `ping-check false;` en `/etc/pydhcp/pydhcpd.conf`. Si usas `pyleases.sh`, establece `PING_CHECK_ENABLED=false` en `pyleases.env` — el script regenera `pydhcpd.conf` en cada ejecución.

> **Note:** `cleanup-interval` controls how often (in seconds) the daemon removes expired leases from memory. The default is `60`. If you use a short pool lease-time (e.g. `10` or `30` seconds), set `cleanup-interval` to the same value or lower so that expired leases are freed promptly and the pool does not appear exhausted. When using `pyleases.sh`, set `CLEANUP_INTERVAL` in `pyleases.env` — it is written into `pydhcpd.conf` on every run.
>
> **Nota:** `cleanup-interval` controla con qué frecuencia (en segundos) el demonio elimina los arrendamientos expirados de la memoria. El valor por defecto es `60`. Si usas un lease-time corto en el pool (p.ej. `10` o `30` segundos), establece `cleanup-interval` al mismo valor o menor para que los arrendamientos expirados se liberen rápidamente y el pool no parezca agotado. Al usar `pyleases.sh`, define `CLEANUP_INTERVAL` en `pyleases.env` — se escribe en `pydhcpd.conf` en cada ejecución.

### Tools

---

#### pyleases

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>pyleases.sh</b> — Advanced DHCP lease and ACL manager for pydhcpd. Parses <code>pydhcpd.leases</code>, detects unauthorized clients, rebuilds <code>pydhcpd.conf</code> from ACL files, and restarts the daemon. Designed for environments enforcing DHCP-based access control.<br><br>
      ACL directories: <code>/etc/acl/acl_mac/</code> (authorized: <code>mac-proxy.txt</code>, <code>mac-transparent.txt</code>, <code>mac-unlimited.txt</code>) and <code>/etc/acl/acl_dhcp/</code> (blocked: <code>blockdhcp.txt</code>).<br>
      Entry format: <code>a;MAC;IP;HOSTNAME;</code>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>pyleases.sh</b> — Gestor avanzado de concesiones y ACLs DHCP para pydhcpd. Parsea <code>pydhcpd.leases</code>, detecta clientes no autorizados, reconstruye <code>pydhcpd.conf</code> a partir de archivos ACL y reinicia el demonio. Diseñado para entornos que aplican control de acceso basado en DHCP.<br><br>
      Directorios ACL: <code>/etc/acl/acl_mac/</code> (autorizados: <code>mac-proxy.txt</code>, <code>mac-transparent.txt</code>, <code>mac-unlimited.txt</code>) y <code>/etc/acl/acl_dhcp/</code> (bloqueados: <code>blockdhcp.txt</code>).<br>
      Formato: <code>a;MAC;IP;HOSTNAME;</code>
    </td>
  </tr>
</table>

```bash
sudo bash tools/pyleases.sh
```

> **First run**: pyleases.sh launches an interactive setup that asks for DHCP server IP, netmask, block-pool range, and DNS servers, and writes `/etc/pydhcp/tools/pyleases.env`. Delete this file to re-run the setup. Some of these prompts overlap with `pyinstall.sh` — answer consistently.
>
> **Primera corrida**: pyleases.sh inicia un setup interactivo que pregunta IP del servidor DHCP, máscara, rango del pool de bloqueo y DNS, y escribe `/etc/pydhcp/tools/pyleases.env`. Elimine ese archivo para volver a ejecutar el setup. Algunas preguntas se solapan con `pyinstall.sh` — responda consistentemente.

##### Supported directives / Directivas soportadas

| Directive | Description | Descripción |
|-----------|-------------|-------------|
| `authoritative;` | Server sends NAK to clients with foreign leases | El servidor envía NAK a clientes con leases ajenos |
| `cleanup-interval N;` | How often (seconds) expired leases are removed from memory | Frecuencia (segundos) con que se eliminan leases expirados de memoria |
| `server-identifier IP;` | IP the server uses to identify itself in DHCP replies | IP con la que el servidor se identifica en las respuestas DHCP |
| `deny duplicates;` | Reject requests from a MAC that already holds a lease | Rechaza solicitudes de una MAC que ya tiene un lease |
| `one-lease-per-client true;` | Release old lease before assigning a new one to the same MAC | Libera el lease anterior antes de asignar uno nuevo a la misma MAC |
| `deny declines;` | Ignore DHCPDECLINE messages | Ignora mensajes DHCPDECLINE |
| `deny client-updates;` | Ignore client-requested hostname updates | Ignora actualizaciones de hostname solicitadas por el cliente |
| `ping-check true\|false;` | Ping IP before OFFER to detect conflicts (controlled via `PING_CHECK_ENABLED` in `pyleases.env`) | Ping a la IP antes del OFFER para detectar conflictos (controlado via `PING_CHECK_ENABLED` en `pyleases.env`) |
| `ddns-update-style none;` | Disable dynamic DNS updates | Deshabilita actualizaciones DNS dinámicas |
| `option wpad ...;` | WPAD/PAC proxy auto-configuration (controlled via `WPAD_ENABLED` in `pyleases.env`) | Autoconfiguración de proxy WPAD/PAC (controlado via `WPAD_ENABLED` en `pyleases.env`) |
| `subnet ... { pool { ... } }` | Subnet declaration with dynamic block pool | Declaración de subred con pool de bloqueo dinámico |
| `host NAME { hardware ethernet MAC; fixed-address IP; }` | Static host reservation | Reserva estática de host |
| `class "blockdhcp" { ... }` / `subclass "blockdhcp" ...` | MAC-based DHCP block list | Lista de bloqueo DHCP por MAC |
| `min-lease-time`, `default-lease-time`, `max-lease-time` | Lease duration controls | Control de duración de leases |
| `option routers`, `option subnet-mask`, `option broadcast-address`, `option domain-name-servers` | Standard DHCP options | Opciones DHCP estándar |

**Warning / Advertencia:**

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li><code>--update</code> backs up replaced files to <code>/etc/pydhcp/bak/TIMESTAMP/</code> before overwriting them. <code>pydhcpd.conf</code> and <code>default/pydhcpd</code> are <b>never overwritten</b> by <code>--update</code> (user config is preserved). Any manual edit to the code files (<code>pydhcpd.py</code>, <code>pyleases.sh</code>, <code>pywebmin.sh</code>) will be replaced. To persist a custom directive, edit the template inside <code>pyleases.sh</code> itself.</li>
        <li><code>pyleases.sh</code> fully rebuilds <code>/etc/pydhcp/pydhcpd.conf</code> on every run from its ACL files and <code>pyleases.env</code>. Any manual edits to <code>pydhcpd.conf</code> — including custom lease times, pools, or directives — will be lost. If you manage <code>pydhcpd.conf</code> manually, do not use <code>pyleases.sh</code>.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul>
        <li><code>--update</code> respalda los archivos reemplazados en <code>/etc/pydhcp/bak/TIMESTAMP/</code> antes de sobrescribirlos. <code>pydhcpd.conf</code> y <code>default/pydhcpd</code> <b>nunca se sobreescriben</b> (la configuración del usuario se preserva). Cualquier edición manual a los archivos de código (<code>pydhcpd.py</code>, <code>pyleases.sh</code>, <code>pywebmin.sh</code>) será reemplazada. Para preservar una directiva personalizada, edite el template dentro del propio <code>pyleases.sh</code>.</li>
        <li><code>pyleases.sh</code> reconstruye completamente <code>/etc/pydhcp/pydhcpd.conf</code> en cada ejecución a partir de sus archivos ACL y <code>pyleases.env</code>. Cualquier edición manual a <code>pydhcpd.conf</code> — incluyendo lease times, pools o directivas personalizadas — se perderá. Si gestiona <code>pydhcpd.conf</code> manualmente, no utilice <code>pyleases.sh</code>.</li>
      </ul>
    </td>
  </tr>
</table>

##### WPAD/PAC via DHCP option 252 (optional)

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>pyleases.sh</code> generates <code>/etc/pydhcp/pydhcpd.conf</code> dynamically on every run. WPAD/PAC support is controlled entirely from <code>pyleases.env</code> — no manual editing of <code>pyleases.sh</code> is required.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>pyleases.sh</code> genera <code>/etc/pydhcp/pydhcpd.conf</code> dinámicamente en cada ejecución. El soporte WPAD/PAC se controla completamente desde <code>pyleases.env</code> — no se requiere editar manualmente <code>pyleases.sh</code>.
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>To enable/disable WPAD:</b>
      <ul>
        <li>Set <code>WPAD_ENABLED=true</code> in <code>/etc/pydhcp/tools/pyleases.env</code> to enable</li>
        <li>Set <code>WPAD_ENABLED=false</code> in <code>/etc/pydhcp/tools/pyleases.env</code> to disable (default)</li>
      </ul>
      <b>Prerequisites (if enabled):</b>
      <ol>
        <li>Install Apache2 and create a VirtualHost on port 18100.</li>
        <li>Place a valid <code>wpad.pac</code> file in the Apache document root for that VirtualHost.</li>
      </ol> The two <code>option wpad</code> lines will be automatically written to <code>/etc/pydhcp/pydhcpd.conf</code> on the next <code>pyleases.sh</code> run.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Para activar/desactivar WPAD:</b>
      <ul>
        <li>Establezca <code>WPAD_ENABLED=true</code> en <code>/etc/pydhcp/tools/pyleases.env</code> para activar</li>
        <li>Establezca <code>WPAD_ENABLED=false</code> en <code>/etc/pydhcp/tools/pyleases.env</code> para desactivar (por defecto)</li>
      </ul>
      <b>Requisitos previos (si está activado):</b>
      <ol>
        <li>Instale Apache2 y cree un VirtualHost en el puerto 18100.</li>
        <li>Coloque un archivo <code>wpad.pac</code> válido en el document root de ese VirtualHost.</li>
      </ol> Las dos líneas <code>option wpad</code> se escribirán automáticamente en <code>/etc/pydhcp/pydhcpd.conf</code> en la próxima ejecución de <code>pyleases.sh</code>.
    </td>
  </tr>
</table>

> **Note**: Android and iOS ignore DHCP option 252. The proxy must be configured manually on those devices.
> 
> **Nota**: Android e iOS ignoran la opción DHCP 252. El proxy debe configurarse manualmente en esos dispositivos.

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
| `/etc/default/isc-dhcp-server` | `/etc/pydhcp/default/pydhcpd` |
| `/var/run/dhcpd.pid` | `/etc/pydhcp/pydhcpd.pid` |
| `/etc/systemd/system/isc-dhcp-server.service` | `/etc/systemd/system/pydhcpd.service` |
| `/etc/init.d/isc-dhcp-server` | `/etc/init.d/pydhcpd` |
| `systemctl start\|stop\|restart\|status isc-dhcp-server` | `systemctl start\|stop\|restart\|status pydhcpd` |
| `service isc-dhcp-server start\|stop\|restart\|status` | `service pydhcpd start\|stop\|restart\|status` |

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

> **Note**: pydhcpd writes logs directly to `/var/log/pydhcpd.log`. It does not use syslog, therefore no `log-facility` directive is needed or supported.
>
> **Nota**: pydhcpd escribe los logs directamente a `/var/log/pydhcpd.log`. No utiliza syslog, por lo tanto no se necesita ni se soporta la directiva `log-facility`.

#### Scenario

| Scenario | isc-dhcp-server | pydhcpd |
|----------|-----------------|---------|
| Authorized client with static IP (renewal) / Cliente autorizado con IP estática (renovación) | `DHCPREQUEST for 192.168.10.50 (192.168.10.2) from aa:bb:cc:dd:ee:ff via enp2s0`<br>`DHCPACK on 192.168.10.50 to aa:bb:cc:dd:ee:ff (FOO) via enp2s0` | `REQUEST from aa:bb:cc:dd:ee:ff (FOO)`<br>`ACK aa:bb:cc:dd:ee:ff → 192.168.10.50 (lease 2592000s)` |
| Unknown client entering the block pool / Cliente desconocido ingresando al pool de bloqueo | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0`<br>`DHCPOFFER on 192.168.10.230 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0`<br>`DHCPREQUEST for 192.168.10.230 (192.168.10.2) from bb:cc:dd:ee:ff:aa (BAR) via enp2s0`<br>`DHCPACK on 192.168.10.230 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)`<br>`OFFER bb:cc:dd:ee:ff:aa → 192.168.10.230`<br>`REQUEST from bb:cc:dd:ee:ff:aa (BAR)`<br>`ACK bb:cc:dd:ee:ff:aa → 192.168.10.230 (lease 60s)` |
| Pool exhausted / Pool agotado | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0: network 192.168.10.0/24: no free leases` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)`<br>`No IP available for bb:cc:dd:ee:ff:aa` |
| Blocked client / Cliente bloqueado | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0: network 192.168.10.0/24: no free leases` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)`<br>`Blocked: bb:cc:dd:ee:ff:aa (deny blockdhcp)` |

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

| Event | isc-dhcp-server (rogue) | pydhcpd (authoritative) |
|-------|-------------------------|-------------------------|
| Rogue offers IP to client | `DHCPOFFER on 192.168.10.222 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | — |
| Client requests rogue IP | `DHCPREQUEST for 192.168.10.222 (192.168.10.249) from bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | `REQUEST from bb:cc:dd:ee:ff:aa (BAR)` |
| Rogue acknowledges | `DHCPACK on 192.168.10.222 to bb:cc:dd:ee:ff:aa (BAR) via enp2s0` | — |
| Authoritative server rejects | — | `NAK → bb:cc:dd:ee:ff:aa` |
| Client rediscovers | `DHCPDISCOVER from bb:cc:dd:ee:ff:aa via enp2s0` | `DISCOVER from bb:cc:dd:ee:ff:aa (BAR)` |

#### Rate Limiting

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>isc-dhcp-server</b> has no built-in per-client rate-limiting for lease allocation. Abuse mitigation relies on <code>deny duplicates;</code> and <code>one-lease-per-client true;</code>, plus pool exhaustion (once the pool is full, further <code>DHCPDISCOVER</code> messages simply receive no <code>DHCPOFFER</code>). Client identification is based on <code>chaddr</code> (or <code>client-id</code>, option 61) — never on the Ethernet source MAC of the frame, so behavior is identical whether the client is directly attached or behind a relay (<code>giaddr</code> is only used for routing the reply).
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>isc-dhcp-server</b> no tiene rate-limiting incorporado por cliente para la asignación de leases. La mitigación de abuso depende de <code>deny duplicates;</code> y <code>one-lease-per-client true;</code>, además del agotamiento del pool (una vez lleno, los <code>DHCPDISCOVER</code> simplemente no reciben <code>DHCPOFFER</code>). La identificación del cliente se basa en <code>chaddr</code> (o <code>client-id</code>, opción 61) — nunca en la MAC Ethernet origen del frame, por lo que el comportamiento es igual si el cliente está conectado directamente o detrás de un relay (<code>giaddr</code> solo se usa para enrutar la respuesta).
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>pydhcpd</b> adds a sliding-window rate limit on lease allocation, keyed by <b>client MAC (<code>chaddr</code>)</b> — the same identifier isc-dhcp-server uses. Each client MAC has its own bucket, so multiple clients behind the same relay are rate-limited independently and do not affect each other. If a single MAC exceeds the allowed number of allocations within the window, further requests are rejected with reason <code>"rate limited"</code> until the window slides forward. This is purely an internal safeguard against allocation storms; it is not configurable via <code>pydhcpd.conf</code> and has no equivalent directive in isc-dhcp-server.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>pydhcpd</b> agrega un límite de tasa (sliding window) sobre la asignación de leases, indexado por <b>MAC del cliente (<code>chaddr</code>)</b> — el mismo identificador que usa isc-dhcp-server. Cada MAC de cliente tiene su propio cupo, de modo que varios clientes detrás del mismo relay se limitan de forma independiente y no se afectan entre sí. Si una MAC supera el número de asignaciones permitidas dentro de la ventana, las solicitudes adicionales se rechazan con la razón <code>"rate limited"</code> hasta que la ventana avance. Esto es solo una salvaguarda interna contra ráfagas de asignación; no es configurable desde <code>pydhcpd.conf</code> y no tiene directiva equivalente en isc-dhcp-server.
    </td>
  </tr>
</table>

## EOL

---

| Project | Version | EOL Date |
| :-----: | :-----: | :------: |
| [ISC-DHCP](https://github.com/isc-projects/dhcp) | 4.4.3-P1-4ubuntu2 | 2022 |

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
