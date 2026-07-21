# [NetScan](https://github.com/maravento)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
    NetScan is a network scanning and auditing toolkit built around Nmap. It includes a portable Windows tool with an alternative GUI frontend based on Zenity — deploying Nmap with all its dependencies silently and unattended, and running different scan levels while generating HTML reports —, an equivalent on-demand scan-and-report script for Linux, and NetWatch, a live web dashboard for continuous LAN device and port auditing on Linux.
    </td>
    <td style="width: 50%; vertical-align: top;">
    NetScan es un conjunto de herramientas de escaneo y auditoría de red construido alrededor de Nmap. Incluye una herramienta portable para Windows con un frontend GUI alternativo basado en Zenity — que despliega Nmap con todas sus dependencias de forma silenciosa y desatendida, y ejecuta distintos niveles de escaneo generando reportes en HTML —, un script equivalente de escaneo y reporte bajo demanda para Linux, y NetWatch, un panel web en tiempo real para auditoría continua de dispositivos LAN y puertos en Linux.
    </td>
  </tr>
</table>

## Repository Structure

---

```
netscan/
├── README.md
├── win/                       # Windows package metadata (netscan.exe itself is hosted on mega.nz, not in this repo)
│   ├── changelog.txt
│   └── netscan.exe.sha256
├── img/                       # Screenshots used throughout this README
│   └── netscan-*.png
├── linux/
│   └── netreport.sh           # LINUX — on-demand scan-and-report tool
└── netwatch/                  # WEB — live web dashboard
    ├── netwatchinstall.sh     # Installer: --install|--update|--uninstall|--status
    ├── web/                   # Deployed to /var/www/netwatch/web/
    │   ├── netwatch.conf       # Apache vhost (:3126/?tab=lan and :3126/?tab=ports)
    │   ├── index.php           # Main page (LAN / Ports tabs)
    │   ├── lan.html            # LAN devices viewer
    │   ├── ports.html          # Ports viewer + Server/Target mode selector
    │   └── netwatchapi.php     # JSON API (devices, ports, mode switch)
    └── tools/                 # Deployed to /var/www/netwatch/tools/
        ├── netwatchlan.sh      # LAN discovery daemon (arp-scan)
        └── netwatchports.sh    # Port auditing daemon (ss / nmap) + mode CLI
```

## NETSCAN

---

### WINDOWS (netscan.exe)

---

#### Data Sheet

