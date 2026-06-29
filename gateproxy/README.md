# [Gateproxy](https://github.com/maravento)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> is a simple proxy/firewall server for managing Pyme's LAN networks. The installation and configuration script is fully automated and customizable according to the needs of the administrator or organization, with minimal interaction during the process. It can be implemented in physical servers or VMs, for greater flexibility and portability.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> es un sencillo servidor proxy/firewall para administrar redes Pyme's LAN. El script de instalación y configuración es totalmente automatizado y personalizable, de acuerdo a las necesidades del administrador u organización, con una interacción mínima durante proceso. Puede ser implementado en servidores físicos o VMs, para mayor flexibilidad y portabilidad.
    </td>
  </tr>
</table>

## DATA SHEET

---

| OS | CPU | NIC | RAM | Storage |
| :---: | :---: | :---: | :---: | :---: |
| Ubuntu 24.04.x | 4+ cores (≥ 3.0 GHz) | 2 (WAN & LAN) | 16-32 GB (4 GB cache_mem) | 100 GB SSD (cache_dir rock) |

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Run the following command on a fresh Ubuntu 24.04.x installation. The script must be executed as root or with <code>sudo</code>. It will self-delete after completion and reboot the system automatically.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Ejecute el siguiente comando en una instalación limpia de Ubuntu 24.04.x. El script debe ejecutarse como root o con <code>sudo</code>. Se eliminará automáticamente al finalizar y reiniciará el sistema.
    </td>
  </tr>
</table>

```bash
wget -qO gateproxy.sh https://raw.githubusercontent.com/maravento/vault/master/gateproxy/gateproxy.sh && sudo bash gateproxy.sh
```

![Gateproxy](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/img/gateproxy.png)

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
| WAN Interface | `eth0` | Public/internet-facing NIC / NIC pública (Internet) |
| LAN Interface | `eth1` | Local network NIC / NIC de red local |
| Server IP | `192.168.0.10` | Gateway IP assigned to this server / IP del servidor en la LAN |
| Netmask | `255.255.255.0` | Subnet mask / Máscara de subred |
| Subnet (CIDR) | `/24` | CIDR prefix length / Prefijo CIDR |
| Localnet | `192.168.0.0` | LAN network address / Dirección de red LAN |
| Broadcast | `192.168.0.255` | LAN broadcast address / Dirección de broadcast LAN |
| DNS Primary | `8.8.8.8` | Primary DNS server / DNS primario |
| DNS Secondary | `8.8.4.4` | Secondary DNS server / DNS secundario |
| Proxy Port | `3128` | Squid proxy port / Puerto del proxy Squid |

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
| **Squid** (squid-openssl) | `3128` | Transparent + explicit proxy with rock/ufs cache |
| **WPAD/PAC** (Apache2) | `18100` | Proxy auto-config served via `wpad.pac` |
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

