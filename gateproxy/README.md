# [Gateproxy](https://github.com/maravento)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> is a modular ecosystem for the administration and management of LAN environments in small and medium-sized businesses, comprising independent projects and components that can be used autonomously but are designed to interoperate within the same environment. Its architecture integrates tools and services such as Proxymon, pydhcp, smbstack, uhm, Apache2, iptables/ipset, suricata, unbound, among others, providing proxy, firewall, DHCP, traffic control and management, web services, and other resources required for network operation. The installation and configuration script automates the deployment of these components and can be adapted to the needs of the administrator or organization, requiring minimal interaction during the process. Some projects are included as part of the base configuration, while others are offered as optional installations. Gateproxy can be deployed on both physical servers and virtual machines, providing flexibility and portability for different infrastructure environments.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> es un ecosistema modular para la administración y gestión de redes LAN de pequeñas y medianas empresas, compuesto por proyectos y componentes independientes que pueden utilizarse de forma autónoma, pero que pueden interoperar dentro de un mismo entorno. Su arquitectura integra herramientas y servicios como Proxymon, pydhcp, smbstack, uhm, Apache2, iptables/ipset, suricata, unbound, entre otros, proporcionando funciones de proxy, firewall, DHCP, control y administración del tráfico, servicios web y otros recursos necesarios para la operación de la red. El script de instalación y configuración automatiza el despliegue de estos componentes y puede adaptarse a las necesidades del administrador u organización, procurando una interacción mínima durante el proceso. Algunos proyectos forman parte de la configuración base, mientras que otros se ofrecen como instalaciones opcionales. Puede implementarse tanto en servidores físicos como en máquinas virtuales, proporcionando flexibilidad y portabilidad para diferentes escenarios de infraestructura.
    </td>
  </tr>
</table>

## Requirements

---

**⚠️ WARNING:** Only tested on Ubuntu 24.04 LTS. Other versions or distros not tested, use at your own risk.

| CPU | NIC | RAM | Storage |
| :---: | :---: | :---: | :---: |
| 4+ cores (≥ 3.0 GHz) | 2 (WAN & LAN) | 12+ GB (4 GB cache_mem) | 100 GB SSD (cache_dir rock) |

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Run the following command on a fresh installation. The script must be executed as root or with <code>sudo</code>. It will self-delete after completion and reboot the system automatically.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Ejecute el siguiente comando en una instalación limpia. El script debe ejecutarse como root o con <code>sudo</code>. Se eliminará automáticamente al finalizar y reiniciará el sistema.
    </td>
  </tr>
</table>

```bash
wget -qO gateproxy.sh https://raw.githubusercontent.com/maravento/vault/master/gateproxy/gateproxy.sh && sudo bash gateproxy.sh
```

![Gateproxy](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/img/gateproxy.png)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Before installing anything, the script checks for conflicting software already on the system: <code>isc-dhcp-server</code>/<code>dnsmasq</code> (DHCP), <code>squid</code>/<code>squid3</code>/<code>tinyproxy</code>/<code>privoxy</code>/<code>3proxy</code> (proxy), <code>nginx</code>/<code>lighttpd</code>/<code>caddy</code> (web server), <code>bind9</code>/<code>pdns-recursor</code> (DNS server), <code>syslog-ng</code>, <code>firewalld</code>, <code>snort</code>, or an active <code>ufw</code>. If any of these are present, the installer aborts with instructions to remove them first.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Antes de instalar nada, el script verifica que no haya software en conflicto ya presente: <code>isc-dhcp-server</code>/<code>dnsmasq</code> (DHCP), <code>squid</code>/<code>squid3</code>/<code>tinyproxy</code>/<code>privoxy</code>/<code>3proxy</code> (proxy), <code>nginx</code>/<code>lighttpd</code>/<code>caddy</code> (servidor web), <code>bind9</code>/<code>pdns-recursor</code> (servidor DNS), <code>syslog-ng</code>, <code>firewalld</code>, <code>snort</code>, o un <code>ufw</code> activo. Si detecta alguno, el instalador aborta con instrucciones para removerlo primero.
    </td>
  </tr>
