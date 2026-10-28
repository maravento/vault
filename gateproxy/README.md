<!--
Gateproxy documentation
FILE: gateproxy/README.md
-->

# [Gateproxy](https://github.com/maravento)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> centralizes internet access and the services of a LAN on one server. It is aimed at small and medium-sized businesses that need to control their traffic and administer their network. It integrates proxy, firewall, DHCP, DNS, Samba, traffic control, intrusion detection, backups and web administration tools through a common installer. Its modular design lets you choose services and use its independent projects separately or together.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> permite centralizar el acceso a Internet y los servicios de una LAN en un servidor. Está orientado a pequeñas y medianas empresas que necesitan controlar el tráfico y administrar su red. Integra proxy, firewall, DHCP, DNS, Samba, control de tráfico, detección de intrusiones, respaldos y herramientas de administración web mediante un instalador común. Su diseño modular permite elegir servicios y utilizar sus proyectos independientes por separado o conjuntamente.
    </td>
  </tr>
</table>

<!-- markdownlint-disable MD033 -->

## REQUIREMENTS

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>CPU: 4+ cores (≥ 3.0 GHz)</li><li>NIC: 2 (WAN &amp; LAN)</li><li>RAM: 12+ GB (4 GB cache_mem)</li><li>Storage: 50 GB SSD (cache_dir rock)</li></ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ul><li>CPU: 4+ núcleos (≥ 3.0 GHz)</li><li>Interfaces de red: 2 (WAN y LAN)</li><li>RAM: 12+ GB (4 GB cache_mem)</li><li>Almacenamiento: SSD de 50 GB (cache_dir rock)</li></ul>
    </td>
  </tr>
</table>

> **⚠️ WARNING -- Supported systems:** Only tested on Ubuntu 24.04/26.04 LTS. Other versions or distributions are not tested and are used at your own risk.
>
> **⚠️ WARNING -- Supported systems:** Solo probado en Ubuntu 24.04/26.04 LTS. Otras versiones o distribuciones no están probadas y se usan bajo tu responsabilidad.

## REPOSITORY STRUCTURE

---

```
gateproxy/
├── acl/                        # Access control lists for MAC, Squid and iptables rules (see ACL STRUCTURE)
│
├── conf/
│   ├── evebox/
│   │   ├── evebox.service          # EveBox systemd unit
│   │   └── evebox.yaml             # EveBox configuration
│   ├── fail2ban/
│   │   └── jail.local              # fail2ban jail config
│   ├── netplan/
│   │   └── 00-networkd.yaml        # Netplan configuration
│   ├── squid/
│   │   └── squid.conf              # Squid proxy configuration
│   ├── suricata/
│   │   ├── disable.conf            # Suricata disabled rules
│   │   ├── drop.conf               # Suricata drop rules (converted alert->drop by suricata-update)
│   │   ├── suricataclean.sh        # Suricata log cleanup
│   │   ├── suricataupdate.sh       # Suricata rules update
│   │   ├── suridata.sh             # Captures dest_ip from drop.conf-matched alerts into /etc/suricata/suridata.txt
│   │   └── suridata.txt            # Destination IPs blocked from Suricata alerts (see suridata.sh)
│   ├── ttyd/
│   │   └── ttyd.service            # ttyd (web terminal) systemd unit
│   ├── unbound/
│   │   └── forward.conf            # Unbound DNS forwarder configuration
│   ├── webmin/
│   │   └── text-editor.wbm         # Webmin Text Editor module
│   └── wpad/
│       └── wpad.conf               # Apache WPAD virtual host
│
├── scr/                        # Scripts (deployed to /etc/scr/)
│   ├── bkconf.sh                   # Backup configuration files
│   ├── iptables.sh                 # Firewall rules and ipsets
│   ├── killswitch.sh               # Emergency traffic block
│   ├── serverboot.sh               # Start/restart all services
│   └── serviceswatch.sh            # Service watchdog
│
└── gpsetup.sh                  # Main installer script
```

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Run the following command on a fresh installation. The script must be executed as root or with <code>sudo</code>.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Ejecute el siguiente comando en una instalación limpia. El script debe ejecutarse como root o con <code>sudo</code>.
    </td>
  </tr>
</table>

```bash
wget -qO gpsetup.sh https://raw.githubusercontent.com/maravento/vault/master/gateproxy/gpsetup.sh && sudo bash gpsetup.sh
```

### Interface Names

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     To identify the correct interface names before running the installer, use:
    </td>
    <td style="width: 50%; vertical-align: top;">
     Para identificar los nombres correctos de interfaces antes de ejecutar el instalador, use:
    </td>
  </tr>
</table>

```bash
join <(ip -o -br link | sort) <(ip -o -br addr | sort) | awk '$2=="UP" {print $1,$6,$3}' | sed -Ee 's./[0-9]+..'
```

### Shell Aliases

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Added to <code>~/.bashrc</code> for the local user.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Agregados al <code>~/.bashrc</code> del usuario local.
    </td>
  </tr>
</table>

```bash
alias upgrade   # full system upgrade (apt + aptitude + snap)
alias server    # run /etc/scr/serverboot.sh
alias cleaner   # run /etc/scr/cleaner.sh
```

### Verification

```bash
# Check running/failed services
systemctl list-units --type service --state running,failed

# Check iptables rules
iptables -nvL
iptables -nvL -t nat
iptables -nvL -t mangle

# Check active ipsets
ipset list -n

# Check listening sockets
ss -ltuna

# Check Squid cache
squidclient mgr:info

# Check WPAD/PAC
curl http://SERVER_IP:18100/wpad.pac
```

## HOW IT WORKS

---

### Installer Behavior

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      After installation, the installer deletes itself and reboots the system automatically.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Después de la instalación, el instalador se elimina y reinicia el sistema automáticamente.
    </td>
  </tr>
</table>

![Gateproxy](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/img/gateproxy.png)

#### Conflict Checks

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Before installing anything, the script checks for conflicting software already on the system. If any of the aborting checks are present, the installer aborts with instructions to remove them first.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Antes de instalar nada, el script verifica que no haya software en conflicto ya presente. Si detecta alguno de los que abortan, el instalador aborta con instrucciones para removerlo primero.
    </td>
  </tr>
</table>

