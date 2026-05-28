# [SMBstack](https://github.com/maravento)

[![status-release-candidate](https://img.shields.io/badge/status-release_candidate-skyblue.svg)](https://github.com/maravento)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>SMBstack</b> is an open-source Samba stack installer for Debian/Ubuntu. It deploys a shared folder with Recycle Bin, full audit logging via rsyslog, a web-based audit viewer, and a shared folder browser — all configured interactively through a single installer script.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>SMBstack</b> es un instalador de stack Samba de código abierto para Debian/Ubuntu. Despliega una carpeta compartida con Papelera de Reciclaje, auditoría completa vía rsyslog, un visor web de auditoría y un explorador web de la carpeta compartida — todo configurado de forma interactiva a través de un único script instalador.
    </td>
  </tr>
</table>

## Web Interface

---

### Main Menu

[![smbmain](https://raw.githubusercontent.com/maravento/vault/master/smbstack/img/smbmain.png)](https://github.com/maravento/vault)

### SMBaudit

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The audit viewer (<code>http://localhost:3092/audit</code>) displays Samba activity logs in real time. It allows filtering by user, IP, action and status, pagination, and export to PDF.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El visor de auditoría (<code>http://localhost:3092/audit</code>) muestra los logs de actividad de Samba en tiempo real. Permite filtrar por usuario, IP, acción y estado, paginación y exportación a PDF.
    </td>
  </tr>
</table>

[![smbaudit](https://raw.githubusercontent.com/maravento/vault/master/smbstack/img/smbaudit.png)](https://github.com/maravento/vault)

### SMBshared

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The shared folder browser (<code>http://localhost:3092/</code>) provides a unified interface with two tabs: <strong>Shared</strong> and <strong>Audit</strong>. The Shared tab allows navigating the shared folder structure, opening or downloading documents, and moving items to the recycle bin. Root-level folders are protected — items cannot be uploaded, created, or deleted from the root level.
    </td>
    <td style="width: 50%; vertical-align: top;">
      El explorador de carpeta compartida (<code>http://localhost:3092/</code>) ofrece una interfaz unificada con dos pestañas: <strong>Shared</strong> y <strong>Audit</strong>. La pestaña Shared permite navegar la estructura de carpetas, abrir o descargar documentos y mover elementos a la papelera de reciclaje. Las carpetas de primer nivel están protegidas — no se pueden subir archivos, crear carpetas ni eliminar elementos desde la raíz.
    </td>
  </tr>
</table>

[![smbshared](https://raw.githubusercontent.com/maravento/vault/master/smbstack/img/smbshared.png)](https://github.com/maravento/vault)

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Inside any subfolder, the toolbar allows uploading single or multiple files simultaneously, creating new folders, and reloading the view. All operations are recorded in the audit log with the client's real IP address, including Cloudflare tunnel connections.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Dentro de cualquier subcarpeta, la barra de herramientas permite subir uno o varios archivos simultáneamente, crear nuevas carpetas y recargar la vista. Todas las operaciones quedan registradas en el log de auditoría con la IP real del cliente, incluyendo conexiones por túnel Cloudflare.
    </td>
  </tr>
</table>

[![smbfiles](https://raw.githubusercontent.com/maravento/vault/master/smbstack/img/smbfiles.png)](https://github.com/maravento/vault)

## Scope

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>What SMBstack does:</b>
      <ul>
        <li>Installs and configures Samba with a shared folder, Recycle Bin and group permissions</li>
        <li>Configures full audit logging via rsyslog to <code>/var/log/samba/log.audit</code></li>
        <li>Deploys a web-based audit log viewer at <code>http://localhost:3092/audit</code></li>
        <li>Deploys a web-based shared folder browser at <code>http://localhost:3092/shared</code></li>
        <li>Configures logrotate for all Samba logs</li>
        <li>Installs a service watchdog (<code>smbload.sh</code>) via cron <code>@reboot</code></li>
        <li>Installs a shared folder size monitor (<code>smbwatch.sh</code>) — self-managed, independent of the installer</li>
        <li>Saves installation config to <code>/var/www/smbstack/smbstack.env</code> for future updates</li>
        <li>Optional NetBIOS support (disabled by default)</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Lo que SMBstack hace:</b>
      <ul>
        <li>Instala y configura Samba con carpeta compartida, Papelera de Reciclaje y permisos de grupo</li>
        <li>Configura auditoría completa vía rsyslog en <code>/var/log/samba/log.audit</code></li>
        <li>Despliega un visor web de auditoría en <code>http://localhost:3092/audit</code></li>
        <li>Despliega un explorador web de la carpeta compartida en <code>http://localhost:3092/shared</code></li>
        <li>Configura logrotate para todos los logs de Samba</li>
        <li>Instala un watchdog de servicios (<code>smbload.sh</code>) vía cron <code>@reboot</code></li>
        <li>Instala un monitor de espacio de la carpeta compartida (<code>smbwatch.sh</code>) — autogestionado, independiente del instalador</li>
        <li>Guarda la configuración de instalación en <code>/var/www/smbstack/smbstack.env</code> para futuras actualizaciones</li>
        <li>Soporte opcional de NetBIOS (deshabilitado por defecto)</li>
      </ul>
    </td>
  </tr>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>Out of scope (not implemented):</b>
      <ul>
        <li>Active Directory / domain controller</li>
        <li>Multiple shared folders</li>
        <li>Custom paths outside <code>/home/$user/</code> (must be edited manually)</li>
        <li>IPv6</li>
        <li>LDAP</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Fuera de alcance (no implementado):</b>
      <ul>
        <li>Active Directory / controlador de dominio</li>
        <li>Múltiples carpetas compartidas</li>
        <li>Rutas personalizadas fuera de <code>/home/$user/</code> (debe editarse manualmente)</li>
        <li>IPv6</li>
        <li>LDAP</li>
      </ul>
    </td>
  </tr>
</table>

## Repository Structure

---

```
smbstack/
├── smbinstall.sh               # Installer: install, update, uninstall, status
├── README.md
├── conf/                       # Configuration files deployed to system paths
│   ├── smb.conf                # Samba main config (placeholders: your_user, compartida)
│   └── fullaudit.conf          # rsyslog full audit rule
├── img/
│   ├── smbshared.png
│   └── smbaudit.png
├── web/                        # Web files deployed to /var/www/smbstack/web/
│   ├── smbweb.conf             # Apache vhost (:3092/audit and :3092/shared)
│   ├── smbaudit.html           # Audit log viewer UI
│   ├── smbapi.php              # Audit log reader API
│   ├── smbaudit-diagnostic.php # Audit log diagnostic tool
│   └── shared.php              # Shared folder dynamic browser
└── tools/                      # Scripts deployed to /var/www/smbstack/tools/
    ├── smbload.sh              # Service watchdog (smbd + winbind)
    └── smbwatch.sh             # Shared folder size monitor (self-managed)
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Files and directories generated at runtime (not included in the repository):
    </td>
    <td style="width: 50%; vertical-align: top;">
      Archivos y directorios generados en runtime (no incluidos en el repositorio):
    </td>
  </tr>
</table>

```
/var/www/smbstack/
│   └── tools/
│       └── watchdir.log        # smbwatch.sh runtime log
└── smbstack.env                # Saved install config (user, paths, network, watch limit)

/home/$USER/shared/             # Shared folder (independent of the installer)
├── recycle/                    # Recycle Bin
└── DEMO/                       # Demo folder

/etc/logrotate.d/samba          # Generated by installer (heredoc)
/var/log/samba/log.audit        # Created by rsyslog
/var/log/samba/log.samba        # Created by rsyslog
```

## Requirements

---

- Ubuntu 24.04 x64
- Apache2 with `mod_headers`, `mod_mime`, `mod_rewrite` and PHP
- rsyslog
- logrotate
- inotify-tools (required by `smbwatch.sh`)

```bash
apt-get install -y apache2 apache2-utils libapache2-mod-php
apt-get install -y --reinstall apache2-doc
```

> **Important**
> - nginx must not be running.
> - SMBstack uses Apache2 exclusively on port 3092, because it is listed as **Unassigned** by IANA. For more information visit [https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt)

## HOW TO USE

---

### Install

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Download the repository and run the installer:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Descarga el repositorio y ejecuta el instalador:
    </td>
  </tr>
</table>

```bash
# Download
sudo apt install -y python-is-python3
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python gitfolder.py https://github.com/maravento/vault/smbstack

# Install
cd smbstack
sudo bash smbinstall.sh
```

The installer will prompt for:

| Prompt | Description |
|--------|-------------|
| Shared folder name | Name for the shared folder (created under `/home/$USER/`) |
| Samba server network | IP/network in CIDR format (e.g. `192.168.1.0/24`) |
| Network interface | Selected from available interfaces listed |
| Samba username | Samba account to create |
| NetBIOS support | Optional, disabled by default |
| Overwrite smb.conf | Only asked if `/etc/samba/smb.conf` already exists |

### Update & Uninstall

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To update or uninstall SMBstack, download the updated repository, enter the folder and run:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para actualizar o desinstalar SMBstack, descarga el repositorio actualizado, entra a la carpeta y ejecuta:
    </td>
  </tr>
</table>

```bash
cd smbstack
sudo bash smbinstall.sh --update
# or | o
sudo bash smbinstall.sh --uninstall
```

| File | `--update` | `--uninstall` |
|------|-----------|---------------|
| `conf/smb.conf` | ✅ overwritten | ✅ restored from `.bak` |
| `conf/fullaudit.conf` | ✅ overwritten | ✅ removed |
| `web/smbweb.conf` | ✅ overwritten | ✅ removed |
| `web/smbaudit.html` | ✅ overwritten | ✅ removed |
| `web/smbapi.php` | ✅ overwritten | ✅ removed |
| `web/smbaudit-diagnostic.php` | ✅ overwritten | ✅ removed |
| `web/shared.php` | ✅ overwritten | ✅ removed |
| `tools/smbload.sh` | ✅ overwritten | ✅ removed |
| `tools/smbwatch.sh` | ✅ overwritten | ✅ removed |
| `/var/www/smbstack/smbstack.env` | ⛔ preserved | ✅ removed |
| Shared folder (`/home/$USER/shared/`) | ⛔ never touched | ⛔ never touched |

> The shared folder is independent of the installer. To remove it, do so manually: `rm -rf /home/$USER/shared`

### Status

```bash
sudo bash smbinstall.sh --status
```

Shows: smbd and winbind service status, Apache port 3092, last 5 audit log entries, and `testparm` summary.

### Config

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      After installation, the main configuration files are:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Tras la instalación, los archivos de configuración principales son:
    </td>
  </tr>
</table>

| Description | File |
|-------------|------|
| Samba main config | `/etc/samba/smb.conf` |
| Audit rsyslog rule | `/etc/rsyslog.d/fullaudit.conf` |
| Web vhost (audit + shared) | `/etc/apache2/sites-available/smbweb.conf` |
| Log rotation | `/etc/logrotate.d/samba` |
| Install config | `/var/www/smbstack/smbstack.env` |

```bash
# Verify Samba config | Verificar configuración de Samba
testparm

# Restart services | Reiniciar servicios
sudo systemctl restart smbd winbind

# View audit log | Ver log de auditoría
tail -f /var/log/samba/log.audit

# List Samba users | Listar usuarios de Samba
sudo pdbedit -L
```

> To use a custom shared folder path outside `/home/$USER/`, edit `/etc/samba/smb.conf` and `/etc/apache2/sites-available/smbweb.conf` manually after installation.

### smbload

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>smbload.sh</code> is a service watchdog that ensures <code>smbd</code> and <code>winbind</code> are running at boot. It is automatically registered in cron <code>@reboot</code> during installation and runs from <code>/var/www/smbstack/tools/</code>.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>smbload.sh</code> es un watchdog de servicios que garantiza que <code>smbd</code> y <code>winbind</code> estén en ejecución al arrancar. Se registra automáticamente en cron <code>@reboot</code> durante la instalación y corre desde <code>/var/www/smbstack/tools/</code>.
    </td>
  </tr>
</table>

```bash
# sudo crontab -l
@reboot /var/www/smbstack/tools/smbload.sh
```

### smbwatch

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>smbwatch.sh</code> monitors first-level subdirectories of the shared folder in real time using <code>inotifywait</code>. When a subdirectory exceeds the configured size limit, the triggering file is automatically moved to the recycle bin. It is self-managed and independent of the installer — it reads its configuration from <code>smbstack.env</code> and prompts for any missing values.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>smbwatch.sh</code> monitorea en tiempo real las subcarpetas de primer nivel de la carpeta compartida usando <code>inotifywait</code>. Cuando una subcarpeta supera el límite de tamaño configurado, el archivo que disparó el evento se mueve automáticamente a la papelera de reciclaje. Es autogestionado e independiente del instalador — lee su configuración desde <code>smbstack.env</code> y solicita los valores faltantes.
    </td>
  </tr>
</table>

```bash
# Start
sudo /var/www/smbstack/tools/smbwatch.sh start

# Stop
sudo /var/www/smbstack/tools/smbwatch.sh stop

# Status
sudo /var/www/smbstack/tools/smbwatch.sh status
```

> `inotify-tools` is required: `apt-get install -y inotify-tools`

### NetBIOS

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      NetBIOS is disabled by default (<code>disable netbios = yes</code> in <code>smb.conf</code>). If enabled during installation, <code>nmbd</code> is activated and its logrotate block is appended to <code>/etc/logrotate.d/samba</code>. To enable it manually after installation:
    </td>
    <td style="width: 50%; vertical-align: top;">
      NetBIOS está deshabilitado por defecto (<code>disable netbios = yes</code> en <code>smb.conf</code>). Si se habilita durante la instalación, se activa <code>nmbd</code> y su bloque de logrotate se agrega a <code>/etc/logrotate.d/samba</code>. Para habilitarlo manualmente tras la instalación:
    </td>
  </tr>
</table>

```bash
sudo sed -i 's/disable netbios = yes/disable netbios = no/' /etc/samba/smb.conf
sudo systemctl enable --now nmbd.service
sudo systemctl restart smbd
```

## ⚠️ WARNING: Network Access

---

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This project is designed to run locally and be accessed over a LAN. It is not recommended to expose it to the internet, as it lacks the hardening required for public-facing deployments.
      If you choose to publish it despite this warning, it is strongly recommended to do so through an on-demand tunnel rather than opening ports directly. This approach lets you start and stop public access at will, without permanently exposing your server.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Este proyecto está diseñado para ejecutarse localmente y ser accedido en red LAN. No se recomienda exponerlo a internet, ya que no cuenta con el endurecimiento necesario para despliegues públicos.
      Si decide publicarlo a pesar de esta advertencia, se recomienda hacerlo a través de un túnel bajo demanda en lugar de abrir puertos directamente. Este enfoque le permite iniciar y detener el acceso público a voluntad, sin exponer el servidor de forma permanente.
    </td>
  </tr>
</table>

**Optional tunnel:**
- [Cloudflare Tunnel (start|stop|status) - Zero Trust Activation Recommended](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