| File |  OS  | Size |
| :--: | :--: | :--: |
| [netscan.exe (.zip)](https://mega.nz/file/rJFQhCBQ#TKKSfa8FcOtmUVx8B7xOAQfkIhf7FlAsPU5R1uZ6EIo) | Windows 10/11 x64 | 78,8 MB |

#### Package Contents

- [nmap](https://nmap.org/download#windows)
- [npcap](https://nmap.org/download#windows)
- [libxslt (xsltproc)](https://www.zlatkovic.com/pub/libxml/)
- [Microsoft Visual C++ Runtimes](https://gitlab.com/stdout12/vcredist/-/releases)

#### How to Use

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>netscan.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>netscan.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

#### ⚠️ WARNING

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <strong>Before continuing:</strong> If you have Nmap or Npcap already installed on your PC, it is recommended to uninstall them before using this tool to avoid version conflicts.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <strong>Antes de continuar:</strong> Si tiene Nmap o Npcap instalado en su PC, se recomienda desinstalarlo antes de usar esta herramienta para evitar conflictos de versiones.
    </td>
  </tr>
</table>

#### Start

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Upon startup, it will prompt you to connect to your data network before continuing. Press OK to continue or Cancel to abort.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Al iniciar, le pedirá que se conecte a su red de datos antes de continuar. Presione OK para continuar o Cancel para abortar.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-welcome.png)](https://www.maravento.com)

#### Scan Selector

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Select the scan mode. Press OK to continue or Cancel to abort.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Seleccione el modo de escaneo. Presione OK para continuar o Cancel para abortar.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-selector.png)](https://www.maravento.com)

#### Scanning Modes

| Scan Mode | Nmap Options | Description | Descripción |
| --------- | ------------ | ----------- | ----------- |
| 1. LAN Scan | `-sS -T4 -F -sV` | Fast network scan with service detection | Escaneo rápido de red con detección de servicios |
| 2. Advanced LAN Scan | `-sS -T4 -p- -sV -sC --max-retries 3 --host-timeout 5m` | Deep scanning with scripts on all ports | Escaneo profundo con scripts en todos los puertos |
| 3. IP Scan | `-Pn -sS -T4 -p- -sV --version-intensity 8 -sC -O --script vuln --traceroute -oA scan_ip --max-retries 3 --host-timeout 10m` | Comprehensive single-host audit with OS detection, vulnerability scanning, and detailed service enumeration | Auditoría completa de un host con detección de OS, escaneo de vulnerabilidades y enumeración detallada de servicios |

#### Installation Messages

| Message | Description | Descripción |
| ------- | ----------- | ----------- |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-extract.png) | Extracting NetScan content during execution. | Extrayendo contenido de NetScan durante la ejecución. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-visual.png) | Installing MS Visual C++ Runtimes. | Instalando MS Visual C++ Runtimes |

#### Scan Messages

| Message | Description | Descripción |
| ------- | ----------- | ----------- |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-ipscan.png) | Option 3: Scanning for a specific IPv4. Ranges are not accepted. | Opción 3: Escaneo de IPv4 específica. No acepta rangos. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-invalidip.png) | Invalid IPv4 address entered. | Introdujo una dirección IPv4 inválida. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-scanning.png) | Scanning IP address or network. | Escaneando dirección IP o red. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-advanced.png) | Intense scanning. | Escaneo intenso. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-end.png) | Scan completed successfully. | El escaneo finalizó exitosamente. |

#### Error Messages

| Message | Description | Descripción |
|-------- | ----------- | ----------- |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-cancel.png) | You pressed the "Cancel" button or an error occurred during installation. | Presionó el botón "Cancelar" u ocurrió un error durante la instalación. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-errordependencies.png) | An error occurred during dependency installation. | Ocurrió un error durante la instalación de las dependencias. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-nointernet.png) | No internet connectivity detected. | No se detectó conectividad a internet. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-osincompatible.png) | You are using the installer on an incompatible operating system. | Está usando el instalador en un sistema operativo incompatible. |

#### Npcap

![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-npcap.png)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     NetScan requires Npcap, included in its free version. This dependency is not installed automatically, as it is not an OEM version and does not support silent installation (<code>/S</code> option). You will need to manually complete the Npcap installation when prompted by the installer. Npcap's free version allows use on up to 5 machines. For more information, see <a href="https://npcap.com/oem/">Npcap OEM</a>.
    </td>
    <td style="width: 50%; vertical-align: top;">
     NetScan requiere Npcap, incluido en su versión gratuita. La instalación de esta dependencia no es desatendida, ya que al no ser una versión OEM, no acepta instalación silenciosa (opción <code>/S</code>). Deberá completar manualmente la instalación de Npcap cuando el instalador la solicite. La versión gratuita de Npcap permite su uso en hasta 5 equipos. Para más información, consulte <a href="https://npcap.com/oem/">Npcap OEM</a>.
    </td>
  </tr>
</table>

#### Report

![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-report.png)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     NetScan will save the scan reports to the <code>Desktop\Report</code> folder, depending on the scan type, and each file will include a timestamp (date and time the scan was executed).
    </td>
    <td style="width: 50%; vertical-align: top;">
     NetScan guardará los reportes de escaneo en la carpeta <code>Desktop\Report</code>, según el tipo de escaneo, y cada archivo incluirá un timestamp (fecha y hora en que se ejecutó el escaneo).
    </td>
  </tr>
</table>