</table>

## SETUP PARAMETERS

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     During installation, the script will detect your network interfaces and ask you to confirm or replace the following default values. All parameters are applied across configuration files automatically via <code>sed</code> replacement.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Durante la instalación, el script detectará sus interfaces de red y le pedirá confirmar o reemplazar los siguientes valores por defecto. Todos los parámetros se aplican automáticamente en los archivos de configuración mediante reemplazo con <code>sed</code>.
    </td>
  </tr>
</table>

| Parameter | Default | Description / Descripción |
| :--- | :---: | :--- |
| WAN Interface | none (required) | Chosen from a numbered list of detected interfaces, with explicit `y/n` confirmation before continuing -- no typing, no silent default / Se elige de una lista numerada de interfaces detectadas, con confirmación explícita `y/n` antes de continuar -- no se escribe, no hay default silencioso |
| LAN Interface | none (required) | Same numbered-list + confirmation flow as WAN Interface; cannot be the same interface already assigned to WAN / Mismo flujo de lista numerada + confirmación que WAN Interface; no puede ser la misma interfaz ya asignada a WAN |
| Server IP | `192.168.0.10` | Gateway IP assigned to this server / IP del servidor en la LAN |
| Netmask | `255.255.255.0` | Subnet mask; CIDR prefix (`/24`) is derived from this automatically, not asked separately / Máscara de subred; el prefijo CIDR (`/24`) se calcula automáticamente a partir de esto, no se pregunta por separado |
| DNS Primary | `8.8.8.8` | Primary DNS server / DNS primario |
| DNS Secondary | `8.8.4.4` | Secondary DNS server / DNS secundario |
| Proxy Port | `3128` | Squid proxy port / Puerto del proxy Squid |

Localnet (`192.168.0.0`) is derived automatically from the Server IP and Netmask together, not asked separately / Localnet (`192.168.0.0`) se deriva automáticamente del Server IP y la Netmask en conjunto, no se pregunta por separado.

DNS Primary/Secondary above only configure Unbound's own forwarders (`conf/server/forward.conf`) — where Unbound sends queries it can't answer locally. They do **not** control which DNS server LAN clients are allowed to query directly; that is pydhcp's own `SERV_DNS` key in `pydhcp.env` (the same value pydhcp hands out via DHCP), which `iptables.sh` reads to open the matching firewall access — no separate gateproxy key to keep in sync by hand. It defaults to the Server IP (Unbound); leaving it unset or empty falls back to the Server IP as well, never to `8.8.8.8`/`8.8.4.4`. To have clients use and reach external DNS directly instead of Unbound, edit `SERV_DNS` in `pydhcp.env` by hand, regenerate `pydhcpd.conf` with pydhcp's `pyleases.sh`, restart `pydhcpd`, and re-run `iptables.sh`.

Los DNS Primario/Secundario de arriba sólo configuran los reenviadores propios de Unbound (`conf/server/forward.conf`) — a dónde manda Unbound las consultas que no puede resolver localmente. **No** controlan a qué servidor DNS pueden consultar directamente los clientes de la LAN; eso lo controla la propia clave `SERV_DNS` de pydhcp en `pydhcp.env` (el mismo valor que pydhcp entrega por DHCP), que `iptables.sh` lee para abrir el acceso correspondiente en el firewall — no hay una clave aparte de gateproxy que sincronizar a mano. Por defecto es el Server IP (Unbound); dejarla sin definir o vacía también cae en el Server IP, nunca en `8.8.8.8`/`8.8.4.4`. Para que los clientes usen y puedan alcanzar DNS externo en vez de Unbound, hay que editar `SERV_DNS` a mano en `pydhcp.env`, regenerar `pydhcpd.conf` con `pyleases.sh` de pydhcp, reiniciar `pydhcpd`, y volver a correr `iptables.sh`.

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Once pydhcp is installed, the script appends its own values (WAN interface, proxy ports, path) to <code>/etc/pydhcp/pydhcp.env</code> — pydhcp's own persistent config file, in a "GATEPROXY CUSTOM VALUES" block after pydhcp's own section. LAN interface, IP, netmask and DNS are written instead by pydhcp's own <code>pysetup.sh</code>, from the values gateproxy passes it via <code>expect</code>. <code>iptables.sh</code> reads that same file at any time afterward. There is no "reuse previous answers" step — each run asks fresh.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Una vez instalado pydhcp, el script agrega sus propios valores (interfaz WAN, puertos del proxy, ruta) a <code>/etc/pydhcp/pydhcp.env</code> — el archivo de configuración persistente propio de pydhcp, en un bloque "GATEPROXY CUSTOM VALUES" después de la sección propia de pydhcp. La interfaz LAN, la IP, la máscara y el DNS los escribe en cambio el propio <code>pysetup.sh</code> de pydhcp, con los valores que gateproxy le pasa por <code>expect</code>. <code>iptables.sh</code> lee ese mismo archivo en cualquier momento después. No existe un paso de "reusar respuestas anteriores" — cada corrida pregunta de nuevo.
    </td>
  </tr>
