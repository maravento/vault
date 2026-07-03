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
      Inside any subfolder, the toolbar allows uploading single or multiple files simultaneously, creating new folders, and reloading the view. All operations are recorded in the audit log with the client's IP address.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Dentro de cualquier subcarpeta, la barra de herramientas permite subir uno o varios archivos simultáneamente, crear nuevas carpetas y recargar la vista. Todas las operaciones quedan registradas en el log de auditoría con la IP del cliente.
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
        <li>Custom paths outside <code>/home/$local_user/</code> (must be edited manually)</li>
        <li>IPv6</li>
        <li>LDAP</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>Fuera de alcance (no implementado):</b>
      <ul>
        <li>Active Directory / controlador de dominio</li>
        <li>Múltiples carpetas compartidas</li>
        <li>Rutas personalizadas fuera de <code>/home/$local_user/</code> (debe editarse manualmente)</li>
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
└── smbstack.env                # Saved install config (user, paths, network, trusted proxies, watch limit)

/home/$local_user/shared/       # Shared folder (independent of the installer)
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

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>Important</strong>
      <ul>
        <li>nginx must not be running.</li>
        <li>SMBstack uses Apache2 exclusively on port 3092, because it is listed as <strong>Unassigned</strong> by IANA. For more information visit <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt</a></li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Importante</strong>
      <ul>
        <li>nginx no debe estar en ejecución.</li>
        <li>SMBstack usa Apache2 exclusivamente en el puerto 3092, ya que está listado como <strong>Sin asignar</strong> por IANA. Para más información visita <a href="https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt">https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.txt</a></li>
      </ul>
    </td>
  </tr>
</table>

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
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python3 gitfolder.py https://github.com/maravento/vault/smbstack