| Packages | Description | Descripción |
| :--- | :--- | :--- |
| `isc-dhcp-server`, `kea-dhcp4-server`, `udhcpd` | DHCP: abort installation | DHCP: abortar la instalación |
| `bind9`, `pdns-recursor`, `unbound` | DNS server: abort installation | Servidor DNS: abortar la instalación |
| `squid`, `squid3`, `squid-openssl` | Proxy: abort installation | Proxy: abortar la instalación |
| `apache2`, `nginx`, `lighttpd`, `caddy` | Web server: abort installation | Servidor web: abortar la instalación |
| `samba` | File server: abort installation | Servidor de archivos: abortar la instalación |
| `syslog-ng` | Syslog: abort installation | Syslog: abortar la instalación |
| `firewalld`, `fail2ban` | Firewall: abort installation | Firewall: abortar la instalación |
| `snort` | IDS: abort installation | IDS: abortar la instalación |
| `webmin`, `ttyd` | Web admin: abort installation | Administración web: abortar la instalación |
| `chrony`, `ntpsec` | Time sync: abort installation | Sincronización horaria: abortar la instalación |
| `exim4` | Mail: abort installation | Correo: abortar la instalación |
| `ufw` | Active firewall: abort installation | Firewall activo: abortar la instalación |
| `dnsmasq` | DHCP/DNS overlap: show a warning | Superposición DHCP/DNS: mostrar una advertencia |

#### Log Rotation

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     The installer adjusts two rotation policies it does not own. Both files are copied to <code>.bak</code> before being edited.
    </td>
    <td style="width: 50%; vertical-align: top;">
     El instalador ajusta dos políticas de rotación que no le pertenecen. Ambos archivos se copian a <code>.bak</code> antes de editarlos.
    </td>
  </tr>
</table>

| File | Value | Description | Descripción |
| :--- | :--- | :--- | :--- |
| `/etc/logrotate.d/squid` | `weekly` | Rotation frequency | Frecuencia de rotación |
| `/etc/logrotate.d/squid` | `rotate 7` | Rotated log files retained | Archivos de log rotados conservados |
| `/etc/logrotate.d/squid` | `create 0640 proxy proxy` | Permissions, owner and group of the recreated log | Permisos, propietario y grupo del log recreado |
| `/etc/logrotate.d/apache2` | `rotate 7` | Rotated log files retained; Ubuntu defaults to 14 | Archivos de log rotados conservados; Ubuntu utiliza 14 por defecto |

### Optional Temporary-Memory Mounts

| Function | Description | Descripción |
| :--- | :--- | :--- |
| Default state | These settings are optional and disabled in <code>gpsetup.sh</code>. By default, the installer preserves the existing mounts and adds none of these entries to <code>/etc/fstab</code>. | Estas opciones son voluntarias y están desactivadas en <code>gpsetup.sh</code>. Por defecto, el instalador conserva los montajes existentes y no agrega estas entradas a <code>/etc/fstab</code>. |
| Mount selection | Before running the installer, decide whether to enable an option or leave all disabled. For <code>/tmp</code>, choose either a 2 GB limit or 30% of physical RAM, never both. Check existing <code>fstab</code> entries to avoid duplicate mounts. The read-only <code>/run/shm</code> option is independent and can affect applications that write to shared memory. Files stored in tmpfs are lost on reboot. | Antes de ejecutar el instalador, decida si necesita alguna opción o prefiere mantenerlas todas desactivadas. Para <code>/tmp</code>, elija un límite de 2 GB o el 30 % de la RAM física, nunca ambos. Revise las entradas existentes de <code>fstab</code> para evitar montajes duplicados. La opción de <code>/run/shm</code> en solo lectura es independiente y puede afectar a las aplicaciones que escriben en memoria compartida. Los archivos almacenados en tmpfs se pierden al reiniciar. |
| Enable mounts | To enable an option, download the script and edit its optional mount block before executing it. For the 2 GB option, uncomment all three lines: <code>failure_message</code>, <code>grep</code> and <code>echo</code>. The examples below show the resulting <code>fstab</code> entries. | Para habilitar una opción, descargue el script y edite su bloque de montajes opcionales antes de ejecutarlo. Para la opción de 2 GB, descomente las tres líneas: <code>failure_message</code>, <code>grep</code> y <code>echo</code>. Los ejemplos siguientes muestran las entradas resultantes de <code>fstab</code>. |

```bash
tmpfs /tmp tmpfs defaults,size=2G,nofail,noatime,mode=1777 0 0      # /tmp as tmpfs, 2 GB limit / /tmp como tmpfs, límite de 2 GB
tmpfs /tmp tmpfs defaults,size=30%,nofail,noatime,mode=1777 0 0     # /tmp as tmpfs, 30% of RAM / /tmp como tmpfs, 30 % de la RAM
none /run/shm tmpfs defaults,ro 0 0                                 # read-only shared memory / memoria compartida de solo lectura
```

### Setup Parameters

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     During installation, the script will detect your network interfaces and ask you to confirm or replace the following default values. The selected mask determines the LAN prefix. Configuration files are adapted during installation; the PAC is generated directly.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Durante la instalación, el script detectará sus interfaces de red y le pedirá confirmar o reemplazar los siguientes valores por defecto. La máscara elegida determina el prefijo LAN. Los archivos se adaptan durante la instalación; el PAC se genera directamente.
    </td>
  </tr>
</table>

| Parameter | Default | Description | Descripción |
| :--- | :---: | :--- | :--- |
| WAN Interface | none (required) | Chosen from a numbered list of detected interfaces, with explicit `y/n` confirmation before continuing. Nothing is typed and there is no silent default | Se elige de una lista numerada de interfaces detectadas, con confirmación explícita `y/n` antes de continuar. No se escribe nada y no hay valor silencioso |
| LAN Interface | none (required) | Same numbered list and confirmation flow as the WAN interface. It cannot be the interface already assigned to WAN | Mismo flujo de lista numerada y confirmación que la interfaz WAN. No puede ser la interfaz ya asignada a WAN |
| Server IP | `192.168.0.10` | Gateway IP assigned to this server | IP del servidor en la LAN |
| Netmask | `255.255.255.0` | Configurable subnet mask. The CIDR prefix is derived from it; `/24` corresponds only to the default | Máscara de subred configurable. El prefijo CIDR se calcula desde ella; `/24` corresponde solo al valor inicial |
| DNS Primary | `1.1.1.2` | Primary DNS server | DNS primario |
| DNS Secondary | `1.0.0.2` | Secondary DNS server | DNS secundario |
| Proxy Port | `3128` | Squid proxy port | Puerto del proxy Squid |
| Squid Intercept Port | `3129` | Squid intercept port | Puerto transparente de Squid |

#### Where the Values Go