</table>

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

## COMPONENTS

---

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

### Proxy

| Component | Port | Notes |
| :--- | :---: | :--- |
| **Squid** (squid-openssl) | `3128` | Explicit proxy with rock/ufs cache |
| **Squid** (squid-openssl) | `3129` | Intercept port — catches captive-portal probes and any client not using the PAC, filtered by the same ACLs as the explicit proxy |
| **WPAD/PAC** (Apache2) | `18100` | Proxy auto-config served via `wpad.pac` |
| **Proxymon** | `18080` | Bandwidth monitoring dashboard |
| **Proxymon** | `18081` | Bandwidth quota warning page (bandata redirect) |

### Web / Admin

| Component | Port | Notes |
| :--- | :---: | :--- |
| **Apache2** | `80` | Web server with PHP support; hosts WPAD and admin pages |
| **Webmin** | `10000` | Server administration panel (`https://localhost:10000`) |

Webmin is installed with the following modules / Webmin se instala con los siguientes módulos:

- **Text Editor** — edit ACL files directly from the browser / editar archivos ACL desde el navegador
- **Service Monitor** (`servicemon`) — watch and restart services / monitorear y reiniciar servicios
- **Netplan Manager** (`netplanmgr`) — manage network configuration / gestionar configuración de red

### DHCP

| Component | Config | Notes |
| :--- | :--- | :--- |
| **pydhcp** | `/etc/pydhcp/pydhcpd.conf` | Python-based DHCP server; default pool range 220–235 |

Pool range and other DHCP settings can be changed in `/etc/pydhcp/pydhcp.env` after installation / El rango del pool y otros parámetros DHCP pueden modificarse en `/etc/pydhcp/pydhcp.env` luego de la instalación.

### DNS

| Component | Config | Notes |
| :--- | :--- | :--- |
| **Unbound** | `/etc/unbound/unbound.conf.d/forward.conf` | Forwarding resolver (not recursive/iterative); listens on `127.0.0.1` and the server IP; forwards to `1.1.1.1`/`8.8.8.8`. DHCP clients receive the server IP as their DNS server. |

### Firewall

| Component | Config | Notes |
| :--- | :--- | :--- |
| **iptables + ipset** | `/etc/scr/iptables.sh` | Stateful firewall with MAC-based access control |
| **ulogd2** | `/var/log/ulog/syslogemu.log` | Kernel-level packet logging via NFLOG |

### Backup

| Component | Notes |
| :--- | :--- |
| **Timeshift** | System snapshots |
| **FreeFileSync** | File mirror sync; auto-updated weekly via `/etc/scr/ffsupdate.sh` |

## REPOSITORY STRUCTURE

---