# Install
cd smbstack
sudo bash smbinstall.sh
```

The installer will prompt for:

| Prompt | Description |
|--------|-------------|
| Shared folder name | Name for the shared folder (created under `/home/$local_user/`) |
| Samba server network | IP/network in CIDR format (e.g. `192.168.1.0/24`) |
| Network interface | Selected from available interfaces listed |
| Samba username | Samba account to create |
| NetBIOS support | Optional, disabled by default |
| Overwrite smb.conf | Only asked if `/etc/samba/smb.conf` already exists |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>$local_user</code> is the local Linux user detected automatically by the installer: the user logged into the console session, or <code>SUDO_USER</code>, or the first user found under <code>/home/</code>. It becomes the owner of the shared folder and the base name for the Samba account.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>$local_user</code> es el usuario local de Linux detectado automáticamente por el instalador: el usuario con sesión en consola, o <code>SUDO_USER</code>, o el primer usuario encontrado en <code>/home/</code>. Se convierte en el propietario de la carpeta compartida y el nombre base de la cuenta Samba.
    </td>
  </tr>
</table>

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
| `conf/smb.conf` | ⛔ not touched (user-customized) | ✅ restored from `.bak` |
| `conf/fullaudit.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/smbweb.conf` | ⛔ not touched (user-customized) | ✅ removed |
| `web/smbaudit.html` | ✅ overwritten | ✅ removed |
| `web/smbapi.php` | ✅ overwritten | ✅ removed |
| `web/smbaudit-diagnostic.php` | ✅ overwritten | ✅ removed |
| `web/shared.php` | ✅ overwritten | ✅ removed |
| `tools/smbload.sh` | ✅ overwritten | ✅ removed |
| `tools/smbwatch.sh` | ✅ overwritten | ✅ removed |
| `/var/www/smbstack/smbstack.env` | ⛔ preserved | ✅ removed |
| Shared folder (`/home/$local_user/shared/`) | ⛔ never touched | ⛔ never touched |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>--update</code> only refreshes application code (web PHP/HTML viewers and <code>tools/*.sh</code>). Configuration files deployed at install time (<code>smb.conf</code>, <code>fullaudit.conf</code>, <code>smbweb.conf</code>) are never overwritten by <code>--update</code>, since they may contain manual edits (custom shares, <code>hosts allow</code>, interfaces, etc.). To pick up changes to these files after an update, compare them manually against <code>conf/</code> and <code>web/smbweb.conf</code> in the repository and apply changes by hand.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>--update</code> solo actualiza el código de la aplicación (visores web PHP/HTML y <code>tools/*.sh</code>). Los archivos de configuración desplegados en la instalación (<code>smb.conf</code>, <code>fullaudit.conf</code>, <code>smbweb.conf</code>) nunca son sobreescritos por <code>--update</code>, ya que pueden contener ediciones manuales (shares personalizados, <code>hosts allow</code>, interfaces, etc.). Para incorporar cambios en estos archivos tras una actualización, compáralos manualmente contra <code>conf/</code> y <code>web/smbweb.conf</code> en el repositorio y aplica los cambios a mano.
    </td>
  </tr>
</table>

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The shared folder is independent of the installer. To remove it, do so manually: <code>rm -rf /home/$local_user/shared</code>
    </td>
    <td style="width: 50%; vertical-align: top;">
      La carpeta compartida es independiente del instalador. Para eliminarla, hazlo manualmente: <code>rm -rf /home/$local_user/shared</code>
    </td>
  </tr>
</table>

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

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>smbstack.env</code> sets <code>TRUSTED_PROXIES="127.0.0.1"</code> by default. It tells <code>web/shared.php</code> to use the <code>CF-Connecting-IP</code> / <code>X-Forwarded-For</code> header (if present) instead of <code>REMOTE_ADDR</code> when logging the client IP for requests arriving from localhost — so a local tunnel's loopback connection isn't recorded as the "client" in the audit log. No effect on direct LAN access.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <code>smbstack.env</code> establece <code>TRUSTED_PROXIES="127.0.0.1"</code> por defecto. Le indica a <code>web/shared.php</code> que use el encabezado <code>CF-Connecting-IP</code> / <code>X-Forwarded-For</code> (si está presente) en lugar de <code>REMOTE_ADDR</code> al registrar la IP del cliente para solicitudes que lleguen desde localhost — así la conexión loopback de un túnel local no se registra como el "cliente" en el log de auditoría. Sin efecto en acceso LAN directo.
    </td>
  </tr>
</table>

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

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To use a custom shared folder path outside <code>/home/$local_user/</code>, edit <code>/etc/samba/smb.conf</code> and <code>/etc/apache2/sites-available/smbweb.conf</code> manually after installation.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para usar una ruta de carpeta compartida personalizada fuera de <code>/home/$local_user/</code>, edita <code>/etc/samba/smb.conf</code> y <code>/etc/apache2/sites-available/smbweb.conf</code> manualmente tras la instalación.
    </td>
  </tr>
</table>

### Recycle Bin

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      SMBstack uses the Samba <code>vfs_recycle</code> module to redirect file deletions to a hidden recycle bin instead of permanently removing them. The bin is stored inside the shared folder under <code>.recycle/</code> and organized by the system user who performed the deletion.
    </td>
    <td style="width: 50%; vertical-align: top;">
      SMBstack usa el módulo <code>vfs_recycle</code> de Samba para redirigir las eliminaciones a una papelera de reciclaje oculta en lugar de borrar permanentemente los archivos. La papelera se almacena dentro de la carpeta compartida en <code>.recycle/</code> y se organiza por el usuario del sistema que realizó la eliminación.
    </td>
  </tr>
</table>

#### Dual-access layout / Estructura de doble acceso

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      SMBstack exposes the shared folder through two independent channels, each operating under a different system user:
    </td>
    <td style="width: 50%; vertical-align: top;">
      SMBstack expone la carpeta compartida a través de dos canales independientes, cada uno operando bajo un usuario del sistema diferente:
    </td>
  </tr>
</table>

| Channel | System user | Recycle path |
|---------|-------------|--------------|
| SMB (LAN clients) | `smbguest` (set by `force user` in `smb.conf`) | `.recycle/smbguest/` |
| Web interface (Apache) | `www-data` | `.recycle/www-data/` |

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This is why the recycle bin directory contains one subdirectory per access channel:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Por eso el directorio de la papelera contiene un subdirectorio por canal de acceso:
    </td>
  </tr>
</table>

```
.recycle/
├── smbguest/               # Files deleted by Windows/Linux SMB clients on the LAN
│   └── DOCUMENTS/
│       ├── report.docx
│       └── Copy #1 of report.docx
└── www-data/               # Files deleted via the web browser interface
    └── 20260623/
        └── invoice.pdf