#### Telemetry

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     NetScan sends information to the developer, only for the purpose of verifying that the installation has been completed successfully. This information is used exclusively for statistical purposes and to improve the installer, without collecting personal data or compromising user privacy. Example:
    </td>
    <td style="width: 50%; vertical-align: top;">
     NetScan envía información al desarrollador, únicamente con el propósito de verificar que la instalación se haya completado de manera exitosa. Esta información se utiliza exclusivamente para fines estadísticos y de mejora del instalador, sin recopilar datos personales ni comprometer la privacidad del usuario. Ejemplo:
    </td>
  </tr>
</table>

```bash
Package Installation
Hostname=DESKTOP-AJ4JSC8
User=User
Date=mié. 13/11/2024 Time= 6:44:17,39
Status=Installed
Package: NetScan
```

#### Packages and Tools

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [curl for Windows](https://curl.se/windows/)
- [libxslt (xsltproc)](https://www.zlatkovic.com/pub/libxml/)
- [nmap](https://nmap.org/download#windows)
- [npcap](https://nmap.org/download#windows)
- [Quick Batch File Compiler](https://www.abyssmedia.com/quickbfc/)
- [RapidCRC Unicode](https://www.ov2.eu/programs/rapidcrc-unicode)
- [vcredist](https://gitlab.com/stdout12/vcredist/-/releases)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

### LINUX (netreport.sh)

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap; vertical-align: top; padding-right: 10px;">
      <p><strong>NetScan can run on Linux with the same scan modes:</strong></p>
      <p>
        1. <code>LAN Scan</code><br>
        2. <code>Advanced LAN Scan</code><br>
        3. <code>IP/Host Scan</code>
      </p>
      <p>
        NetScan will save scan reports in the <code>/home/$USER/Report</code> folder,
        according to the scan type.<br> Each file will include a timestamp
        (date and time when the scan was executed).
      </p>
    </td>
    <td style="width: 50%; white-space: nowrap; vertical-align: top; padding-left: 10px;">
      <p><strong>NetScan puede ejecutarse en Linux con los mismos modos de escaneo:</strong></p>
      <p>
        1. <code>LAN Scan</code><br>
        2. <code>Advanced LAN Scan</code><br>
        3. <code>IP/Host Scan</code>
      </p>
      <p>
        NetScan guardará los reportes de escaneo en la carpeta <code>/home/$USER/Report</code>,
        según el tipo de escaneo.<br> Cada archivo incluirá un timestamp
        (fecha y hora en que se ejecutó el escaneo).
      </p>
    </td>
  </tr>
</table>

#### Requirements

**⚠️ WARNING:** Only tested on Ubuntu 24.04 LTS. Other versions or distros not tested, use at your own risk.

- nmap, xsltproc

```bash
apt-get install -y nmap xsltproc
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>netreport.sh</code> checks for these on startup and aborts with a clear message if either is missing — install them beforehand to skip the extra round-trip.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>netreport.sh</code> verifica esto al iniciar y aborta con un mensaje claro si falta alguno — instálalos de antemano para evitarte la vuelta extra.
    </td>
  </tr>
</table>

```bash
wget -q https://raw.githubusercontent.com/maravento/vault/master/netscan/linux/netreport.sh -O netreport.sh
chmod +x netreport.sh
sudo ./netreport.sh
```

### WEB (netwatch)

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
    NetWatch is a live web dashboard for LAN and port auditing on Linux, independent of the on-demand Windows/Linux scan-and-report tools described above. It runs two background daemons — one discovering LAN devices via periodic <code>arp-scan</code>, another auditing TCP and UDP ports in one of two mutually exclusive modes: <strong>Server</strong> (default — reads the server's own listening sockets live, no probing) or <strong>Target</strong> (a chosen external host, scanned in near real time with nmap). Only one ports mode runs at a time, by design, to keep the audit trail free of mixed-source noise. Everything is exposed through a two-tab web interface reachable from <code>localhost</code>: <strong>LAN</strong> (device inventory with online/offline status) and <strong>Ports</strong> (server or target ports with open/closed status). History is kept in a local SQLite database.
    </td>
    <td style="width: 50%; vertical-align: top;">
    NetWatch es un panel web en tiempo real para auditoría de LAN y puertos en Linux, independiente de las herramientas de escaneo bajo demanda de Windows/Linux descritas arriba. Ejecuta dos demonios en segundo plano — uno que descubre dispositivos en la LAN vía <code>arp-scan</code> periódico, otro que audita puertos TCP y UDP en uno de dos modos mutuamente excluyentes: <strong>Server</strong> (por defecto — lee en vivo los sockets en escucha del propio servidor, sin sondear) o <strong>Target</strong> (un host externo elegido, escaneado casi en tiempo real con nmap). Solo un modo de puertos corre a la vez, a propósito, para mantener el rastro de auditoría libre de ruido de fuentes mezcladas. Todo se expone mediante una interfaz web de dos pestañas accesible desde <code>localhost</code>: <strong>LAN</strong> (inventario de dispositivos con estado online/offline) y <strong>Ports</strong> (puertos del servidor o de un target con estado abierto/cerrado). El histórico se guarda en una base de datos SQLite local.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netwatch.png)](https://www.maravento.com)

#### Runtime Files

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Files and directories generated at runtime (not included in the repository — see the top-level <a href="#repository-structure">Repository Structure</a> for the static tree):
    </td>
    <td style="width: 50%; vertical-align: top;">
      Archivos y directorios generados en runtime (no incluidos en el repositorio):
    </td>
  </tr>
</table>

```
/etc/netwatch/                      # Read-only config (750 root:www-data), same model as proxymon's /etc/proxymon
└── netwatch.env                     # Install config: user, interfaces, network, server IP, poll intervals
                                     # (640 root:www-data — web reads, never writes)

/var/www/netwatch/data/             # Web-writable state (775 www-data:www-data)
├── netwatch.db                      # SQLite database (WAL mode)
└── ports_mode.conf                  # Active ports mode + target IP
                                     # (664 www-data:www-data — web rewrites in place)

/var/run/                           # PID files, used by start/stop/status
├── netwatchlan.pid                  # netwatchlan.sh
└── netwatchports.pid                # netwatchports.sh

/var/log/netwatch.log               # Shared by the installer and both daemons
/etc/logrotate.d/netwatch           # Weekly rotation for the shared log
```

#### Requirements

**⚠️ WARNING:** Only tested on Ubuntu 24.04 LTS. Other versions or distros not tested, use at your own risk.

- Apache2 with mod_php (not PHP-FPM — the vhost uses `SetHandler application/x-httpd-php`)
- arp-scan, sqlite3, php-sqlite3, nmap, iproute2 (`ss`), logrotate

```bash
apt-get install -y apache2 libapache2-mod-php
apt-get install -y arp-scan sqlite3 php-sqlite3 nmap iproute2 logrotate
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>Optional</strong> — <code>avahi-utils</code> (mDNS) and <code>nbtscan</code> (NetBIOS) improve the LAN tab's <code>Hostname</code> column for devices without a reverse-DNS record (most consumer/IoT devices on a home LAN). Neither is required — <code>netwatchlan.sh</code> falls back gracefully to DNS-only resolution if they're not installed.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Opcional</strong> — <code>avahi-utils</code> (mDNS) y <code>nbtscan</code> (NetBIOS) mejoran la columna <code>Hostname</code> de la pestaña LAN para dispositivos sin registro DNS reverso (la mayoría de equipos de consumo/IoT en una LAN hogareña). Ninguno es obligatorio — <code>netwatchlan.sh</code> degrada con gracia a resolución solo por DNS si no están instalados.
    </td>
  </tr>
</table>

```bash
apt-get install -y avahi-utils nbtscan
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>Important</strong>
      <ul>
        <li>nginx must not be running.</li>
        <li>NetWatch uses Apache2 exclusively on port 3126, because it is listed as <strong>Unassigned</strong> by IANA. For more information visit <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt</a></li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Importante</strong>
      <ul>
        <li>nginx no debe estar en ejecución.</li>
        <li>NetWatch usa Apache2 exclusivamente en el puerto 3126, ya que está listado como <strong>Sin asignar</strong> por IANA. Para más información visita <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt</a></li>
      </ul>
    </td>
  </tr>
</table>

#### HOW TO USE

##### Install

```bash
git clone --depth=1 https://github.com/maravento/vault.git
cd vault/netscan/netwatch
sudo bash netwatchinstall.sh --install

# or

wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python3 gitfolder.py https://github.com/maravento/vault/netscan
cd netscan/netwatch
sudo bash netwatchinstall.sh --install
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The installer lists all physical network interfaces with a global IPv4 address (virtual/loopback interfaces are hidden — see below) and prompts twice: first for one or more <strong>scan interfaces</strong> (comma-separated numbers, e.g. <code>1,2</code> — useful on a server with both a LAN and a WAN NIC, since <code>netwatchlan.sh</code> arp-scans every one of them each cycle), then for a single <strong>management interface</strong>, which is the one the web panel's IP allowlist trusts for access — keep this on your LAN/admin interface, never on WAN. It then deploys the web dashboard and both daemons and starts them automatically — unlike an optional watchdog, these daemons are the dashboard's core, so they run right after install.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El instalador lista todas las interfaces de red físicas con una dirección IPv4 global (las interfaces virtuales/loopback quedan ocultas — ver abajo) y pregunta dos veces: primero por una o más <strong>interfaces a escanear</strong> (números separados por coma, ej. <code>1,2</code> — útil en un servidor con NIC de LAN y de WAN, ya que <code>netwatchlan.sh</code> hace arp-scan de cada una en cada ciclo), luego por una única <strong>interfaz de gestión</strong>, que es la que la lista blanca de IPs del panel web confía para el acceso — mantenla en tu interfaz LAN/admin, nunca en la WAN. Luego despliega el panel web y ambos demonios y los inicia automáticamente — a diferencia de un watchdog opcional, estos demonios son el núcleo del panel, por lo que se ejecutan justo después de instalar.
    </td>
  </tr>
</table>

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Interfaces matching <code>lo</code>, <code>docker*</code>, <code>br-*</code>, <code>veth*</code>, <code>virbr*</code>, <code>tun*</code>, <code>tap*</code> or <code>wg*</code> are excluded from both selectors — they're never useful arp-scan targets and would only clutter the interface list on a server running Docker/libvirt/VPN.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Las interfaces que coinciden con <code>lo</code>, <code>docker*</code>, <code>br-*</code>, <code>veth*</code>, <code>virbr*</code>, <code>tun*</code>, <code>tap*</code> o <code>wg*</code> quedan excluidas de ambos selectores — nunca son objetivos útiles para arp-scan y solo saturarían la lista de interfaces en un servidor con Docker/libvirt/VPN.
    </td>
  </tr>
</table>

##### Update & Uninstall

```bash
cd vault/netscan/netwatch
sudo bash netwatchinstall.sh --update
# or | o
sudo bash netwatchinstall.sh --uninstall
```

| File | `--update` | `--uninstall` |
|------|-----------|---------------|
| `web/netwatch.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/index.php`, `lan.html`, `ports.html`, `netwatchapi.php` | ✅ overwritten | ✅ removed |
| `tools/netwatchlan.sh`, `tools/netwatchports.sh` | ✅ overwritten (daemons restarted) | ✅ removed (daemons stopped) |
| `/etc/netwatch/netwatch.env` | ⛔ preserved | ✅ removed |
| `/var/www/netwatch/data/netwatch.db`, `ports_mode.conf` | ⛔ preserved | ✅ removed |

##### Status

```bash
sudo bash netwatchinstall.sh --status
```

Shows: daemon status (running/stopped), Apache port 3126, last 10 lines of the shared log, active ports mode/target, and device/port counts from the database.

##### LAN Field Reference

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      What <code>Vendor</code>/<code>Hostname</code> show when a value couldn't be resolved — both come straight from <code>arp-scan</code>'s MAC OUI lookup and the DNS → mDNS → NetBIOS chain, not from netwatch itself:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Lo que muestran <code>Vendor</code>/<code>Hostname</code> cuando no se pudo resolver un valor — ambos vienen directo del lookup OUI de MAC de <code>arp-scan</code> y de la cadena DNS → mDNS → NetBIOS, no de netwatch en sí:
    </td>
  </tr>
</table>

| Value | Meaning |
|-------|---------|
| `(Unknown)` | The MAC has a real, manufacturer-assigned OUI, but it isn't in `arp-scan`'s vendor database (`ieee-oui.txt`). |
| `(Unknown: locally administered)` | The MAC's "locally administered" bit is set — it was never assigned by a manufacturer at all (common with Wi-Fi privacy MAC randomization, VMs, containers). There's no vendor to look up. |
| `-` (Hostname) | Reverse DNS, mDNS, and NetBIOS (the ones installed) all failed to resolve a name for that IP. |

##### Ports Modes

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The Ports tab audits TCP and UDP ports in one of two modes, switchable from the browser (mode selector + Apply) or from the command line. Only one mode is active at a time — switching does not delete the other mode's history, it just stops polling it.
    </td>
    <td style="width: 50%; vertical-align: top;">
      La pestaña Ports audita puertos TCP y UDP en uno de dos modos, intercambiables desde el navegador (selector de modo + Apply) o desde la línea de comandos. Solo un modo está activo a la vez — cambiar de modo no borra el histórico del otro, solo deja de sondearlo.
    </td>
  </tr>
</table>

| Mode | Default | What it does | Poll method |
|------|---------|---------------|-------------|
| **Server** | ✅ yes | Watches this server's own listening TCP and UDP ports | `ss -tulnp` (reads the kernel's socket table directly — not a scan, always accurate, includes the owning process) |
| **Target** | no | Watches a single external host you choose | `nmap -Pn -sT -sU -F --host-timeout 60s` (top ~100 common TCP + UDP ports, skips host-discovery so a target dropping ICMP still gets scanned) every poll cycle |

```bash
sudo /var/www/netwatch/tools/netwatchports.sh mode server
sudo /var/www/netwatch/tools/netwatchports.sh mode target 192.168.1.10
sudo /var/www/netwatch/tools/netwatchports.sh list
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Clicking Apply (or running <code>mode target</code>) only writes the new mode/target to <code>ports_mode.conf</code> — it does not scan on the spot. <code>netwatchports.sh</code> is already running as a background loop and only picks up the change on its next cycle (<code>PORT_POLL_INTERVAL</code>, 30s by default), so the table can read empty for up to that long right after switching. What you see refreshing in the browser (<code>Refresh: 15s</code> selector) is a second, independent poll of whatever is already in the database — not the scan itself.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Al hacer clic en Apply (o correr <code>mode target</code>) solo se escribe el nuevo modo/target en <code>ports_mode.conf</code> — no escanea al instante. <code>netwatchports.sh</code> ya está corriendo en background y recién toma el cambio en su siguiente ciclo (<code>PORT_POLL_INTERVAL</code>, 30s por defecto), así que la tabla puede verse vacía hasta ese tiempo justo después de cambiar. Lo que se actualiza en el navegador (selector <code>Refresh: 15s</code>) es un segundo sondeo independiente de lo que ya hay en la base de datos — no el escaneo en sí.
    </td>
  </tr>
</table>

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>End-to-end timing:</strong> up to <code>PORT_POLL_INTERVAL</code> (30s default) for the daemon to pick up the new target, plus the <code>nmap</code> scan itself (seconds against a responsive host; the UDP half in particular can take much longer against one that silently drops probes — capped at 60s via <code>--host-timeout</code>, so one cycle can't stall the next), plus up to the browser's refresh interval to display it. Close to two minutes end-to-end isn't unusual against a heavily filtered target.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Tiempo de punta a punta:</strong> hasta <code>PORT_POLL_INTERVAL</code> (30s por defecto) para que el daemon tome el nuevo target, más el escaneo <code>nmap</code> en sí (segundos contra un host que responde; la mitad UDP en particular puede tardar mucho más contra uno que descarta los probes en silencio — acotado a 60s vía <code>--host-timeout</code>, así que un ciclo no puede estancar al siguiente), más hasta el intervalo de refresco del navegador para mostrarlo. No es raro que sean casi dos minutos de punta a punta contra un target muy filtrado.
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>ICMP is not required.</strong> The scan runs with <code>-Pn</code> (skips host-discovery/ping), so the target's firewall does not need to allow ICMP echo for its ports to be detected — the TCP/UDP probes go out directly either way.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>No hace falta ICMP.</strong> El escaneo corre con <code>-Pn</code> (se salta el descubrimiento por ping), así que el firewall del target no necesita permitir ICMP echo para que se detecten sus puertos — los probes TCP/UDP salen directo de todos modos.
    </td>
  </tr>
</table>

| Empty-table message | When it shows |
|----------------------|---------------|
| `Scanning ports. Wait...` | Right after clicking Apply, until the first row for the new mode/target arrives. |
| `No ports observed yet in this mode` | Table is empty and no mode/target was just applied (e.g. reloading the page on a mode that hasn't been polled yet). |
| `No ports match the current filters` | There is data, but the search box or Status/Protocol filters exclude every row. |

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>Target mode is an active port scan.</strong> Only point it at hosts you own or are explicitly authorized to audit — the same authorization requirement that applies to the Nmap-based Windows/Linux tools described above.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>El modo Target es un escaneo de puertos activo.</strong> Apúntalo únicamente a hosts que te pertenezcan o que estés explícitamente autorizado a auditar — el mismo requisito de autorización que aplica a las herramientas basadas en Nmap de Windows/Linux descritas arriba.
    </td>
  </tr>
</table>

#### ⚠️ WARNING: Network Access

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      NetWatch is designed to run locally and be accessed over a LAN. It is not recommended to expose it to the internet, as it lacks the hardening required for public-facing deployments. If you choose to publish it despite this warning, do so through an on-demand tunnel rather than opening ports directly.
    </td>
    <td style="width: 50%; vertical-align: top;">
      NetWatch está diseñado para ejecutarse localmente y ser accedido en red LAN. No se recomienda exponerlo a internet, ya que no cuenta con el endurecimiento necesario para despliegues públicos. Si decide publicarlo a pesar de esta advertencia, hágalo a través de un túnel bajo demanda en lugar de abrir puertos directamente.
    </td>
  </tr>
</table>

> **CSRF protection:** the Ports tab's mode-switch form has no login by design — guest access for the whole LAN is intentional. What it does have is a per-session CSRF token on the state-changing POST, so a request is only accepted if it was actually loaded from the page first.
>
> **Protección CSRF:** el formulario de cambio de modo de la pestaña Ports no tiene login por diseño — el acceso de invitado para toda la LAN es intencional. Lo que sí tiene es un token CSRF por sesión en el POST que modifica estado, de modo que una solicitud solo se acepta si realmente se cargó la página antes.

**Optional tunnel:**
- [Cloudflare Tunnel with Zero Trust Recommended](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)

## NOTICE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>This repository</strong>
      <ul>
        <li>May include third-party components.</li>
        <li>Does not accept Pull Requests. Changes must be proposed via Issues.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Este repositorio</strong>
      <ul>
        <li>Puede incluir componentes de terceros.</li>
        <li>No acepta Pull Requests. Los cambios deben proponerse mediante Issues.</li>
      </ul>
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