```
gateproxy/
├── acl/                        # Default ACL files (deployed to /etc/acl/, see ACL STRUCTURE)
├── conf/
│   ├── pack/                   # Optional package configs, one subfolder per project
│   │   ├── evebox/
│   │   │   ├── evebox.service      # EveBox systemd unit
│   │   │   └── evebox.yaml         # EveBox configuration
│   │   ├── fail2ban/
│   │   │   └── jail.local          # fail2ban jail config
│   │   ├── suricata/
│   │   │   ├── disable.conf        # Suricata disabled rules
│   │   │   ├── drop.conf           # Suricata drop rules (converted alert->drop by suricata-update)
│   │   │   ├── suricataclean.sh    # Suricata log cleanup
│   │   │   ├── suricataupdate.sh   # Suricata rules update
│   │   │   └── suridata.sh         # Captures dest_ip from drop.conf-matched alerts into suridata.txt
│   │   └── ttyd/
│   │       └── ttyd.service        # ttyd (web terminal) systemd unit
│   ├── scr/                    # Scripts (deployed to /etc/scr/)
│   │   ├── bkconf.sh               # Backup configuration files
│   │   ├── iptables.sh             # Firewall rules and ipsets
│   │   ├── killswitch.sh           # Emergency traffic block
│   │   ├── serverboot.sh           # Start/restart all services
│   │   └── serviceswatch.sh        # Service watchdog
│   ├── server/                 # Server configuration files
│   │   ├── 000-add.txt             # Apache VirtualHost additions
│   │   ├── 00-networkd.yaml        # Netplan configuration
│   │   ├── forward.conf            # Unbound DNS forwarder configuration
│   │   ├── hosts.txt               # /etc/hosts additions
│   │   ├── servername.conf         # Apache ServerName config
│   │   ├── squid.conf              # Squid proxy configuration
│   │   ├── wpad.conf               # Apache WPAD virtual host
│   │   └── wpad.pac                # Proxy auto-config script
│   └── webmin/
│       └── text-editor.wbm         # Webmin Text Editor module
├── gateproxy.sh                # Main installer script
├── img/
│   └── gateproxy.png
└── README.md
```

## ACL STRUCTURE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     All access control lists are stored under <code>/etc/acl/</code>, organized by service. Files are deployed from the repository and managed by Webmin's Text Editor module.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Todas las listas de control de acceso se almacenan en <code>/etc/acl/</code>, organizadas por servicio. Los archivos son desplegados desde el repositorio y administrados por el módulo Text Editor de Webmin.
    </td>
  </tr>
</table>