Pool range and other DHCP settings can be changed in `/etc/pydhcp/pydhcpd.env` after installation / El rango del pool y otros parámetros DHCP pueden modificarse en `/etc/pydhcp/pydhcpd.env` luego de la instalación.

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
├── acl/                        # Default ACL files (deployed to /etc/acl/)
│   ├── acl_dhcp/
│   │   └── blockdhcp.txt
│   ├── acl_ipt/
│   │   ├── blockports.txt
│   │   ├── bogons.txt
│   │   ├── dhcp_ip.txt
│   │   └── dhcp_mac.txt
│   ├── acl_mac/
│   │   ├── mac-proxy.txt
│   │   └── mac-unlimited.txt
│   └── acl_squid/
│       ├── aipextra.txt
│       ├── allowdomains.txt
│       ├── blockdomains.txt
│       ├── blockext.txt
│       └── blockmime.txt
├── conf/
│   ├── pack/                   # Optional package configs
│   │   ├── disable.conf            # Suricata disabled rules
│   │   ├── drop.conf               # Suricata drop rules
│   │   ├── evebox.service          # EveBox systemd unit
│   │   ├── evebox.yaml             # EveBox configuration
│   │   ├── jail.local              # fail2ban jail config
│   │   ├── suricata-clean.sh       # Suricata log cleanup
│   │   └── suricata-update.sh      # Suricata rules update
│   ├── scr/                    # Scripts (deployed to /etc/scr/)
│   │   ├── bkconf.sh               # Backup configuration files
│   │   ├── iptables.sh             # Firewall rules and ipsets
│   │   ├── killswitch.sh           # Emergency traffic block
│   │   ├── serverboot.sh           # Start/restart all services
│   │   └── serviceswatch.sh        # Service watchdog
│   ├── server/                 # Server configuration files
│   │   ├── 000-add.txt             # Apache VirtualHost additions
│   │   ├── 000-default.conf        # Apache default site
│   │   ├── 00-networkd.yaml        # Netplan configuration
│   │   ├── dir.conf                # Apache directory index config
│   │   ├── hosts.txt               # /etc/hosts additions
│   │   ├── security.conf           # Apache security hardening
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
│   └── blockdhcp.txt           # MACs blocked from receiving a DHCP lease
├── acl_squid/              # Squid proxy ACLs
│   ├── aipextra.txt            # Additional allowed IPs (bypass blacklist)
│   ├── allowdomains.txt        # Allowed domains (whitelist)
│   ├── blockdomains.txt        # Blocked domains (blacklist)
│   ├── blockext.txt            # Blocked file extensions
│   └── blockmime.txt           # Blocked MIME types
└── acl_ipt/                # iptables ACLs
    ├── blockports.txt          # Blocked port ranges (VPN, P2P, cryptomining…)
    ├── bogons.txt              # Bogon/unroutable IP ranges
    ├── dhcp_ip.txt             # IP list derived from DHCP leases (auto-generated)
    └── dhcp_mac.txt            # MAC list derived from DHCP leases (auto-generated)
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     MAC list files use semicolon-separated format: <code>description;MAC_ADDRESS</code>. Lines with an empty MAC field are ignored by the firewall.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Los archivos de listas MAC usan formato separado por punto y coma: <code>descripcion;DIRECCION_MAC</code>. Las líneas con el campo MAC vacío son ignoradas por el firewall.
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
| `macunlimited` | `hash:mac` | Full bypass — APs, managed switches, and similar infrastructure devices |
| `macproxy` | `hash:mac` | HTTP transparent redirect to Squid (port 3128); PAC served on port 18100 |
| `macports` | `hash:mac` | Registered devices with controlled port access (DNS, printing, email, STUN, etc.) |
| `macip` | `hash:ip,mac` | MAC+IP binding — drops spoofed source addresses |
| `blockports` | `bitmap:port` | Blocked port ranges (VPN tunnels, P2P, cryptomining, legacy protocols) |
| `bandata` | `hash:ip` | IPs over bandwidth quota — DNS and port 80 only, redirected to warning page |

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
- **Alternate proxies** — ports 8080, 8000, 3129, 3130
- **Legacy / risky** — FTP (20–21), Telnet (23), Finger (79), IRC (6660–6669), CHARGEN (19), Echo (7), WINS (42), IPP (631), BTC/ETH (8332, 8333, 8545, 30303)

### Security Rules

- SYN flood protection via rate-limited `syn_flood` chain
- TCP scan / malformed packet drops (SYN+FIN, SYN+RST, NEW with SYN+ACK)
- Bittorrent and Tor protocol detection via hex string matching (`NFLOG` + `DROP`)
- GRE (protocol 47) and 6to4 (protocol 41) blocked from LAN
- Windows ICS network range (192.168.137.0/24) blocked
- NetBIOS NMBD (137–139), CoAP (5683–5684), mDNS noise, WUDO WAN traffic blocked
- Private RFC-1918 ranges dropped on WAN input