```

#### File versioning / Versionado de archivos

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      When <code>recycle:versions = yes</code> is active, deleting a file that already exists in the recycle bin does not overwrite it — the new copy is saved alongside the original with a <code>Copy #N of</code> prefix:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Cuando <code>recycle:versions = yes</code> está activo, eliminar un archivo que ya existe en la papelera no lo sobreescribe — la nueva copia se guarda junto a la original con el prefijo <code>Copy #N of</code>:
    </td>
  </tr>
</table>

```
.recycle/smbguest/DOCUMENTS/
├── report.docx             ← first deletion
└── Copy #1 of report.docx  ← second deletion of the same file
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To exclude specific file types from versioning, use <code>recycle:noversions</code>. These types are still recycled, but repeated deletions <strong>overwrite</strong> the previous copy in the bin rather than creating a numbered duplicate:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para excluir tipos de archivo del versionado, usa <code>recycle:noversions</code>. Estos archivos siguen yendo a la papelera, pero eliminaciones repetidas <strong>sobreescriben</strong> la copia anterior en lugar de crear una nueva numerada:
    </td>
  </tr>
</table>

```ini
# All files keep multiple versions:
recycle:versions = yes

# These types are recycled but NOT versioned — second delete overwrites the first:
recycle:noversions = *.dat,*.ini
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Use <code>noversions</code> for files where accumulating copies adds no value: runtime data files, config dumps, ini snapshots, and similar.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Usa <code>noversions</code> para archivos donde acumular copias no aporta valor: archivos de datos en tiempo de ejecución, volcados de configuración, snapshots de ini y similares.
    </td>
  </tr>
</table>

#### Configuration reference / Referencia de configuración

| Parameter | Value | Description | Descripción |
|-----------|-------|-------------|-------------|
| `recycle:repository` | `.recycle/%U` | Path of the recycle bin inside the share. `%U` is replaced at runtime by the effective system user: `smbguest` for SMB clients, `www-data` for the web interface. Creates one subdirectory per access channel. | Ruta de la papelera dentro del share. `%U` se reemplaza en tiempo de ejecución por el usuario del sistema efectivo: `smbguest` para clientes SMB, `www-data` para la interfaz web. Crea un subdirectorio por canal de acceso. |
| `recycle:directory_mode` | `0775` | Permissions for each per-user recycle subdirectory that Samba creates automatically. `0775` allows the `sambashare` group (which includes both `smbguest` and `www-data`) to read and write. The Samba default is `0700` (owner only), which would block group access. | Permisos del subdirectorio de papelera por usuario que Samba crea automáticamente. `0775` permite al grupo `sambashare` (que incluye tanto `smbguest` como `www-data`) leer y escribir. El valor por defecto de Samba es `0700` (solo propietario), lo que bloquearía el acceso de grupo. |
| `recycle:keeptree` | `yes` | Preserves the original directory path inside the recycle bin. A file deleted from `DOCUMENTS/Q1/report.docx` is stored as `.recycle/smbguest/DOCUMENTS/Q1/report.docx`, making it easy to trace its origin. | Preserva la ruta original del directorio dentro de la papelera. Un archivo eliminado de `DOCUMENTS/Q1/report.docx` se almacena como `.recycle/smbguest/DOCUMENTS/Q1/report.docx`, facilitando rastrear su origen. |
| `recycle:versions` | `yes` | Keeps multiple copies when the same file is deleted more than once. Each new copy is named `Copy #N of filename`. Set to `no` to keep only the most recent deleted copy. | Conserva múltiples copias cuando el mismo archivo se elimina más de una vez. Cada nueva copia se nombra `Copy #N of nombre`. Establécelo en `no` para conservar solo la copia eliminada más reciente. |
| `recycle:noversions` | `*.dat,*.ini` | File patterns excluded from versioning. These files are still sent to the recycle bin, but repeated deletions overwrite the existing copy instead of creating a numbered duplicate. Useful for config snapshots, runtime data, and similar low-value files. Only applies when `recycle:versions = yes`. | Patrones de archivos excluidos del versionado. Estos archivos igualmente van a la papelera, pero eliminaciones repetidas sobreescriben la copia existente en lugar de crear una nueva numerada. Útil para snapshots de configuración, datos de runtime y similares. Solo aplica cuando `recycle:versions = yes`. |
| `recycle:touch` | `yes` | Updates the file's access time (`atime`) when it is moved to the bin. Useful for knowing when a file was recycled independently of its original modification date. | Actualiza el tiempo de acceso (`atime`) del archivo al moverlo a la papelera. Útil para saber cuándo fue reciclado independientemente de su fecha de modificación original. |
| `recycle:exclude` | `*.tmp,*.temp,*.o,~$*,*.~??,*.log,*.trace,*.TMP,*.asv` | File patterns that are permanently deleted instead of recycled. Covers temporary files, Office lock files (`~$*`), Matlab autosave files (`*.asv`), and compiled object files (`*.o`). | Patrones de archivos que se eliminan permanentemente en lugar de reciclarse. Cubre archivos temporales, archivos de bloqueo de Office (`~$*`), autoguardados de Matlab (`*.asv`) y archivos objeto compilados (`*.o`). |
| `recycle:exclude_dir` | `/temp,/tmp,/cache,/.Trash-1000` | Directories whose files bypass the recycle bin and are permanently deleted. Paths are relative to the share root. `/.Trash-1000` is the trash directory that some Linux desktop clients create directly on the share. | Directorios cuyos archivos omiten la papelera y se eliminan permanentemente. Las rutas son relativas a la raíz del share. `/.Trash-1000` es el directorio de papelera que algunos clientes Linux de escritorio crean directamente en el share. |
| `recycle:maxsize` | `1073741824` | Maximum file size in bytes (1 GB) that will be recycled. Files larger than this are permanently deleted to prevent a single file from filling up the bin. | Tamaño máximo de archivo en bytes (1 GB) que será reciclado. Los archivos mayores se eliminan permanentemente para evitar que un solo archivo llene la papelera. |
| `hide files` | `/.recycle/` | Hides the `.recycle` directory from Windows Explorer and mapped drive views. The directory remains accessible from the server filesystem. | Oculta el directorio `.recycle/` de la vista del Explorador de Windows y las unidades de red mapeadas. El directorio sigue siendo accesible desde el sistema de archivos del servidor. |

