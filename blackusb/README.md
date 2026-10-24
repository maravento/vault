<!--
BlackUSB documentation
FILE: blackusb/README.md
-->

# [BlackUSB](https://github.com/maravento)

[![status-frozen](https://img.shields.io/badge/status-frozen-blue.svg)](https://github.com/maravento)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <b>BlackUSB</b> is a experimental script, that prevents theft of personal data, malware, forensic tools, BadUSB (USB Rubber Ducky), etc. Generates a whitelist of usb/hid devices and blocks any other unauthorized insertion of unknown devices, using udev rules.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <b>BlackUSB</b> es un script experimental, que previene el robo de datos personales, malware, herramientas forenses, BadUSB (USB Rubber Ducky), etc. Genera una lista blanca de dispositivos usb/hid y bloquea cualquier otra inserción no autorizada de dispositivos desconocidos, usando reglas udev.
    </td>
  </tr>
</table>

<!-- markdownlint-disable MD033 -->

## REQUIREMENTS

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Only tested on Ubuntu 24.04/26.04 LTS. Other versions or distributions are not tested and are used at your own risk.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Solo probado en Ubuntu 24.04/26.04 LTS. Otras versiones o distribuciones no están probadas y se usan bajo tu responsabilidad.
    </td>
  </tr>
</table>

`bash`, `udev`, `systemd`, `util-linux`

## DATA SHEET

---

### Data Sheet (For Linux)

|Option|Description|
|------|-----------|
|`--show`|Show currently connected usb devices / Muestra los dispositivos conectados|
|`--on`|Turn on blackusb and generate white list of connected USB devices / Activar blackusb y genera lista blanca de dispositivos USB conectados|
|`--eject`|Choose a device from the list to eject or add entry / Elija un dispositivo de la lista para expulsarlo o agregar entrada|
|`--off`|Temporarily deactivate blackusb / Desactiva temporalmente blackusb|
|`--generate`|Generate or refresh whitelist udev rules file / Genera o refresca lista blanca de dispositivos lista udev usb|
|`--delete`|Delete udev rules file contain white list usb devices / Elimina archivo udev que contiene lista blanca de dispositivos usb|
|`--trigger`|Trigger event on insertion or removal / Dispara el evento de inserción o remoción|
|`--edit`|Edit udev rules file manually / Edita manualmente las reglas udev|
|`--help`|Show accepted options / Mostrar las opciones aceptadas|

### Data Sheet (For Windows)

| File | OS | Size |
| :---: | :---: | :---: |
| [blackusb.exe (.zip)](https://raw.githubusercontent.com/maravento/vault/master/blackusb/win/blackusb.zip) | Windows 10/11 x86 x64 | 4,3 MB |

## HOW TO USE

---

### Linux installation

```bash
# Download
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python3 gitfolder.py https://github.com/maravento/vault/blackusb

# Install
cd blackusb/linux
sudo chmod +x blackusb.sh
sudo bash blackusb.sh
```

### How To Use (For Linux)

Example:

`blackusb.sh --show`

```bash
sudo /path_to/blackusb.sh --show
 0 Name=xHCI Host Controller, Vendor=1d6b, Product=0003, Serial=0022:00:14.0
 1 Vendor=8087, Product=07dc
 2 Name=USB2.0-CRW, Vendor=0bda, Product=0129, Serial=20100001396000000
 3 Name=Integrated_Webcam_HD, Vendor=0c45, Product=6710
 4 Name=HID-compliant mouse, Vendor=046d, Product=c530
 5 Name=xHCI Host Controller, Vendor=1d6b, Product=0002, Serial=0022:00:14.0
```

### How To Use (For Windows)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>BlackUSB.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>BlackUSB.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

> This is requested because this project uses batch scripts packaged into a .exe, and antivirus software may flag this as a false positive. If in doubt, you can unzip the .exe and audit the scripts, run the packages manually, or choose not to use this project.
>
> Esto se solicita porque este proyecto usa scripts batch empaquetados en un .exe, y los antivirus pueden detectarlo como falso positivo. Si tiene dudas, puede descomprimir el .exe y auditar los scripts, ejecutar los paquetes manualmente, o no usar este proyecto.

## HOW IT WORKS

---

### Linux device control

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     It is a bash script that generates a white list of usb/hid devices and blocks any other unauthorized insertion of unknown devices, using udev rules.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Es un bash script que genera una lista blanca de dispositivos usb/hid y bloquea cualquier otra inserción no autorizada de dispositivos desconocidos, usando reglas udev.
    </td>
  </tr>
</table>



#### Paranoic Mode

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     It adds system shutdown when an unauthorized USB device is inserted. To enable it, uncomment <code>poweroff</code> in <code>commands_list</code>. The default command list contains only <code>sync</code>; it does not lock the session.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Añade el apagado del sistema al insertar un dispositivo USB no autorizado. Para activarlo, descomente <code>poweroff</code> en <code>commands_list</code>. La lista predeterminada contiene únicamente <code>sync</code>; no bloquea la sesión. 
    </td>
  </tr>
</table>

`'poweroff'`

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <code>'sync'</code> runs by default on an unknown device, before any other command in the list. <code>'poweroff'</code> can be added alongside it, not only as a replacement.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <code>'sync'</code> se ejecuta por defecto ante un dispositivo desconocido, antes de cualquier otro comando de la lista. <code>'poweroff'</code> puede agregarse junto a él, no solo como reemplazo.
    </td>
  </tr>
</table>

#### Demo Mode

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Logs an unknown device without running the commands in <code>commands_list</code>. Set <code>demo='yes'</code> to enable this mode. The generated udev rule still denies unauthorized USB devices with <code>ATTR{authorized}="0"</code>; demo mode does not disable that blocking.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Registra un dispositivo desconocido sin ejecutar los comandos de <code>commands_list</code>. Defina <code>demo='yes'</code> para activar este modo. La regla udev generada sigue rechazando dispositivos USB no autorizados con <code>ATTR{authorized}="0"</code>; el modo demo no desactiva ese bloqueo.
    </td>
  </tr>
</table>

#### Logs

`/var/log/blackusb.log`

Example (blocked and whitelisted devices are both logged, each entry preceded by a divider line):

```bash
──────────────────────────────────────────
2026-07-22 12:34:10 [BLACKLIST] Unknown Device Blocked: SUBSYSTEM=="usb", ATTR{idVendor}=="0781", ATTR{idProduct}=="5567", ATTR{serial}=="4C530799910104103543"
Cruzer Blade
──────────────────────────────────────────
2026-07-22 12:35:02 [WHITELIST] Allowed Device Connected: Vendor=0781, Product=5567, Name=Cruzer Blade
```

#### Fork

[usbkill](https://github.com/hephaest0s/usbkill), [usbdeath](https://github.com/trpt/usbdeath)

### Windows device control

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Tool to block unauthorized devices USB, HID, HDC, Bluetooth, IEEE, SmartCardReader, PCMCIA, Printers, SCSI, RAID, etc. Cleans previous device installations, rescans those connected and blocks new ones.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Herramienta para bloquear dispositivos no autorizados USB, HID, HDC, Bluetooth, IEEE, SmartCardReader, PCMCIA, Printers, SCSI, RAID, etc. Limpia instalaciones previas de dispositivos, reescanea los conectados y bloquea los nuevos.
    </td>
  </tr>
</table>

#### Important Before Use

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/blackusb/img/blackusb.png">
</div>

| Description | Descripción |
|---|---|
| - Do not press **BLOCK** button twice in a row or it will block all USB/HID devices. | - No pulse el botón **BLOCK** dos veces seguidas, o bloqueará todos los dispositivos USB/HID. |
| - If you have defined <a href="https://en.wikipedia.org/wiki/Group_Policy" target="_blank">GPO policies</a> on your system, they will be rewritten. Make a GPO backup before using BlackUSB. | - Si tiene establecidas <a href="https://en.wikipedia.org/wiki/Group_Policy" target="_blank">GPO policies</a> en su sistema, serán reescritas. Haga backup GPO antes de usar BlackUSB. |
| - To add a new USB/HID device to your whitelist (excluded from blocking) you must press the RESTORE button to remove the restrictions, then connect the new device and finally press BLOCK button. | - Para incorporar un nuevo dispositivo USB/HID a su lista blanca (excluidos de bloqueo) debe pulsar el botón RESTORE para eliminar las restricciones, luego conectar el nuevo dispositivo y finalmente pulsar el botón BLOCK. |
| - After executing the BLOCK option, the **whitelist.txt** report file, which contains the white list of USB/HID devices excluded from the lock, will be displayed on your desktop. This list will be deleted when using the RESTORE option. | - Despues de ejecutar la opción BLOCK, aparecerá en su escritorio el archivo de reporte **whitelist.txt**, que contiene la lista blanca de dispositivos USB/HID excluidos del bloqueo. Esta lista será eliminada al utilizar la opción RESTORE. |

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/blackusb/img/restrictions.jpg">
</div>

#### Packages and tools

- [74cz](http://74.cz/es/make-sfx/index.php)
- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [Resource Turner](http://www.restuner.com/)
- [Robust File Copy](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [robvanderwoude](http://www.robvanderwoude.com/)
- [USBOblivion](https://sourceforge.net/projects/usboblivion/)
- [Windows SDK - Devcon32/64](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

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