| Function | Description | Descripción |
| :--- | :--- | :--- |
| Localnet | Localnet (<code>192.168.0.0</code>) is derived from the Server IP and Netmask together, not asked separately. | Localnet (<code>192.168.0.0</code>) se deriva del Server IP y la Netmask en conjunto, no se pregunta por separado. |
| Client DNS | <ul><li>DNS Primary/Secondary only configure Unbound's own forwarders (<code>conf/unbound/forward.conf</code>), where Unbound sends queries it cannot answer locally.</li><li>They do <b>not</b> control which DNS server LAN clients may query directly.</li><li>That is pydhcp's <code>SERV_DNS</code> key in <code>pydhcp.env</code>, the same value pydhcp hands out via DHCP, which <code>iptables.sh</code> reads to open the matching firewall access.</li><li>Installation sets it to the Server IP (Unbound).</li><li>If it is missing, empty or malformed, <code>iptables.sh</code> aborts during key validation.</li><li>To have clients reach external DNS directly, edit <code>SERV_DNS</code> by hand, regenerate <code>pydhcpd.conf</code> with pydhcp's <code>pyleases.sh</code>, restart <code>pydhcpd</code>, and re-run <code>iptables.sh</code>.</li></ul> | <ul><li>Los DNS Primario y Secundario solo configuran los reenviadores propios de Unbound (<code>conf/unbound/forward.conf</code>), a donde Unbound manda las consultas que no resuelve localmente. <b>No</b> controlan a qué servidor DNS pueden consultar directamente los clientes de la LAN.</li><li>Eso lo controla la clave <code>SERV_DNS</code> de pydhcp en <code>pydhcp.env</code>, el mismo valor que pydhcp entrega por DHCP, que <code>iptables.sh</code> lee para abrir el acceso en el firewall.</li><li>La instalación le asigna el Server IP (Unbound).</li><li>Si falta, está vacía o tiene formato inválido, <code>iptables.sh</code> aborta durante la validación de claves.</li><li>Para que los clientes alcancen DNS externo directamente, edita <code>SERV_DNS</code> a mano, regenera <code>pydhcpd.conf</code> con <code>pyleases.sh</code> de pydhcp, reinicia <code>pydhcpd</code> y vuelve a correr <code>iptables.sh</code>.</li></ul> |
| Installer configuration | <ul><li>GateProxy configures the interfaces first, then passes LAN, WAN and the server IPv4 to <code>pysetup.sh</code>.</li><li>PyDHCP detects that prefix and writes the IP, network and mask into <code>pydhcp.env</code>.</li><li>DNS and pool answers are supplied through <code>expect</code>.</li><li>Once pydhcp is installed, the script substitutes its own values (WAN interface, proxy port) into <code>conf/</code> with <code>sed</code> before deploying, so they end up in the firewall script itself.</li><li>It never writes into <code>pydhcp.env</code>, which belongs to pydhcp.</li><li>There is no "reuse previous answers" step: each run asks fresh.</li></ul> | <ul><li>GateProxy configura primero las interfaces y envía LAN, WAN y la IPv4 del servidor a <code>pysetup.sh</code>.</li><li>PyDHCP detecta ese prefijo y escribe IP, red y máscara en <code>pydhcp.env</code>.</li><li>Las respuestas de DNS y pool se envían mediante <code>expect</code>.</li><li>Una vez instalado pydhcp, el script sustituye sus propios valores (interfaz WAN, puerto del proxy) dentro de <code>conf/</code> con <code>sed</code> antes de desplegar, así que quedan en el propio script del firewall.</li><li>Nunca escribe en <code>pydhcp.env</code>, que pertenece a pydhcp.</li><li>No existe un paso de "reusar respuestas anteriores": cada corrida pregunta de nuevo.</li></ul> |

### Components

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy installs and configures the following components automatically.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy instala y configura los siguientes componentes automáticamente.
    </td>
  </tr>
</table>

#### Projects