```
/etc/acl/
├── acl_mac/                # MAC address lists for iptables ipsets
│   ├── mac-proxy.txt           # MACs routed through Squid (port 3128)
│   └── mac-unlimited.txt       # MACs with unrestricted access (APs, switches)
├── acl_dhcp/               # DHCP access control
│   └── blockdhcp.txt           # MACs blocked from a DHCP lease (empty seed, populated/managed by pydhcp's pyleases.sh)
├── acl_squid/              # Squid proxy ACLs
│   ├── aipextra.txt            # Additional allowed IPs (bypass blacklist)
│   ├── allowdomains.txt        # Allowed domains (whitelist)
│   ├── blockdomains.txt        # Blocked domains (blacklist)
│   ├── blockext.txt            # Blocked file extensions
│   ├── blockmime.txt           # Blocked MIME types
│   └── blockpatterns.txt       # Blocked URL patterns (BitTorrent, scrapers…)
└── acl_ipt/                # iptables ACLs
    ├── blockports.txt          # Blocked port ranges (VPN, P2P, cryptomining…)
    ├── bogons.txt              # Bogon/unroutable IP ranges
    ├── dhcp_ip.txt             # IP list derived from DHCP leases (auto-generated by iptables.sh)
    ├── dhcp_mac.txt            # MAC list derived from DHCP leases (auto-generated by iptables.sh)
    └── suridata.txt            # Dest IPs from Suricata alerts (auto-generated by suridata.sh)
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     MAC list files use pydhcp's own entry format: <code>a;MAC;IP;HOSTNAME;</code>. The leading <code>a</code> marks an active entry — <code>iptables.sh</code> only reads lines starting with <code>a;</code> and a non-empty MAC field; anything else (including a different leading character or a commented-out <code>#a;...</code> line) is ignored.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Los archivos de listas MAC usan el mismo formato de entrada que pydhcp: <code>a;MAC;IP;HOSTNAME;</code>. La `a` inicial marca una entrada activa — <code>iptables.sh</code> sólo lee líneas que empiecen con <code>a;</code> y tengan el campo MAC no vacío; cualquier otra cosa (incluido un carácter inicial distinto o una línea comentada <code>#a;...</code>) se ignora.
    </td>
  </tr>
</table>

## FIREWALL

---

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

### ipsets

| ipset | Type | Purpose |
| :--- | :--- | :--- |
| `macunlimited` | `hash:mac` | Full bypass — APs, managed switches, and similar infrastructure devices. **Requires a matching static reservation in `pydhcpd.conf`** in addition to being listed here — `MACCHECK` (see below) checks `macip`, not this list directly. Run pydhcp's `pyleases.sh` after editing this file, or add the reservation by hand |
| `macproxy` | `hash:mac` | Routed through Squid: explicit via PAC (port 3128, served on port 18100) for compliant clients, or intercepted (port 3129) for direct/non-PAC HTTP. Same `pydhcpd.conf` reservation requirement as `macunlimited` above |
| `macports` | `hash:mac` | Registered devices with controlled port access (DNS, printing, email, STUN, etc.). Same `pydhcpd.conf` reservation requirement as `macunlimited` above |
| `macip` | `hash:ip,mac` | MAC+IP binding, parsed from `pydhcpd.conf`. Gatekeeper for every other list below — a device not in `macip` is dropped before `macunlimited`/`macproxy`/`macports` are ever evaluated |
| `blockports` | `bitmap:port` | Blocked port ranges (VPN tunnels, P2P, cryptomining, legacy protocols) |
| `suridata` | `hash:ip` | Dest IPs flagged by Suricata alerts matching a `drop.conf` signature — silent `DROP`, see below |
| `bandata` | `hash:ip` | IPs over bandwidth quota — DNS and port 80 only, redirected to warning page. Created and populated by Proxymon, not by `iptables.sh` — Proxymon is installed by `gateproxy.sh` as a bundled optional component (see Optional Packages); `iptables.sh` only opens the warning-page port (18081) for it |

`macip` is built from `pydhcpd.conf`'s static `host {}` blocks, not from `mac-*.txt` directly. Adding a MAC to `mac-unlimited.txt`/`mac-proxy.txt` classifies it, but does **not** by itself grant it network access — it still needs a matching static reservation in `pydhcpd.conf`, or the firewall's `MACCHECK` step drops its traffic regardless of classification. pydhcp ships an optional tool, `tools/pyleases.sh`, that generates those reservations from the same `mac-*.txt` files — run it after editing any of them (it is not scheduled automatically by any installer, see the Scripts section below).

### Blocked Ports (`blockports.txt`)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     The following categories are blocked outbound from LAN by default.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Las siguientes categorías están bloqueadas por defecto en tráfico saliente desde la LAN.
    </td>
  </tr>
</table>

- **VPN / Tunnels** — HTTPS (443), DoT (853), DoQ (784), OpenVPN (1194), WireGuard (51820), L2TP (1701), IPsec (500, 4500), PPTP (1723), SOCKS5 (1080), Shadowsocks (7300), 6to4 (41–60, 3544)
- **P2P / Bittorrent** — ports 6881–6889, 6969, 58251, 58252, 58687
- **Cryptomining** — ports 3333, 5555, 6666, 7777, 8848, 9999, 14433, 14444, 45560
- **Tor** — ports 9001–9004, 9030, 9031, 9050, 9090, 9101–9103, 9150
- **Alternate proxies** — ports 8000, 3130
- **Legacy / risky** — FTP (20–21), SSH (22), Finger (79), IRC (6660–6669), CHARGEN (19), Echo (7), WINS (42), IPP (631), BTC/ETH (8332, 8333, 8545, 30303)

### Suricata-driven IP Blocking (`suridata`)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Suricata runs passive (AF-PACKET, IDS mode) — it can never block traffic on its own, regardless of what <code>drop.conf</code> says. <code>suridata.sh</code> (cron, every 5 minutes) is what turns a <code>drop.conf</code> match into a real block: it reads the SIDs <code>suricata-update</code> already resolved to <code>drop</code> action in <code>suricata.rules</code> (covers both literal SIDs and <code>re:</code> message-regex entries in <code>drop.conf</code>), tails only the new lines of <code>eve.json</code> since its last run, and for every alert whose <code>signature_id</code> matches, appends the flow's <code>dest_ip</code> to <code>suridata.txt</code>. <code>iptables.sh</code> loads that file into the <code>suridata</code> ipset and drops matching destinations at <code>mangle PREROUTING</code> — silently, no warning page (unlike <code>bandata</code>, this blocks a destination, not a client). No expiry: entries are removed by hand, same model as <code>blockports.txt</code>. <code>macunlimited</code> members (APs, switches) are exempt, same as <code>blockports</code>.
     <br><br>
     <strong>Editing <code>drop.conf</code> / <code>disable.conf</code>:</strong> <code>suricataupdate.sh</code> is the only script that reads these files and applies them to <code>suricata.rules</code>; it only runs once a day via cron (2 AM). A SID you just added to <code>drop.conf</code> stays as plain <code>alert</code> (not blocked) until that cron runs. To apply the change immediately, run both in order: <code>sudo /etc/suricata/suricataupdate.sh && sudo /etc/suricata/suridata.sh</code> — on that first <code>suridata.sh</code> run after the SID becomes <code>drop</code>, it also does a one-time full <code>eve.json</code> rescan for that SID (tracked via <code>suridata.sids</code>), so alerts that already fired earlier that day get backfilled into <code>suridata.txt</code> too, not just alerts from that point forward.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Suricata corre en modo pasivo (AF-PACKET, IDS) — nunca puede bloquear tráfico por sí solo, sin importar lo que diga <code>drop.conf</code>. <code>suridata.sh</code> (cron, cada 5 minutos) es lo que convierte un match de <code>drop.conf</code> en un bloqueo real: lee los SIDs que <code>suricata-update</code> ya resolvió a acción <code>drop</code> en <code>suricata.rules</code> (cubre tanto SIDs literales como entradas <code>re:</code> de regex de mensaje en <code>drop.conf</code>), lee solo las líneas nuevas de <code>eve.json</code> desde su última corrida, y por cada alerta cuyo <code>signature_id</code> coincide, agrega el <code>dest_ip</code> del flujo a <code>suridata.txt</code>. <code>iptables.sh</code> carga ese archivo al ipset <code>suridata</code> y bloquea los destinos que coincidan en <code>mangle PREROUTING</code> — de forma silenciosa, sin página de aviso (a diferencia de <code>bandata</code>, esto bloquea un destino, no un cliente). Sin expiración: las entradas se retiran a mano, mismo modelo que <code>blockports.txt</code>. Los miembros de <code>macunlimited</code> (APs, switches) quedan exentos, igual que con <code>blockports</code>.
     <br><br>
     <strong>Al editar <code>drop.conf</code> / <code>disable.conf</code>:</strong> <code>suricataupdate.sh</code> es el único script que lee estos archivos y los aplica a <code>suricata.rules</code>; corre una sola vez al día por cron (2 AM). Una SID recién agregada a <code>drop.conf</code> queda como <code>alert</code> plano (sin bloquear) hasta que corra ese cron. Para aplicar el cambio de inmediato, corre ambos en orden: <code>sudo /etc/suricata/suricataupdate.sh && sudo /etc/suricata/suridata.sh</code> — en esa primera corrida de <code>suridata.sh</code> después de que la SID pasa a <code>drop</code>, también hace un escaneo completo único de <code>eve.json</code> para esa SID (rastreado vía <code>suridata.sids</code>), así que las alertas que ya habían ocurrido ese mismo día también quedan agregadas a <code>suridata.txt</code>, no solo las de ahí en adelante.
    </td>
  </tr>
</table>

### Security Rules

- SYN flood protection via rate-limited `syn_flood` chain
- TCP scan / malformed packet drops (SYN+FIN, SYN+RST, NEW with SYN+ACK)
- Bittorrent/Tor and other protocol-level detection is handled by Suricata (see Optional Packages below), not by hex-string matching in `iptables.sh`
- GRE (protocol 47) and 6to4 (protocol 41) blocked from LAN
- Windows ICS network range (192.168.137.0/24) blocked
- NetBIOS NMBD (137–139), CoAP (5683–5684), mDNS noise, WUDO WAN traffic blocked
- Bogon/reserved-range filtering (RFC1918, link-local, test-nets, etc.) is available in `iptables.sh` but **disabled by default** — enabling it blindly can lock the LAN out of its own network if the server's subnet falls inside a blocked RFC1918 range; see the comment above the `BOGONS` block before enabling it

### Allowed LAN Services (`macports`)

Devices registered in `macports` have access to the following / Los dispositivos registrados en `macports` tienen acceso a los siguientes servicios:

- **Printing** — JetDirect/RAW (9100), SNMP (161, 162), prnrequest/prnstatus (3910, 3911)
- **Email** — SMTP (465, 587), IMAP (993), POP3 (995), STARTTLS (143, 110)
- **Messaging / XMPP** — ports 5222, 5223, 5228, 5269
- **WebRTC / STUN-TURN** — UDP 3478–3481, 19302–19309; TCP 3478, 5349
- **Samba / SMB** — TCP 445, 3092
- **LAN discovery** — mDNS (5353), LLMNR (5355), SSDP/UPnP (1900), WSD (3702), IGMP
- **KMS** — Windows activation (1688)

DNS (UDP/TCP 53) is a global rule applied to all LAN traffic, not a `macports`-specific privilege — see `SERV_DNS` above / DNS (UDP/TCP 53) es una regla global aplicada a todo el tráfico LAN, no un privilegio específico de `macports` — ver `SERV_DNS` arriba.

## OPTIONAL PACKAGES

---

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

### Optional Pack: Net Tools + Security

- **Network diagnostics** — `fping`, `ethtool`, `iperf3`, `masscan`, `nbtscan`, `nast`, `arp-scan`, `arping`, `netdiscover`, `nmap`, `traceroute`, `mtr`, `wireless-tools`
- **fail2ban** — brute-force protection with custom jail config
- **lynis** — security auditing (`lynis -c -Q`; log at `/var/log/lynis.log`)
- **fsearch** — fast file search (GUI)
- **ttyd** — web terminal, loopback-only (`http://localhost:7681`)
- **Suricata IDS** — network intrusion detection in AF-PACKET mode with auto-update rules; community-id enabled
- **suridata** — turns `drop.conf` matches into real blocks via the `suridata` ipset (see [FIREWALL](#firewall)); cron every 5 minutes
- **EveBox** — Suricata event browser (`http://localhost:5636`)

### Optional Pack: Samba

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Installs <b>smbstack</b> — a Samba server with a shared folder, Recycle Bin, and audit logging configured out of the box. <code>smbstack</code> manages its own veto list for common unwanted file types (<code>/etc/samba/acl/commonveto.txt</code>, active by default) — not gateproxy's responsibility.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Instala <b>smbstack</b> — un servidor Samba con carpeta compartida, Papelera de Reciclaje y registro de auditoría configurados de fábrica. <code>smbstack</code> gestiona su propia lista veto de tipos de archivo comunes no deseados (<code>/etc/samba/acl/commonveto.txt</code>, activa por defecto) — no es responsabilidad de gateproxy.
    </td>
  </tr>
</table>

### Optional Pack: UHM

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     This prompt only appears if a local UniFi Network controller is detected first — classic (<code>dpkg</code> package <code>unifi</code>) or unifi-os (<code>/var/lib/uosserver/server.conf</code>, podman-based). If neither is found, the prompt is skipped entirely — gateproxy does not install UniFi or podman itself. To install UniFi Network self-hosted / UniFi OS Server first, use <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/unifisetup.sh"><code>unifisetup.sh</code></a>, then re-run gateproxy (or run <code>uhmsetup.sh</code> from the <a href="https://github.com/maravento/uhm">uhm</a> repo directly). Installs <b>uhm</b> (UniFi Hotspot Manager), which requires pydhcp already installed and running — a requirement gateproxy's own base setup already satisfies. <code>uhm</code> runs its own interactive installer (<code>uhmsetup.sh</code>): it reads pydhcp's network values from <code>pydhcp.env</code> automatically, then prompts for its own UniFi-specific settings (controller credentials, SSID, etc.) directly.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Este prompt sólo aparece si primero se detecta un controlador UniFi Network local — classic (paquete <code>dpkg</code> <code>unifi</code>) o unifi-os (<code>/var/lib/uosserver/server.conf</code>, basado en podman). Si no se detecta ninguno, el prompt se omite por completo — gateproxy no instala UniFi ni podman por sí mismo. Para instalar primero UniFi Network self-hosted / UniFi OS Server, use <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/scripts/bash/unifisetup.sh"><code>unifisetup.sh</code></a>, y luego vuelva a ejecutar gateproxy (o ejecute <code>uhmsetup.sh</code> directamente desde el repo de <a href="https://github.com/maravento/uhm">uhm</a>). Instala <b>uhm</b> (UniFi Hotspot Manager), que requiere tener pydhcp ya instalado y corriendo — requisito que la configuración base de gateproxy ya satisface. <code>uhm</code> ejecuta su propio instalador interactivo (<code>uhmsetup.sh</code>): lee automáticamente los valores de red de pydhcp desde <code>pydhcp.env</code>, y luego pregunta directamente por sus propios parámetros específicos de UniFi (credenciales del controlador, SSID, etc.).
    </td>
  </tr>
</table>

## POST-INSTALL

---

### Scripts (`/etc/scr/`)

The following scripts from `conf/scr/` are copied to `/etc/scr/` during installation / Los siguientes scripts de `conf/scr/` se copian a `/etc/scr/` durante la instalación:

| Script | Trigger | Purpose |
| :--- | :--- | :--- |
| `iptables.sh` | manual | Load firewall rules and ipsets |
| `serverboot.sh` | manual (`alias server`) | Start/restart all server services |
| `serviceswatch.sh` | every 5 min | Restart failed services |
| `killswitch.sh` | manual | Block all traffic in emergency |
| `bkconf.sh` | manual | Backup configuration files |

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Some deployed tools — <code>iptables.sh</code> here, and pydhcp's own <code>pyleases.sh</code> — are never added to cron automatically by any installer. Scheduling them (or not) is entirely up to the operator, based on their own needs.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Algunas herramientas desplegadas — <code>iptables.sh</code> aquí, y <code>pyleases.sh</code> de pydhcp — nunca se agregan al cron automáticamente por ningún instalador. Programarlas (o no) queda enteramente a criterio del operador, según sus necesidades.
    </td>
  </tr>
</table>

The installer also downloads the following scripts from external repositories / El instalador también descarga los siguientes scripts de repositorios externos:

| Script | Trigger | Purpose |
| :--- | :--- | :--- |
| `hwclock.sh` | `@reboot` | Sync hardware clock |
| `blackusb.sh` | `@reboot` | USB device access control |
| `cleaner.sh` | `@weekly` | System cleanup |
| `ffsupdate.sh` | `@weekly` | Update FreeFileSync |
| `filereport.sh` | manual | Generate file system report |

### Shell Aliases

Added to `~/.bashrc` for the local user / Agregados al `~/.bashrc` del usuario local:

```bash
alias upgrade   # full system upgrade (nala + aptitude + snap)
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

# Check Squid cache
squidclient mgr:info

# Check WPAD/PAC
curl http://SERVER_IP:18100/wpad.pac
```

## IMPORTANT

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy is a script designed for very specific network environments (see Requirements above for the supported OS/version). It is not intended for general or production use. Using it outside the environment for which it was designed may cause unexpected behavior or system misconfiguration. Use at your own risk.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy es un script diseñado para entornos de red muy específicos (ver Requirements arriba para el SO/versión soportada). No está destinado para uso general ni en producción. Usarlo fuera del entorno para el que fue diseñado puede causar comportamientos inesperados o una mala configuración del sistema. Úselo bajo su propio riesgo.
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