#### Automatic cleanup / Limpieza automática

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The installer registers a weekly cron job (under <code>root</code>) that removes recycled files older than 7 days:
    </td>
    <td style="width: 50%; vertical-align: top;">
      El instalador registra una tarea cron semanal (bajo <code>root</code>) que elimina los archivos reciclados con más de 7 días de antigüedad:
    </td>
  </tr>
</table>

```bash
@weekly find "/home/$local_user/shared/.recycle/" -depth -mindepth 1 -mtime +7 -delete
```

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      To adjust the retention period or inspect the entry:
    </td>
    <td style="width: 50%; vertical-align: top;">
      Para ajustar el período de retención o inspeccionar la entrada:
    </td>
  </tr>
</table>

```bash
sudo crontab -e
```

---

### Full Audit

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      SMBstack uses the Samba <code>vfs_full_audit</code> module to log file operations to <code>/var/log/samba/log.audit</code> via rsyslog. Only successful operations are recorded; failures are suppressed to keep the log clean.
    </td>
    <td style="width: 50%; vertical-align: top;">
      SMBstack usa el módulo <code>vfs_full_audit</code> de Samba para registrar operaciones de archivos en <code>/var/log/samba/log.audit</code> vía rsyslog. Solo se registran operaciones exitosas; los fallos se suprimen para mantener el log limpio.
    </td>
  </tr>
