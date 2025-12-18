# [Scripts](https://www.maravento.com)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Script Repository.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Repositorio de Scripts.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/scripts
```

## HOW TO USE

---

### BASH (Linux)

Tested on: Ubuntu 22.04/24.04 x64

#### Application and Deployment Utilities

- [Crypto Notify (Top 5)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cryptonotify.sh)
- [Joomla (install|remove with Apache/MySQL/PHP/mkcert)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/joomla.sh)
- [Rustdesk Client (install|uninstall|update)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rustdesk.sh)

#### Cloud & Backup

- [FreeFileSync Update](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ffsupdate.sh)
- [Gdrive (Mount | Umount - to folder `/home/$USER/gdrive`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/gdrive.sh)
- [MEGAsync Instances (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/msyncs)
- [Rclone Cloud (Google Drive, PCloud, Dropbox, OneDrive, Mega, etc.) - mount|umount (start|stop|status|restart)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rcloud.sh)
- [Rclone Sync (Google Drive, PCloud, Dropbox, OneDrive, Mega, etc.) - Sync to Download|Upload Folder](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rsync.sh)

#### Context Menu Tools (Nautilus, Caja, Thunar, Nemo)

- [copy path](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/copypath)
- [check MD5](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checkmd5)
- [check sha256](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checksha256)
- [KDE Connect (Send files to smarthphone)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/send2phone)
- [make MD5](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/makemd5)
- [make sha256](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/makesha256)
- [mount manager (smb, sftp, fuse)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/mountman)

#### Networking & Security

- [Android 2 PC via scrcpy (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/droid2pc.sh)
- [ArpON table filter](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/arponscan.sh)
- [Arpwatch (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/arpwatch.sh)
- [Cloudflare Tunnel (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cftunnel.sh)
- [Internet Watchdog (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/watchdog.sh)
- [IP Kill](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ipkill.sh)
- [Netplan Switch (install|uninstall|status|help)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/npswitch.sh)
- [ngLocalhost Tunnel (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/nglocalhost.sh)
- [Port Kill (check port with: `sudo netstat -lnp | grep "port"`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/portkill.sh)
- [Serveo Tunnel (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/serveo.sh)
- [Unifi Hotspot Client Access (via Linux Server with Iptables)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/unifihotspot.sh)
- [Wireguard VPN (install|uninstall - server|client)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/wireguard.sh)

#### Proxy

- [Squid Analysis Tool)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/squidtool.sh)
- [Squid-OpenSSL (ssl-bump)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/sslbump.sh)

#### Storage and File Operations

- [Cleaner - Delete files (Thumbs.db, Zone.identifier, encryptable, etc.)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cleaner.sh)
- [Disk Temp (HDD/SSD/NVMe)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/disktemp.sh)
- [Drive Crypt (Cryptomator Encrypted Disk - mount|umount - to folder `/home/$USER/dcrypt`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/drivecrypt.sh)
- [Mass Unzip with Pass](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/massunzip.sh)
- [NTFS Disk Drive (mount|umount with ntfs-3g)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ntfsdrive.sh)
- [System Migration Tool](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/appbr.sh)
- [TRIM for SSD/NVMe](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/trim.sh)
- [Watch Directories (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/watchdir.sh)

#### System and Resource Management

- [Check Bandwidth (Set Minimum download|upload Value)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/bandwidth.sh)
- [Check Cron](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checkcron.sh)
- [Force Logrotate](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/logrotate.sh)
- [Kill Process By Name](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/pskill.sh)
- [Kworker Kill](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/kworker.sh)
- [Limit processes with CPU Limit (start|stop|status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cpulimit.sh)
- [Realtek Linux drivers](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/realtekdrv.sh)
- [Winpower UPS (install|remove|start|stop|status|restart)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/winpower.sh)

#### Virtualization

- [Bridge Management for Virtualization (on|off|status|clean)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/bridge.sh)
- [Docker + Portainer (install|remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/docker.sh)
- [phpVirtualBox Install](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/phpvbox.sh)
- [Virtual Hard Disk VHD image (.img) (loop or kpartx - create|mount|umount)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vdisk.sh)
- [VirtualBox 7.1 (install|remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vbox.sh)
- [VMs Virtualbox (start|stop|status|shutdown|reset) (replace `my_vm` with the name of your vm)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vm.sh)
- [WinBoat (install|remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/winboat.sh)

#### Webmin Module Installation Tools

- [Netplan Manager - Networking Category (install|uninstall)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/netplanmgr.sh)
- [Services Monitor - System Category (install|uninstall)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/servicemon.sh)
- [Squid Monitor - Server Category (install|uninstall)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/squidmon.sh)

### BATCH (Windows)

Tested on: Windows 10/11 x64

- [FixPrint (Print Queue Cleaning)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/fixprint.bat)
- [Mozilla Thunderbird (Backup Profiles to USB)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/mtpbackup.bat)
- [Net Reset (Proxy and NIC)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/netreset.bat)
- [Non-Essential Services (disable|auto)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/nonservices.bat)
- [Regedit Backup (to `%HOMEDRIVE%\RegBackup`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/regbackup.bat)
- [Safe Boot (Modes: safe boot minimal|safe boot with network|normal)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/safeboot.bat)
- [SMB Config (Modify smb1|smb signing|insecure guest access)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/smbconf.bat)
- [Unifi Network Server Setup](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/unifisetup.bat)
- [Uniform Server (Change MySQL/Apache Ports - Set portable|permanent - Run With System)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/uzeroconf.bat)
- [VTools QEMU/KVM (Spice, VirtIO, and WinFsp Setup as a Service)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/vtools.bat)
- [WMIC (Add|Remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/wmic.bat)

### PYTHON (Linux)

Tested on: Ubuntu 22.04/24.04

- [Git Folder Download (Replaces Subversion SVN EOS/EOL on GitHub/GitLab)](https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py)

### VBScript (Windows)

Tested on: Windows 7/10/11 x64

- [Autorun Disable](https://raw.githubusercontent.com/maravento/vault/master/scripts/vbs/autorun.vbs)

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