### Allowed LAN Services (`macports`)

Devices registered in `macports` have access to the following / Los dispositivos registrados en `macports` tienen acceso a los siguientes servicios:

- **DNS** — UDP/TCP 53 (to configured DNS servers only)
- **Printing** — JetDirect/RAW (9100), SNMP (161, 162), prnrequest/prnstatus (3910, 3911)
- **Email** — SMTP (465, 587), IMAP (993), POP3 (995), STARTTLS (143, 110)
- **Messaging / XMPP** — ports 5222, 5223, 5228, 5269
- **WebRTC / STUN-TURN** — UDP 3478–3481, 19302–19309; TCP 3478, 5349
- **Samba / SMB** — TCP 445, 3092
- **LAN discovery** — mDNS (5353), LLMNR (5355), SSDP/UPnP (1900), WSD (3702), IGMP
- **Remote support** — RustDesk (21114–21119), AnyDesk (6568, 7070)
- **KMS** — Windows activation (1688)
- **Localsend** — TCP 53317

## OPTIONAL PACKAGES

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     The installer offers two optional installation prompts at the end of the base setup.
    </td>
    <td style="width: 50%; vertical-align: top;">
     El instalador ofrece dos prompts de instalación opcionales al final de la configuración base.
    </td>
  </tr>
</table>

### Optional Pack: Net Tools + Security

- **Network diagnostics** — `fping`, `ethtool`, `iperf3`, `masscan`, `nbtscan`, `nast`, `arp-scan`, `arping`, `netdiscover`, `nmap`, `traceroute`, `mtr`, `wireless-tools`
- **fail2ban** — brute-force protection with custom jail config
- **lynis** — security auditing (`lynis -c -Q`; log at `/var/log/lynis.log`)
- **fsearch** — fast file search (GUI)
- **Suricata IDS** — network intrusion detection in AF-PACKET mode with auto-update rules; community-id enabled
- **EveBox** — Suricata event browser (`http://localhost:5636`)

### Optional Pack: Samba

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Installs <b>smbstack</b> — a Samba server with a shared folder, Recycle Bin, and audit logging configured out of the box.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Instala <b>smbstack</b> — un servidor Samba con carpeta compartida, Papelera de Reciclaje y registro de auditoría configurados de fábrica.
    </td>
  </tr>
</table>

## POST-INSTALL

---

### Scripts (`/etc/scr/`)

The following scripts from `conf/scr/` are copied to `/etc/scr/` during installation / Los siguientes scripts de `conf/scr/` se copian a `/etc/scr/` durante la instalación:

| Script | Trigger | Purpose |
| :--- | :--- | :--- |
| `iptables.sh` | `@reboot` / manual | Load firewall rules and ipsets |
| `serverboot.sh` | manual (`alias server`) | Start/restart all server services |
| `serviceswatch.sh` | every 5 min | Restart failed services |
| `killswitch.sh` | manual | Block all traffic in emergency |
| `bkconf.sh` | manual | Backup configuration files |

The installer also downloads the following scripts from external repositories / El instalador también descarga los siguientes scripts de repositorios externos:

| Script | Trigger | Purpose |
| :--- | :--- | :--- |
| `hwclock.sh` | `@reboot` | Sync hardware clock |
| `lock.sh` | `@reboot` | Screen lock policy |
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
     Gateproxy is a script designed for very specific network environments and is only compatible with Ubuntu 24.04.x LTS. It is not intended for general or production use. Using it outside the environment for which it was designed may cause unexpected behavior or system misconfiguration. Use at your own risk.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy es un script diseñado para entornos de red muy específicos y solo es compatible con Ubuntu 24.04.x LTS. No está destinado para uso general ni en producción. Usarlo fuera del entorno para el que fue diseñado puede causar comportamientos inesperados o una mala configuración del sistema. Úselo bajo su propio riesgo.
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
