# [Scripts](https://github.com/maravento)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Script Repository.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Repositorio de Scripts.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python3 gitfolder.py https://github.com/maravento/vault/scripts
```

## HOW TO USE

---

### BASH (Linux)

Tested on: Ubuntu 24.04.x LTS x64

#### AI

- [AI Stack Manager (Docker: Portainer + Ollama + Open WebUI + LLM Models | Opcional: OpenCode + LM Studio)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/aistack.sh)

#### Containers & Virtualization

- [Bridge Management for Virtualization (on|off|status|clean)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/bridge.sh)
- [phpVirtualBox Install](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/phpvbox.sh)
- [Virtual Hard Disk VHD image (.img) (loop or kpartx - create|mount|umount)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vdisk.sh)
- [VirtualBox 7.x (install|remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vbox.sh)
- [VMs Virtualbox (start|stop|status|shutdown|reset) (replace `my_vm` with the name of your vm)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vm.sh)
- [WinBoat (install|remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/winboat.sh)

#### Context Menu Tools (Nautilus, Caja, Thunar, Nemo)

- [check MD5](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checkmd5)
- [check sha256](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checksha256)
- [copy path](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/copypath)
- [KDE Connect (Send files to smarthphone)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/send2phone)
- [make MD5](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/makemd5)
- [make sha256](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/makesha256)
- [mount manager (smb, sftp, fuse)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/mountman)

#### Networking, Remote Access & Security

- [Android 2 PC via scrcpy (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/droid2pc.sh)
- [ArpON table filter](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/arponscan.sh)
- [Arpwatch (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/arpwatch.sh)
- [Check Bandwidth (Set Minimum download|upload Value)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/bandwidth.sh)
- [Internet Watchdog (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/watchdog.sh)
- [Iperf3 Client](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/iperf3.sh)
- [Netplan Switch (install|uninstall|status|help)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/npswitch.sh)
- [Port Kill (check port with: `sudo netstat -lnp | grep "port"`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/portkill.sh)
- [Rustdesk Client (install|uninstall|update)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rdclient.sh)
- [Rustdesk Server (install|uninstall|update)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rdserver.sh)
- [x11vnc (install|uninstall|start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/x11vncmgr.sh)

#### Proxy & Firewall
- [IP Kill](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ipkill.sh)
- [Squid Analysis Tool](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/squidtool.sh)
- [Squid-OpenSSL (ssl-bump)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/sslbump.sh)

#### Server & Deployment

- [Cloudflare Tunnel (create|start|startall|stop|status) - Zero Trust Activation Recommended](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)
- [Docker + Portainer (install|remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/docker.sh)
- [Joomla (install|remove with Apache/MySQL/PHP/mkcert)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/joomla.sh)
- [ngLocalhost Tunnel (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/nglocalhost.sh)
- [Serveo Tunnel (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/serveo.sh)
- [Wireguard VPN (install|uninstall - server|client)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/wireguard.sh)

#### Storage, Backup & Cloud

- [Cleaner - Delete files (Thumbs.db, Zone.identifier, encryptable, etc.)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cleaner.sh)
- [Disk Check (HDD/SSD/NVMe)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/diskcheck.sh)
- [Drive Crypt (Cryptomator Encrypted Disk - mount|umount - to folder `/home/$USER/dcrypt`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/drivecrypt.sh)
- [File Extensions Report (find files by extension in target folder)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/filereport.sh)
- [FreeFileSync Update](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ffsupdate.sh)
- [Gdrive (Mount | Umount - to folder `/home/$USER/gdrive`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/gdrive.sh)
- [Mass Unzip with Pass](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/massunzip.sh)
- [MEGAsync Instances (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/msyncs)
- [NTFS Disk Drive (mount|umount with ntfs-3g)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ntfsdrive.sh)
- [Rclone Cloud (Google Drive, PCloud, Dropbox, OneDrive, Mega, etc.) - mount|umount (start|stop|status|restart)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rcloud.sh)
- [Rclone Sync (Google Drive, PCloud, Dropbox, OneDrive, Mega, etc.) - Sync to Download|Upload Folder](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rsync.sh)
- [System Migration Tool](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/appbr.sh)
- [TRIM for SSD/NVMe](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/trim.sh)

#### System, Hardware & Monitoring

- [Check Cron](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checkcron.sh)
- [Crypto Notify (Top 5)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cryptonotify.sh)
- [Force Logrotate](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/logrotate.sh)
- [Hardware Clock Sync](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/hwclock.sh)
- [Kill Process By Name](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/pskill.sh)
- [Kworker Kill](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/kworker.sh)
- [Limit processes with CPU Limit (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cpulimit.sh)
- [Lock Scripts (Randomized delayed self-rescheduling via at)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/lock.sh)
- [Realtek Linux drivers](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/realtekdrv.sh)
- [Winpower UPS (install|remove|start|stop|status|restart)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/winpower.sh)

#### Webmin Module Installation Tools

- [Netplan Manager - Networking Category (install|uninstall)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/netplanmgr.sh)
- [Services Monitor - System Category (install|uninstall)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/servicemon.sh)
- [Squid Monitor - Server Category (install|uninstall)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/squidmon.sh)

### BATCH (Windows)

Tested on: Windows 10/11 x64

#### Backup & Recovery

- [Drivers (Backup and Restore)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/driversbk.bat)
- [Mozilla Thunderbird (Backup Profiles to USB)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/mtpbackup.bat)
- [Regedit Backup (to `%HOMEDRIVE%\RegBackup`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/regbackup.bat)
- [Safe Boot (Modes: safe boot minimal|safe boot with network|normal)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/safeboot.bat)

#### Networking & System

- [Net Reset (Proxy and NIC)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/netreset.bat)
- [Non-Essential Services (disable|auto)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/nonservices.bat)
- [SMB Config (Modify smb1|smb signing|insecure guest access)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/smbconf.bat)
- [WMIC (Add|Remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/wmic.bat)

#### Hardware, Virtualization & Server

- [FixPrint (Print Queue Cleaning)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/fixprint.bat)
- [NVMeOptimizer (Add|Remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/nvmeoptimizer.bat)
- [Uniform Server (Change MySQL/Apache Ports - Set portable|permanent - Run With System)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/uzeroconf.bat)
- [VTools QEMU/KVM (Spice, VirtIO, and WinFsp Setup as a Service)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/vtools.bat)

#### Unifi Win Tools

- [Unifi Network Server Setup](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/unifisetup.bat)

### PYTHON (Linux)

Tested on: Ubuntu 24.04.x LTS x64

- [Email Scan (Replaces: BASE_URL and TARGET_EMAIL)](https://raw.githubusercontent.com/maravento/vault/master/scripts/python/emailscan.py)
- [Git Folder Download](https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py)
- [Link Check - Broken Link Scanner (Replaces: BASE_URL)](https://raw.githubusercontent.com/maravento/vault/master/scripts/python/linkcheck.py)

### VBScript (Windows)

Tested on: Windows 7/10/11 x64

- [Autorun Disable](https://raw.githubusercontent.com/maravento/vault/master/scripts/vbs/autorun.vbs)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
