# [Scripts](https://www.maravento.com)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

Script Repository / Repositorio de Scripts

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/scripts"
```

## HOW TO USE

---

### Bash (Linux)

Tested on: / Probado en: Ubuntu 20.04/22.04 x64

- [ARP table filter](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/arponscan.sh)
- [Check Bandwidth (Set Minimum Download | Upload Value)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/bandwidth.sh)
- [Check Cron](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/checkcron.sh)
- [Disk Temp (HDD/SSD/NVMe)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/disktemp.sh)
- [Drive Crypt (Cryptomator Encrypted Disk - Mount | Umount - to folder `/home/$USER/dcrypt`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/drivecrypt.sh)
- [FreeFileSync Update](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ffsupdate.sh)
- [Gdrive (Mount | Umount - to folder `/home/$USER/gdrive`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/gdrive.sh)
- [IP Kill](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/ipkill.sh)
- [Kill Process By Name](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/pskill.sh)
- [Kworker Kill](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/kworker.sh)
- [Limit processes with CPU Limit (start | stop | status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/cpulimit.sh)
- [Mass Unzip with Pass](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/massunzip.sh)
- [Net Report](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/netreport.sh)
- [phpVirtualBox (Install)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/phpvbox.sh)
- [Port Kill (check port with: `sudo netstat -lnp | grep "port"`)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/portkill.sh)
- [Rclone Cloud (Google Drive, PCloud, Dropbox, OneDrive, Mega, etc. - Mount | Umount with start | stop | restart | status)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rcloud.sh)
- [Rclone Sync (Google Drive, PCloud, Dropbox, OneDrive, Mega, etc. - Sync to Download | Upload Folder)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/rsync.sh)
- [Send files to phone with KDE Connect (for Nautilus/Caja)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/send2phone)
- [TRIM (SSD/NVMe)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/trim.sh)
- [Virtual Hard Disk VHD (image (.img) - loop or kpartx - Create | Mount | Umount](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vdisk.sh)
- [VirtualBox (Install | Remove)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vboxinstall.sh)
- [VMs Virtualbox (start | stop | shutdown | reset | status - replace `my_vm` with the name of your vm)](https://raw.githubusercontent.com/maravento/vault/master/scripts/bash/vm.sh)

### Batch (Windows)

Tested on: / Probado en: Windows 7/10/11 x64

- [Net Reset - Proxy and NIC](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/netreset.bat)
- [Non-Essential Services - Disable | Auto](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/nonservices.bat)
- [Regedit Backup - to `%homedrive%\RegBackup`](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/regbackup.bat)
- [Safe Boot - Modes: Safe with Network | Safe Minimal | Normal](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/safeboot.bat)
- [SMB signing - Activate | Deactivate](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/smbsign.bat)
- [SMB1 protocol - Activate | Deactivate](https://raw.githubusercontent.com/maravento/vault/master/scripts/batch/smb1.bat)

### VBScript (Windows)

Tested on: / probado en: Windows 7/10/11 x64

- [Autorun Disable](https://raw.githubusercontent.com/maravento/vault/master/scripts/vbs/autorun.vbs)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