| Project | Description | Descripción |
| :--- | :--- | :--- |
| [pydhcp](https://github.com/maravento/pydhcp) | DHCP server | Servidor DHCP |
| [smbstack](https://github.com/maravento/smbstack) | Samba file server | Servidor de archivos Samba |
| [proxymon](https://github.com/maravento/proxymon) | Bandwidth monitoring and quotas | Monitoreo de ancho de banda y cuotas |
| [suridata](https://github.com/maravento/vault/tree/master/suridata) | Suricata IDS with ipset blocking | IDS Suricata con bloqueo ipset |

> Each project is installed and configured by its own installer, and documents its own behavior, configuration and limits. Gateproxy only supplies the network values and consumes the results.
>
> Cada proyecto se instala y configura con su propio instalador, y documenta su comportamiento, configuración y límites. Gateproxy solo aporta los valores de red y consume los resultados.

#### Proxy

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     During installation, the Squid port configuration asks for both ports. Defaults: proxy <code>3128</code>, intercept <code>3129</code>. Gateproxy applies the selected ports to its configuration files and passes both values to Proxymon. Proxymon writes them as <code>SQUID_MGR_PORT</code> and <code>SQUID_INTERCEPT_PORT</code> in <code>proxymon.env</code>, without asking again.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Durante la instalación, la configuración de puertos Squid pregunta ambos valores. Valores iniciales: proxy <code>3128</code>, transparente <code>3129</code>. Gateproxy aplica los puertos elegidos a sus archivos y pasa ambos valores a Proxymon. Proxymon los escribe como <code>SQUID_MGR_PORT</code> y <code>SQUID_INTERCEPT_PORT</code> en <code>proxymon.env</code>, sin volver a preguntar.
    </td>
  </tr>
</table>

| Component | Port | Description | Descripción |
| :--- | :---: | :--- | :--- |
| Squid (squid-openssl) | `3128` | Explicit proxy with rock/ufs cache | Proxy explícito con caché rock/ufs |
| Squid (squid-openssl) | `3129` | Intercept port for captive-portal probes and clients not using the PAC, filtered by the same ACLs | Puerto transparente para sondeos de portal cautivo y clientes sin PAC, filtrados por las mismas ACL |
| WPAD/PAC (Apache2) | `18100` | Proxy auto-config served via `wpad.pac` | Autoconfiguración de proxy servida por `wpad.pac` |
| Proxymon | `18080` | Bandwidth monitoring dashboard | Panel de monitoreo de ancho de banda |
| Proxymon | `18081` | Bandwidth quota warning page (bandata redirect) | Página de aviso de cuota (redirección de bandata) |

#### Web / Admin

| Component | Port | Description | Descripción |
| :--- | :---: | :--- | :--- |
| Apache2 | `80` | Web server with PHP support; hosts WPAD and admin pages | Servidor web con PHP; aloja WPAD y las páginas de administración |
| Webmin | `10000` | Server administration panel (`https://localhost:10000`) | Panel de administración del servidor (`https://localhost:10000`) |
| Webmin: Text Editor | `10000` | Edit ACL files from the browser | Editar archivos ACL desde el navegador |
| Webmin: Service Monitor (`servicemon`) | `10000` | Watch and restart services | Monitorear y reiniciar servicios |
| Webmin: Netplan Manager (`netplanmgr`) | `10000` | Manage network configuration | Gestionar configuración de red |

#### DHCP

| Component | Config | Description | Descripción |
| :--- | :--- | :--- | :--- |
| pydhcp | `/etc/pydhcp/core/pydhcpd.conf` | Python-based DHCP server; default pool range 220–235 | Servidor DHCP en Python; rango de pool inicial 220–235 |

> Pool range and other DHCP settings can be changed in `/etc/pydhcp/pydhcp.env` after installation.
>
> El rango del pool y otros parámetros DHCP pueden modificarse en `/etc/pydhcp/pydhcp.env` luego de la instalación.

#### DNS

| Component | Config | Description | Descripción |
| :--- | :--- | :--- | :--- |
| Unbound | `/etc/unbound/unbound.conf.d/forward.conf` | Forwarding resolver, not recursive. Listens on `127.0.0.1` and the server IP, and forwards to `1.1.1.2` and `1.0.0.2`. DHCP clients receive the server IP as their DNS server. | Resolutor de reenvío, no recursivo. Escucha en `127.0.0.1` y en la IP del servidor, y reenvía a `1.1.1.2` y `1.0.0.2`. Los clientes DHCP reciben la IP del servidor como su DNS. |

#### Security / Monitoring

| Component | Port | Description | Descripción |
| :--- | :---: | :--- | :--- |
| Suricata IDS | — | Intrusion detection in AF-PACKET mode with auto-update rules; community-id enabled | Detección de intrusiones en modo AF-PACKET con reglas autoactualizadas; community-id activo |
| suridata | — | Turns `drop.conf` matches into blocks through the `suridata` ipset; cron every 5 minutes | Convierte las coincidencias de `drop.conf` en bloqueos mediante el ipset `suridata`; cron cada 5 minutos |
| EveBox | `5636` | Suricata event browser (`http://localhost:5636`) | Visor de eventos de Suricata (`http://localhost:5636`) |
| fail2ban | — | Brute-force protection with custom jail config | Protección contra fuerza bruta con jaulas propias |
| ttyd | `7681` | Web terminal, loopback only (`http://localhost:7681`) | Terminal web, solo en loopback (`http://localhost:7681`) |

#### Net Tools

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Command-line tools for the administrator. No script of the stack invokes them.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Herramientas de línea de comandos para el administrador. Ningún script del stack las invoca.
    </td>
  </tr>
</table>

| Tool | Purpose | Propósito |
| :--- | :--- | :--- |
| `iw` | Wireless interfaces (`iwconfig`, `iwlist`, `iwpriv`) | Interfaces inalámbricas (`iwconfig`, `iwlist`, `iwpriv`) |
| `fping`, `ethtool` | Host reachability and NIC settings | Alcance de hosts y ajustes de la tarjeta de red |
| `iperf3` | Throughput test (server: `iperf3 -s`, client: `iperf3 -c SERVER_IP`) | Prueba de rendimiento (servidor: `iperf3 -s`, cliente: `iperf3 -c SERVER_IP`) |
| `masscan`, `nmap`, `python3-nmap`, `ndiff` | Port scanning and scan comparison | Escaneo de puertos y comparación de escaneos |
| `nbtscan`, `nast`, `arp-scan`, `arping`, `netdiscover` | LAN discovery over NetBIOS and ARP | Descubrimiento de la LAN por NetBIOS y ARP |
| `traceroute`, `mtr-tiny` | Path tracing to a domain or IP | Trazado de ruta hacia un dominio o IP |

#### Backup

| Component | Description | Descripción |
| :--- | :--- | :--- |
| Timeshift | System snapshots | Instantáneas del sistema |
| FreeFileSync | File mirror sync, updated weekly by `/etc/scr/ffsupdate.sh` | Sincronización espejo de archivos, actualizada cada semana por `/etc/scr/ffsupdate.sh` |
| `bkconf.sh` | Configuration archive; only the last 3 are kept | Archivo de configuración; solo se conservan los 3 últimos |

#### ACL Structure

| Function | Description | Descripción |
| :--- | :--- | :--- |
| ACL deployment | All access control lists are stored under <code>/etc/acl/</code>, organized by service. Files are deployed from the repository only if missing (an existing file, from a previous install or from another project sharing this path, is never overwritten) and managed by Webmin's Text Editor module. | Todas las listas de control de acceso se almacenan en <code>/etc/acl/</code>, organizadas por servicio. Los archivos se despliegan desde el repositorio solo si faltan (uno ya existente, de una instalación previa o de otro proyecto que comparte esta ruta, nunca se sobreescribe) y se administran con el módulo Text Editor de Webmin. |
| MAC entry format | MAC list files use pydhcp's own entry format: <code>a;MAC;IP;HOSTNAME;</code>. The leading <code>a</code> marks an active entry — <code>iptables.sh</code> only reads lines starting with <code>a;</code> and a non-empty MAC field; anything else (including a different leading character or a commented-out <code>#a;...</code> line) is ignored. | Los archivos de listas MAC usan el mismo formato de entrada que pydhcp: <code>a;MAC;IP;HOSTNAME;</code>. La <code>a</code> inicial marca una entrada activa — <code>iptables.sh</code> sólo lee líneas que empiecen con <code>a;</code> y tengan el campo MAC no vacío; cualquier otra cosa (incluido un carácter inicial distinto o una línea comentada <code>#a;...</code>) se ignora. |

```
/etc/acl/
├── mac/                    # MAC address lists for iptables ipsets
│   ├── mac-limited.txt           # MACs routed through Squid (port 3128)
│   └── mac-unlimited.txt       # MACs with unrestricted access (APs, switches)
├── squid/                  # Squid proxy ACLs
│   ├── aipextra.txt            # Additional allowed IPs (bypass blacklist)
│   ├── allowdomains.txt        # Allowed domains (whitelist)
│   ├── blockdomains.txt        # Blocked domains (blacklist)
│   ├── blockext.txt            # Blocked file extensions
│   ├── blockmime.txt           # Blocked MIME types
│   └── blockpatterns.txt       # Blocked URL patterns (BitTorrent, scrapers…)
└── ipt/                    # iptables ACLs
    ├── blockports.txt          # Blocked port ranges (VPN, P2P, cryptomining…)
    ├── bogons.txt              # Bogon/unroutable IP ranges
    ├── dhcp_ip.txt             # IP list derived from DHCP leases (auto-generated by iptables.sh)
    └── dhcp_mac.txt            # MAC list derived from DHCP leases (auto-generated by iptables.sh)
```

> Suricata's blocklist (`suridata.txt`) is not under `/etc/acl/`: it lives in `/etc/suricata/data/suridata.txt`, generated by `suridata.sh`. MACs blocked from a DHCP lease (`blockdhcp.txt`) belong to pydhcp and live at `/etc/acl/dhcp/blockdhcp.txt`, in its own namespace inside `/etc/acl/`.
>
> La lista de bloqueo de Suricata (`suridata.txt`) no está en `/etc/acl/`: vive en `/etc/suricata/data/suridata.txt`, generada por `suridata.sh`. Las MAC bloqueadas por concesión DHCP (`blockdhcp.txt`) pertenecen a pydhcp y viven en `/etc/acl/dhcp/blockdhcp.txt`, en su propio espacio dentro de `/etc/acl/`.

#### Firewall

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     The firewall (<code>iptables.sh</code>) uses an O(1) ipset-based architecture. Every LAN device is identified by MAC+IP binding derived from the DHCP server config. Global IPv4 policy is permissive with explicit drops; IPv6 is closed by default on LAN.
    </td>
    <td style="width: 50%; vertical-align: top;">
     El firewall (<code>iptables.sh</code>) usa una arquitectura basada en ipset O(1). Cada dispositivo LAN es identificado por enlace MAC+IP derivado de la configuración del servidor DHCP. La política IPv4 global es permisiva con drops explícitos; IPv6 está cerrado por defecto en LAN.
    </td>
  </tr>
</table>

| Component | Config | Description | Descripción |
| :--- | :--- | :--- | :--- |
| iptables + ipset | `/etc/scr/iptables.sh` | Stateful firewall with MAC-based access control | Firewall con estado y control de acceso por MAC |
| ulogd2 | `/var/log/ulog/syslogemu.log` | Kernel-level packet logging via NFLOG | Registro de paquetes a nivel de kernel mediante NFLOG |

##### ipsets

| ipset | Type | Description | Descripción |
| :--- | :--- | :--- | :--- |
| `macunlimited` | `hash:mac` | Full bypass for APs, managed switches and similar infrastructure. It also **requires a matching static reservation in `pydhcpd.conf`**, because `MACCHECK` checks `macip`, not this list | Acceso total para APs, switches administrables e infraestructura similar. Además **exige una reserva estática en `pydhcpd.conf`**, porque `MACCHECK` consulta `macip`, no esta lista |
| `maclimited` | `hash:mac` | Routed through Squid: explicit via PAC (port 3128, served on 18100), or intercepted (port 3129) for HTTP without PAC. Same reservation requirement as `macunlimited` | Enrutados por Squid: explícito por PAC (puerto 3128, servido en 18100), o transparente (puerto 3129) para HTTP sin PAC. Misma exigencia de reserva que `macunlimited` |
| `macports` | `hash:mac` | Registered devices with controlled port access. Same reservation requirement as `macunlimited` | Dispositivos registrados con acceso controlado a puertos. Misma exigencia de reserva que `macunlimited` |
| `macip` | `hash:ip,mac` | <ul><li>MAC and IP binding, built from the static <code>host {}</code> blocks in <code>pydhcpd.conf</code>, not directly from <code>mac-*.txt</code>.</li><li>Adding a MAC to <code>mac-unlimited.txt</code> or <code>mac-limited.txt</code> classifies it but does <strong>not</strong> grant network access by itself.</li><li>A device without a matching static reservation is dropped by <code>MACCHECK</code> before the other lists are evaluated.</li><li>pydhcp provides <code>tools/pyleases.sh</code> to generate those reservations from the same <code>mac-*.txt</code> files.</li><li>Run it after editing any of them, or add the reservation by hand; no installer schedules it.</li></ul> | <ul><li>Enlace MAC e IP, construido desde los bloques estáticos <code>host {}</code> de <code>pydhcpd.conf</code>, no directamente desde <code>mac-*.txt</code>.</li><li>Agregar una MAC a <code>mac-unlimited.txt</code> o <code>mac-limited.txt</code> la clasifica, pero <strong>no</strong> concede acceso a la red por sí solo.</li><li>Un dispositivo sin reserva estática coincidente se descarta mediante <code>MACCHECK</code> antes de evaluar las demás listas.</li><li>pydhcp proporciona <code>tools/pyleases.sh</code> para generar esas reservas desde los mismos archivos <code>mac-*.txt</code>.</li><li>Ejecútalo después de editar cualquiera de ellos, o agrega la reserva a mano; ningún instalador lo programa.</li></ul> |
| `blockports` | `bitmap:port` | Blocked port ranges (VPN tunnels, P2P, cryptomining, legacy protocols) | Rangos de puertos bloqueados (túneles VPN, P2P, criptominería, protocolos obsoletos) |
| `suridata` | `hash:ip` | Destination IPs flagged by Suricata alerts matching a `drop.conf` signature; silent `DROP` | IP de destino marcadas por alertas de Suricata que coinciden con `drop.conf`; `DROP` silencioso |
| `bandata` | `hash:ip` | IPs over bandwidth quota, left with DNS and port 80 only and redirected to a warning page. Proxymon creates and fills it, not `iptables.sh`, which only opens port 18081 for the warning page | IP que superaron la cuota, con solo DNS y puerto 80, redirigidas a una página de aviso. La crea y llena Proxymon, no `iptables.sh`, que solo abre el puerto 18081 para esa página |

##### Blocked Ports (`blockports.txt`)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <code>blockports.txt</code> holds the ports blocked outbound from the LAN by default, one per line. They cover VPNs and tunnels, P2P, cryptomining, Tor, alternate proxies and legacy or risky protocols. The list is the ACL itself, so consult the file for the current entries.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <code>blockports.txt</code> contiene los puertos bloqueados por defecto en tráfico saliente desde la LAN, uno por línea. Cubren VPN y túneles, P2P, criptominería, Tor, proxies alternativos y protocolos antiguos o riesgosos. La lista es la ACL misma, así que las entradas vigentes se consultan en el archivo.
    </td>
  </tr>
</table>

##### Suricata-driven IP Blocking (`suridata`)

| Function | Description | Descripción |
| :--- | :--- | :--- |
| Alert processing | <ul><li>Suricata runs passive (AF-PACKET, IDS mode) — it can never block traffic on its own, regardless of what <code>drop.conf</code> says. <code>suridata.sh</code> (cron, every 5 minutes) is what turns a <code>drop.conf</code> match into a real block: it reads the SIDs <code>suricata-update</code> already resolved to <code>drop</code> action in <code>suricata.rules</code> (covers both literal SIDs and <code>re:</code> message-regex entries in <code>drop.conf</code>), tails only the new lines of <code>eve.json</code> since its last run, and for every alert whose <code>signature_id</code> matches, appends the flow's <code>dest_ip</code> to <code>suridata.txt</code>. <code>iptables.sh</code> loads that file into the <code>suridata</code> ipset and drops matching destinations at <code>mangle PREROUTING</code> — silently, no warning page (unlike <code>bandata</code>, this blocks a destination, not a client).</li><li>No expiry: entries are removed by hand, same model as <code>blockports.txt</code>. <code>macunlimited</code> members (APs, switches) are exempt, same as <code>blockports</code>.</li></ul> | <ul><li>Suricata corre en modo pasivo (AF-PACKET, IDS) — nunca puede bloquear tráfico por sí solo, sin importar lo que diga <code>drop.conf</code>. <code>suridata.sh</code> (cron, cada 5 minutos) es lo que convierte un match de <code>drop.conf</code> en un bloqueo real: lee los SIDs que <code>suricata-update</code> ya resolvió a acción <code>drop</code> en <code>suricata.rules</code> (cubre tanto SIDs literales como entradas <code>re:</code> de regex de mensaje en <code>drop.conf</code>), lee solo las líneas nuevas de <code>eve.json</code> desde su última corrida, y por cada alerta cuyo <code>signature_id</code> coincide, agrega el <code>dest_ip</code> del flujo a <code>suridata.txt</code>. <code>iptables.sh</code> carga ese archivo al ipset <code>suridata</code> y bloquea los destinos que coincidan en <code>mangle PREROUTING</code> — de forma silenciosa, sin página de aviso (a diferencia de <code>bandata</code>, esto bloquea un destino, no un cliente).</li><li>Sin expiración: las entradas se retiran a mano, mismo modelo que <code>blockports.txt</code>.</li><li>Los miembros de <code>macunlimited</code> (APs, switches) quedan exentos, igual que con <code>blockports</code>.</li></ul> |
| Rule updates | <ul><li><b>Editing <code>drop.conf</code> / <code>disable.conf</code>:</b> <code>suricataupdate.sh</code> is the only script that reads these files and applies them to <code>suricata.rules</code>; it only runs once a day via cron (2 AM).</li><li>A SID you just added to <code>drop.conf</code> stays as plain <code>alert</code> (not blocked) until that cron runs.</li><li>To apply the change immediately, run both in order: <code>sudo /etc/suricata/suricataupdate.sh && sudo /etc/suricata/suridata.sh</code> — on that first <code>suridata.sh</code> run after the SID becomes <code>drop</code>, it also does a one-time full <code>eve.json</code> rescan for that SID (tracked via <code>suridata.sids</code>), so alerts that already fired earlier that day get backfilled into <code>suridata.txt</code> too, not just alerts from that point forward.</li></ul> | <ul><li><b>Al editar <code>drop.conf</code> / <code>disable.conf</code>:</b> <code>suricataupdate.sh</code> es el único script que lee estos archivos y los aplica a <code>suricata.rules</code>; corre una sola vez al día por cron (2 AM).</li><li>Una SID recién agregada a <code>drop.conf</code> queda como <code>alert</code> plano (sin bloquear) hasta que corra ese cron.</li><li>Para aplicar el cambio de inmediato, corre ambos en orden: <code>sudo /etc/suricata/suricataupdate.sh && sudo /etc/suricata/suridata.sh</code> — en esa primera corrida de <code>suridata.sh</code> después de que la SID pasa a <code>drop</code>, también hace un escaneo completo único de <code>eve.json</code> para esa SID (rastreado vía <code>suridata.sids</code>), así que las alertas que ya habían ocurrido ese mismo día también quedan agregadas a <code>suridata.txt</code>, no solo las de ahí en adelante.</li></ul> |
| Live blocking | Between reloads, <code>suridata.sh</code> also patches the live <code>suridata</code> ipset directly with any newly found IP, so a new block takes effect within one cron cycle instead of waiting for the next full firewall reload. | Entre recargas, <code>suridata.sh</code> también aplica directamente al ipset <code>suridata</code> en vivo cualquier IP recién encontrada, para que un nuevo bloqueo surta efecto en el mismo ciclo de cron, sin esperar la siguiente recarga completa del firewall. |
| Log cleanup | <b>Log cleanup:</b> <code>suricataclean.sh</code> runs monthly via cron and truncates Suricata's own logs. It is the third and last cron entry of the Suricata component, alongside <code>suricataupdate.sh</code> (daily, 2 AM) and <code>suridata.sh</code> (every 5 minutes). | <b>Limpieza de logs:</b> <code>suricataclean.sh</code> corre por cron una vez al mes y trunca los logs propios de Suricata. Es la tercera y última entrada de cron del componente Suricata, junto a <code>suricataupdate.sh</code> (diaria, 2 AM) y <code>suridata.sh</code> (cada 5 minutos). |
| Local exclusion | <ul><li><b>Local exclusion:</b> Suridata reads <code>SERV_SUBNET</code>, <code>SERV_MASK</code> and <code>WAN_IFACE</code> from <code>/etc/suricata/data/suridata.env</code>.</li><li>It excludes the complete configured LAN network and current WAN IPv4 networks, using their actual masks.</li><li>No <code>/24</code> is assumed.</li><li>Matching addresses already present are removed from the blocklist and live ipset.</li><li>Missing or invalid required network settings abort execution.</li><li>Suridata validates LAN/WAN IPv4 before installing its packages.</li><li>If runtime WAN IPv4 detection fails, it aborts before changing blocks; existing blocks remain unchanged.</li></ul> | <ul><li><b>Exclusión local:</b> Suridata lee <code>SERV_SUBNET</code>, <code>SERV_MASK</code> y <code>WAN_IFACE</code> desde <code>/etc/suricata/data/suridata.env</code>.</li><li>Excluye la red LAN completa y las redes IPv4 WAN actuales mediante sus máscaras reales.</li><li>No asume <code>/24</code>.</li><li>Retira direcciones coincidentes de la lista y del ipset activo.</li><li>Aborta si faltan ajustes de red requeridos o son inválidos.</li><li>Suridata valida IPv4 LAN/WAN antes de instalar sus paquetes.</li><li>Si falla detectar IPv4 WAN durante la ejecución, aborta antes de modificar bloqueos; conserva los existentes.</li></ul> |

##### Security Rules

| Description | Descripción |
| :--- | :--- |
| <ul><li>SYN flood protection via rate-limited <code>syn_flood</code> chain</li><li>TCP scan and malformed packet drops (SYN+FIN, SYN+RST, NEW with SYN+ACK)</li><li>Bittorrent, Tor and other protocol-level detection is handled by Suricata, not by hex-string matching in <code>iptables.sh</code></li><li>GRE (protocol 47) and 6to4 (protocol 41) blocked from LAN</li><li>Windows ICS network range (<code>192.168.137.0/24</code>) blocked</li><li>NetBIOS NMBD (137–139), CoAP (5683–5684), mDNS noise and WUDO WAN traffic blocked</li><li>Bogon and reserved-range filtering (RFC1918, link-local, test-nets) is available in <code>iptables.sh</code> but <strong>disabled by default</strong>. Enabling it blindly can lock the LAN out of its own network when the server's subnet falls inside a blocked RFC1918 range. Read the comment above the <code>BOGONS</code> block first.</li></ul> | <ul><li>Protección contra SYN flood mediante la cadena <code>syn_flood</code> con límite de tasa</li><li>Descarte de escaneos TCP y paquetes mal formados (SYN+FIN, SYN+RST, NEW con SYN+ACK)</li><li>La detección de Bittorrent, Tor y otros protocolos la hace Suricata, no la coincidencia hexadecimal en <code>iptables.sh</code></li><li>GRE (protocolo 47) y 6to4 (protocolo 41) bloqueados desde la LAN</li><li>Rango de red de Windows ICS (<code>192.168.137.0/24</code>) bloqueado</li><li>NetBIOS NMBD (137–139), CoAP (5683–5684), ruido mDNS y tráfico WUDO hacia WAN bloqueados</li><li>El filtrado de bogones y rangos reservados (RFC1918, link-local, test-nets) existe en <code>iptables.sh</code> pero está <strong>desactivado por defecto</strong>. Activarlo a ciegas puede dejar la LAN fuera de su propia red si la subred del servidor cae en un rango RFC1918 bloqueado. Lee antes el comentario sobre el bloque <code>BOGONS</code>.</li></ul> |

##### Allowed LAN Services (`macports`)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Devices registered in <code>macports</code> have access to the services below. DNS (UDP/TCP 53) is a global rule applied to all LAN traffic, not a <code>macports</code> privilege; see <code>SERV_DNS</code> above.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Los dispositivos registrados en <code>macports</code> tienen acceso a los servicios de abajo. DNS (UDP/TCP 53) es una regla global aplicada a todo el tráfico LAN, no un privilegio de <code>macports</code>; ver <code>SERV_DNS</code> arriba.
    </td>
  </tr>
</table>

<table width="100%">
  <tr><th>Service / Servicio</th><th>Ports / Puertos</th></tr>
  <tr><td>Printing / Impresión</td><td>JetDirect/RAW 9100, SNMP 161–162, prnrequest/prnstatus 3910–3911</td></tr>
  <tr><td>Email / Correo</td><td>SMTP 465, 587; IMAP 993; POP3 995; STARTTLS 143, 110</td></tr>
  <tr><td>Messaging / XMPP / Mensajería / XMPP</td><td>5222, 5223, 5228, 5269</td></tr>
  <tr><td>WebRTC / STUN-TURN / WebRTC / STUN-TURN</td><td>UDP 3478–3481, 19302–19309; TCP 3478, 5349</td></tr>
  <tr><td>Samba / SMB / Samba / SMB</td><td>TCP 445, 3092</td></tr>
  <tr><td>LAN discovery / Descubrimiento LAN</td><td>mDNS 5353, LLMNR 5355, SSDP/UPnP 1900, WSD 3702, IGMP</td></tr>
  <tr><td>KMS / KMS</td><td>Windows activation 1688</td></tr>
</table>

### Optional Packages

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     The installer offers three optional installation prompts at the end of the base setup.
    </td>
    <td style="width: 50%; vertical-align: top;">
     El instalador ofrece tres prompts de instalación opcionales al final de la configuración base.
    </td>
  </tr>
</table>

#### Optional GTK Pack

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Desktop applications. Only useful on a machine with a graphical session.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Aplicaciones de escritorio. Solo útiles en una máquina con sesión gráfica.
    </td>
  </tr>
</table>

| Package | Description | Descripción |
| :--- | :--- | :--- |
| `gparted` | Partition editor | Editor de particiones |
| `gnome-disk-utility` | GNOME disk manager | Gestor de discos de GNOME |
| `qdirstat` | Disk usage analyzer | Analizador de uso de disco |
| `baobab` | Disk usage analyzer (GNOME) | Analizador de uso de disco (GNOME) |
| `gsmartcontrol` | GUI for SMART disk health | Interfaz gráfica para la salud SMART |
| `cpu-x` | Hardware information viewer | Visor de información de hardware |
| `synaptic` | Graphical package manager | Gestor gráfico de paquetes |
| `gdebi` | Graphical `.deb` installer | Instalador gráfico de `.deb` |
| `gtkhash` | Checksum calculator | Calculadora de sumas de verificación |
| `wmctrl` | Window manager control | Control del gestor de ventanas |
| `mesa-utils` | OpenGL diagnostics (`glxinfo`, `glxgears`) | Diagnóstico de OpenGL (`glxinfo`, `glxgears`) |
| `fsearch` | Fast file search; adds an external PPA | Búsqueda rápida de archivos; agrega un PPA externo |
| `lynis` | Security auditing (`lynis -c -Q`; log at `/var/log/lynis.log`) | Auditoría de seguridad (`lynis -c -Q`; log en `/var/log/lynis.log`) |

#### Optional Pack: Samba

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Installs <b>smbstack</b> — a Samba server with a shared folder, Recycle Bin, and audit logging configured out of the box. <code>smbstack</code> manages its own veto list for common unwanted file types (<code>/etc/smbstack/acl/commonveto.txt</code>, active by default) — not gateproxy's responsibility.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Instala <b>smbstack</b> — un servidor Samba con carpeta compartida, Papelera de Reciclaje y registro de auditoría configurados de fábrica. <code>smbstack</code> gestiona su propia lista veto de tipos de archivo comunes no deseados (<code>/etc/smbstack/acl/commonveto.txt</code>, activa por defecto) — no es responsabilidad de gateproxy.
    </td>
  </tr>
</table>

#### Optional Pack: UHM

| Description | Descripción |
| :--- | :--- |
| <ul><li>This prompt only appears if a local UniFi Network controller is detected first — classic (<code>dpkg</code> package <code>unifi</code>) or unifi-os (<code>/var/lib/uosserver/server.conf</code>, podman-based).</li><li>If neither is found, the prompt is skipped entirely — gateproxy does not install UniFi or podman itself.</li><li>To install UniFi Network self-hosted / UniFi OS Server first, use <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/unifisetup.sh"><code>unifisetup.sh</code></a>, then re-run gateproxy (or run <code>uhmsetup.sh</code> from the <a href="https://github.com/maravento/uhm">uhm</a> repo directly).</li><li>Installs <b>uhm</b> (UniFi Hotspot Manager), which requires pydhcp already installed and running — a requirement gateproxy's own base setup already satisfies. <code>uhm</code> runs its own interactive installer (<code>uhmsetup.sh</code>): it reads pydhcp's network values from <code>pydhcp.env</code> automatically, then prompts for its own UniFi-specific settings (controller credentials, SSID, etc.) directly.</li></ul> | <ul><li>Este prompt sólo aparece si primero se detecta un controlador UniFi Network local — classic (paquete <code>dpkg</code> <code>unifi</code>) o unifi-os (<code>/var/lib/uosserver/server.conf</code>, basado en podman).</li><li>Si no se detecta ninguno, el prompt se omite por completo — gateproxy no instala UniFi ni podman por sí mismo.</li><li>Para instalar primero UniFi Network self-hosted / UniFi OS Server, use <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/unifisetup.sh"><code>unifisetup.sh</code></a>, y luego vuelva a ejecutar gateproxy (o ejecute <code>uhmsetup.sh</code> directamente desde el repo de <a href="https://github.com/maravento/uhm">uhm</a>).</li><li>Instala <b>uhm</b> (UniFi Hotspot Manager), que requiere tener pydhcp ya instalado y corriendo — requisito que la configuración base de gateproxy ya satisface. <code>uhm</code> ejecuta su propio instalador interactivo (<code>uhmsetup.sh</code>): lee automáticamente los valores de red de pydhcp desde <code>pydhcp.env</code>, y luego pregunta directamente por sus propios parámetros específicos de UniFi (credenciales del controlador, SSID, etc.).</li></ul> |

### Post-Install

#### Scripts (`/etc/scr/`)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The installer copies project scripts from <code>scr/</code> to <code>/etc/scr/</code> and downloads the external scripts listed below.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El instalador copia los scripts del proyecto desde <code>scr/</code> a <code>/etc/scr/</code> y descarga los scripts externos enumerados abajo.
    </td>
  </tr>
</table>

| Script | Source / Origen | Trigger | Description | Descripción |
| :--- | :--- | :--- | :--- | :--- |
| `iptables.sh` | `scr/` | manual | Load firewall rules and ipsets. Some deployed tools — <code>iptables.sh</code> here, and pydhcp's own <code>pyleases.sh</code> — are never added to cron automatically by any installer. Scheduling them (or not) is entirely up to the operator, based on their own needs. | Carga las reglas del firewall y los ipsets. Algunas herramientas desplegadas — <code>iptables.sh</code> aquí, y <code>pyleases.sh</code> de pydhcp — nunca se agregan al cron automáticamente por ningún instalador. Programarlas (o no) queda enteramente a criterio del operador, según sus necesidades. |
| `serverboot.sh` | `scr/` | manual (`alias server`) | Start or restart all server services | Inicia o reinicia todos los servicios del servidor |
| `serviceswatch.sh` | `scr/` | every 5 min | Restart failed services | Reinicia los servicios caídos |
| `killswitch.sh` | `scr/` | manual | Block all traffic in an emergency | Bloquea todo el tráfico en una emergencia |
| `bkconf.sh` | `scr/` | manual | Back up configuration files | Respalda los archivos de configuración |
| `hwclock.sh` | external / externo | `@reboot` | Sync hardware clock | Sincroniza el reloj de hardware |
| `blackusb.sh` | external / externo | `@reboot` | USB device access control. The cron entry runs `blackusb.sh --off`, so the udev rule is moved aside on every boot and the control starts deactivated. Activate it with `blackusb.sh --on` | Control de acceso a dispositivos USB. La entrada de cron ejecuta `blackusb.sh --off`, así que la regla udev se aparta en cada arranque y el control queda desactivado. Actívalo con `blackusb.sh --on` |
| `cleaner.sh` | external / externo | `@weekly` | System cleanup | Limpieza del sistema |
| `ffsupdate.sh` | external / externo | `@weekly` | Update FreeFileSync | Actualiza FreeFileSync |
| `filereport.sh` | external / externo | manual | Generate file system report | Genera un informe del sistema de archivos |

### PAC and Configuration Consistency

| Description | Descripción |
| :--- | :--- |
| <ul><li>GateProxy configures its interfaces before calling dependent installers. PyDHCP receives the selected LAN/WAN and server IPv4, then detects the configured prefix. During installation, <code>gpsetup.sh</code> generates <code>/var/www/wpad/wpad.pac</code> with the selected server IP and proxy port. LAN destinations use <code>isInNet</code> with <code>SERV_SUBNET</code> and <code>SERV_MASK</code>. Local names and loopback remain direct. No PAC template is deployed.</li><li>During installation, <code>gpsetup.sh</code> uses <code>sed -i</code> to replace placeholders with the selected values. Later edits are not synchronized automatically between files. If you change Squid ports after installation, keep <code>proxymon.env</code>, <code>squid.conf</code> and the corresponding WPAD/PAC settings aligned. <code>iptables.sh</code> reads the shared ports when it runs; editing <code>proxymon.env</code> alone does not apply firewall rules or update Squid. Editing only one file can leave the settings inconsistent and interrupt proxy access.</li></ul> | <ul><li>GateProxy configura sus interfaces antes de invocar los instaladores dependientes. PyDHCP recibe LAN/WAN y la IPv4 del servidor; después detecta el prefijo configurado. Durante la instalación, <code>gpsetup.sh</code> genera <code>/var/www/wpad/wpad.pac</code> con la IP del servidor y puerto proxy seleccionados. Los destinos LAN utilizan <code>isInNet</code> con <code>SERV_SUBNET</code> y <code>SERV_MASK</code>. Los nombres locales y loopback conservan acceso directo. No se despliega una plantilla PAC.</li><li>Durante la instalación, <code>gpsetup.sh</code> utiliza <code>sed -i</code> para sustituir marcadores por los valores elegidos. Los cambios posteriores no se sincronizan automáticamente entre archivos. Si cambia los puertos de Squid, mantenga alineados <code>proxymon.env</code>, <code>squid.conf</code> y la configuración WPAD/PAC correspondiente. <code>iptables.sh</code> lee los puertos compartidos cuando se ejecuta. Editar solamente <code>proxymon.env</code> no aplica reglas del firewall ni actualiza Squid. Modificar solamente un archivo puede dejar valores incompatibles e interrumpir el acceso al proxy.</li></ul> |

> **⚠️ WARNING -- Manual configuration changes:** Keep Squid, Proxymon, WPAD/PAC and firewall settings aligned after manual changes.
>
> **⚠️ WARNING -- Manual configuration changes:** Mantenga alineados Squid, Proxymon, WPAD/PAC y el firewall después de cambios manuales.

> **⚠️ WARNING -- Intended environment:** Gateproxy is a script designed for very specific network environments (see Requirements above for the supported OS/version). It is not intended for general or production use. Using it outside the environment for which it was designed may cause unexpected behavior or system misconfiguration. Use at your own risk.
>
> **⚠️ WARNING -- Intended environment:** Gateproxy es un script diseñado para entornos de red muy específicos (ver Requirements arriba para el SO/versión soportada). No está destinado para uso general ni en producción. Usarlo fuera del entorno para el que fue diseñado puede causar comportamientos inesperados o una mala configuración del sistema. Úselo bajo su propio riesgo.

## NOTICE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>This repository</strong>
      <ul>
        <li>May include third-party components.</li>
        <li>Does not accept Pull Requests. Changes must be proposed via Issues.</li>
        <li>This project does not support backward compatibility. New versions may require configuration changes or reinstallation.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Este repositorio</strong>
      <ul>
        <li>Puede incluir componentes de terceros.</li>
        <li>No acepta Pull Requests. Los cambios deben proponerse mediante Issues.</li>
        <li>Este proyecto no soporta retrocompatibilidad. Las nuevas versiones pueden requerir cambios de configuración o una reinstalación.</li>
      </ul>
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
