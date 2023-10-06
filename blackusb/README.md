# [BlackUSB](https://www.maravento.com)

[![status-frozen](https://img.shields.io/badge/status-frozen-blue.svg)](https://github.com/maravento/vault)

**BlackUSB** is a experimental script, that prevents theft of personal data, malware, forensic tools, BadUSB (USB Rubber Ducky), etc. Generates a whitelist of usb/hid devices and blocks any other unauthorized insertion of unknown devices, using udev rules.

**BlackUSB** es un script experimental, que previene el robo de datos personales, malware, herramientas forenses, BadUSB (USB Rubber Ducky), etc. Genera una lista blanca de dispositivos usb/hid y bloquea cualquier otra inserción no autorizada de dispositivos desconocidos, usando reglas udev

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/blackusb"
```

## FOR LINUX OS

---

It is a bash script that generates a white list of usb/hid devices and blocks any other unauthorized insertion of unknown devices, using udev rules / Es un bash script que genera una lista blanca de dispositivos usb/hid y bloquea cualquier otra inserción no autorizada de dispositivos desconocidos, usando reglas udev

```bash
sudo wget -q -N https://raw.githubusercontent.com/maravento/vault/master/blackusb/linux/blackusb.sh -O /path_to/blackusb.sh && sudo chmod +x /path_to/blackusb.sh
```

### How To Use (For Linux)

Example:

`blackusb.sh show` or `blackusb.sh s`

```bash
sudo /path_to/blackusb.sh s
 0 Name=xHCI Host Controller, Vendor=1d6b, Product=0003, Serial=0022:00:14.0
 1 Vendor=8087, Product=07dc
 2 Name=USB2.0-CRW, Vendor=0bda, Product=0129, Serial=20100001396000000
 3 Name=Integrated_Webcam_HD, Vendor=0c45, Product=6710
 4 Name=HID-compliant mouse, Vendor=046d, Product=c530
 5 Name=xHCI Host Controller, Vendor=1d6b, Product=0002, Serial=0022:00:14.0
```

### Data Sheet (For Linux)

|Full|Short|Description|
|----|-----|-----------|
|show|s|Show currently connected usb devices / Muestra los dispositivos conectados|
|on|o|Turn on blackusb and generate white list of connected USB devices / Activar blackusb y genera lista blanca de dispositivos USB conectados|
|eject|j|Choose a device from the list to eject or add entry / Elija un dispositivo de la lista para expulsarlo o agregar entrada|
|off|x|Temporarily deactivate blackusb / Desactiva temporalmente blackusb|
|gen|g|Generate or refresh whitelist udev rules file / Genera o refresca lista blanca de dispositivos lista udev usb|
|del|d|Delete udev rules file contain white list usb devices / Elimina archivo udev que contiene lista blanca de dispositivos usb|
|edit|e|Edit udev rules file manually / Edita manualmente las reglas udev|

### Paranoic Mode

It consists of turning off your terminal when inserting an unauthorized and/or unknown usb device, rather than locking it. To activate it, edit the script manually and uncomment the line / Consiste en apagar su terminal cuando se inserte un dispositivo usb no autorizado y/o desconocido, en lugar de bloquearlo. Para activarlo, edite manualmente el script y descomente la línea

`'poweroff'`

### Logs

`/var/log/blackusb.log`

Example:

```bash
2017-07-06 12:34:10 Blackusb triggered!
Unknown Device Blocked: SUBSYSTEM=="usb", ATTR{idVendor}=="0781", ATTR{idProduct}=="5567", ATTR{serial}=="4C530799910104103543"
Cruzer Blade
```

### Dependencies

`bash`, `udev`

### Fork

This project is based on: / Este proyecto está basado en:

[usbkill](https://github.com/hephaest0s/usbkill)

[usbdeath](https://github.com/trpt/usbdeath)

## FOR WINDOWS OS

---

Tool to block unauthorized devices USB, HID, HDC, Bluetooth, IEEE, SmartCardReader, PCMCIA, Printers, SCSI, RAID, etc. Cleans previous device installations, rescans those connected and blocks new ones / Herramienta para bloquear dispositivos no autorizados USB, HID, HDC, Bluetooth, IEEE, SmartCardReader, PCMCIA, Printers, SCSI, RAID, etc. Limpia instalaciones previas de dispositivos, reescanea los conectados y bloquea los nuevos

### Data Sheet (For Windows)

|File|Version|OS|Size|
|----|-------|--|----|
|[blackusb.exe (.zip)](https://raw.githubusercontent.com/maravento/vault/master/blackusb/win/blackusb.zip)|1.0|Windows 7/8/10 x86 x64|4,2 MB|

### How To Use (For Windows)

- Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System and close all windows / Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo y cierre todas las ventanas
- Download BlackUSB.exe (.zip)), unzip it on your desktop / Descargue BlackUSB.exe (.zip), descomprimirlo en el escritorio
- Run Setup by double-clicking accept execution with privileges and follow the onscreen instructions / Ejecútelo con doble clic, acepte la ejecución con privilegios y siga las instrucciones en pantalla

### Important Before Use

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/blackusb/img/blackusb.png">
</div>

- Do not press **BLOCK** button twice in a row or it will block all USB/HID devices. / No pulse el botón **BLOCK**, dos veces seguidas, o bloqueará todos los dispositivos USB/HID
- If you have defined [GPO policies](https://en.wikipedia.org/wiki/Group_Policy) on your system, they will be rewritten. Make a GPO backup before using BlackUSB / Si tiene establecidas [políticas GPO](https://es.wikipedia.org/wiki/Directiva_de_Grupo) en su sistema, serán reescritas. Haga backup GPO antes de usar BlackUSB
- To add a new USB/HID device to your whitelist (excluded from blocking) you must press the RESTORE button to remove the restrictions, then connect the new device and finally press BLOCK button / Para incorporar un nuevo dispositivo USB/HID a su lista blanca (excluidos de bloqueo) debe pulsar el botón RESTORE para eliminar las restricciones, luego conectar el nuevo dispositivo y finalmente pulsar el botón BLOCK
- After executing the BLOCK option, the **whitelist.txt** report file, which contains the white list of USB/HID devices excluded from the lock, will be displayed on your desktop. This list will be deleted when using the RESTORE option / Despues de ejecutar la opción BLOCK, aparecerá en su escritorio el archivo de reporte **whitelist.txt**, que contiene la lista blanca de dispositivos USB/HID excluidos del bloqueo. Esta lista será eliminada al utilizar la opción RESTORE
- BlackUSB for Windows is included in [Dextroyer](https://www.maravento.com/p/dxt.html) / BlackUSB para Windows está incluido en [Dextroyer](https://www.maravento.com/p/dxt.html)

## PACKAGES AND TOOLS

---

- [74cz](http://74.cz/es/make-sfx/index.php)
- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [Resource Hacker](http://www.angusj.com/resourcehacker/)
- [Robust File Copy](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [robvanderwoude](http://www.robvanderwoude.com/)
- [USBOblivion](https://sourceforge.net/projects/usboblivion/)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