</table>

#### Configuration reference / Referencia de configuración

| Parameter | Value | Description | Descripción |
|-----------|-------|-------------|-------------|
| `full_audit:logfile` | `/var/log/samba/log.audit` | Destination log file, written via the rsyslog rule in `/etc/rsyslog.d/fullaudit.conf`. | Archivo de log de destino, escrito mediante la regla rsyslog en `/etc/rsyslog.d/fullaudit.conf`. |
| `full_audit:prefix` | `%I\|%m\|%S` | Fields prepended to each log entry: `%I` = client IP address, `%m` = client machine name, `%S` = share name. | Campos que se anteponen a cada entrada del log: `%I` = IP del cliente, `%m` = nombre del equipo cliente, `%S` = nombre del share. |
| `full_audit:success` | `mkdirat renameat unlinkat pwrite` | VFS operations logged when they succeed. See table below. | Operaciones VFS que se registran cuando tienen éxito. Ver tabla a continuación. |
| `full_audit:failure` | `none` | No failed operations are logged. | No se registran operaciones fallidas. |
| `full_audit:facility` | `LOCAL5` | rsyslog facility used to route audit entries to the dedicated log file, keeping them separate from general system logs. | Facility de rsyslog usada para enrutar las entradas de auditoría al archivo dedicado, manteniéndolas separadas de los logs generales del sistema. |
| `full_audit:priority` | `notice` | Syslog priority level assigned to audit entries. | Nivel de prioridad syslog asignado a las entradas de auditoría. |

#### Logged operations / Operaciones registradas

| Samba syscall | Triggered by | Desencadenado por |
|---------------|--------------|-------------------|
| `mkdirat` | Creating a directory via SMB or the web interface | Creación de un directorio vía SMB o la interfaz web |
| `renameat` | Renaming or moving a file or folder. Also triggered by Windows clients when saving a new file — Windows creates a temporary file first, then renames it to the final name. Log format: `source_path\|destination_path`. Does **not** appear for recycle bin operations. | Renombrado o movimiento de archivo o carpeta. También lo disparan los clientes Windows al guardar un archivo nuevo — Windows crea primero un archivo temporal y luego lo renombra al nombre final. Formato en el log: `ruta_origen\|ruta_destino`. **No** aparece para operaciones de papelera de reciclaje. |
| `unlinkat` | File deletion. This entry appears for **both** permanent deletions and files moved to the recycle bin — `vfs_full_audit` intercepts the original `unlink` call before `vfs_recycle` redirects it, so the audit log cannot distinguish between the two. | Borrado de archivo. Esta entrada aparece tanto para borrados permanentes como para archivos movidos a la papelera — `vfs_full_audit` intercepta la llamada `unlink` original antes de que `vfs_recycle` la redirija, por lo que el log no puede distinguir entre ambos casos. |
| `pwrite` | Data written to an open file **via SMB**. Two independent sources produce this same action name: Samba itself (for SMB clients) and, separately, `shared.php` (for uploads/new files created through the web interface, which never go through `smbd` and so `vfs_full_audit` can't see them on its own). To tell them apart in the raw log, check the syslog `$user` field before `smbd_audit:` — the web interface always logs it as `www-data`. | Datos escritos en un archivo abierto **vía SMB**. Dos fuentes independientes generan esta misma acción: Samba (para clientes SMB) y, por separado, `shared.php` (para subidas/archivos nuevos creados desde la interfaz web, que nunca pasan por `smbd` y por eso `vfs_full_audit` no puede verlas por sí solo). Para distinguirlas en el log crudo, revisa el campo `$user` del syslog antes de `smbd_audit:` — la interfaz web siempre lo registra como `www-data`. |

> **Note:** There is no way to distinguish a recycled file from a permanently deleted one in the audit log — both appear as `unlinkat`. To determine whether a deleted file was recycled, check the `.recycle/` directory on the filesystem. `renameat` entries are logged with a `source|destination` format and indicate an explicit rename or move, including the Windows pattern of creating a temp file and renaming it on save.
>
> **Nota:** No es posible distinguir en el log de auditoría un archivo reciclado de uno eliminado permanentemente — ambos aparecen como `unlinkat`. Para determinar si un archivo fue reciclado, verifica el directorio `.recycle/` en el sistema de archivos. Las entradas `renameat` se registran con el formato `origen|destino` e indican un renombrado o movimiento explícito, incluyendo el patrón de Windows de crear un archivo temporal y renombrarlo al guardar.

> **Why `openat` is not audited:** it was evaluated and deliberately left out of `full_audit:success` by default. Every file/directory open — including plain browsing, reads and downloads, not just writes — generates an entry, so a single Explorer window left open on a busy folder produces dozens of near-duplicate lines per second. That noise buries the events actually worth reviewing without adding meaningful traceability, since `pwrite` already covers the write itself. This is a project default, not a hard limitation — if your use case needs to audit opens/reads too, add it yourself in `/etc/samba/smb.conf`:
> ```
> full_audit:success = mkdirat renameat unlinkat pwrite openat
> ```
> then `testparm` and `systemctl restart smbd`. `--update` won't touch this — `smb.conf` is never overwritten after install, so the change persists.
>
> **Por qué `openat` no se audita:** se evaluó y se dejó fuera de `full_audit:success` por defecto, a propósito. Cada apertura de archivo o carpeta — incluyendo simple navegación, lecturas y descargas, no solo escrituras — genera una entrada, así que una sola ventana del Explorador abierta sobre una carpeta con actividad produce decenas de líneas casi idénticas por segundo. Ese ruido entierra los eventos que sí vale la pena revisar sin aportar trazabilidad real, ya que `pwrite` ya cubre la escritura en sí. Esto es un valor por defecto del proyecto, no una limitación forzosa — si tu caso de uso necesita auditar también aperturas/lecturas, agrégalo tú mismo en `/etc/samba/smb.conf`:
> ```
> full_audit:success = mkdirat renameat unlinkat pwrite openat
> ```
> luego `testparm` y `systemctl restart smbd`. `--update` no lo tocará — `smb.conf` nunca se sobreescribe tras la instalación, así que el cambio persiste.

---

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

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <code>inotify-tools</code> is required: <code>apt-get install -y inotify-tools</code>
    </td>
    <td style="width: 50%; vertical-align: top;">
      Se requiere <code>inotify-tools</code>: <code>apt-get install -y inotify-tools</code>
    </td>
  </tr>
</table>

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

> **CSRF protection:** `web/shared.php` has no login by design — guest access for the whole LAN (and the tunnel, if enabled) is intentional. What it does have is a per-session token on the four state-changing forms (upload, new folder, new file, recycle), so a POST is only accepted if it was actually loaded from the page first. This blocks a malicious site elsewhere from silently auto-submitting a form to your server through a visitor's browser (CSRF); it does **not** restrict who can use the browser itself — that's still governed purely by network reachability (LAN / tunnel), same as today.
>
> **Protección CSRF:** `web/shared.php` no tiene login por diseño — el acceso de invitado para toda la LAN (y el túnel, si está activo) es intencional. Lo que sí tiene es un token por sesión en los cuatro formularios que modifican estado (subir, nueva carpeta, nuevo archivo, papelera), de modo que un POST solo se acepta si realmente se cargó la página antes. Esto bloquea que un sitio malicioso ajeno autoenvíe un formulario a tu servidor a través del navegador de un visitante (CSRF); **no** restringe quién puede usar el explorador en sí — eso sigue gobernado únicamente por el alcance de red (LAN / túnel), igual que hoy.

**Optional tunnel:**
- [Cloudflare Tunnel (start|stop|status) - Zero Trust Activation Recommended](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
