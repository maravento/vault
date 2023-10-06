# [Dextroyer](https://www.maravento.com/p/dxt.html)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

Dextroyer (dxt) is an experimental package of security scripts for Windows. Contains highly destructive tools, classified as malware by some antivirus and security solutions ([VirusTotal report](https://www.virustotal.com/en/file/63c60e798a5738e10cb6fda1975c360d9889b4c437c2c04bd20ec967926c9b7e/analysis/1551278322/)), and can harm your system if used incorrectly. Therefore, use it at your own risk.

Dextroyer (dxt) es un paquete experimental de scripts de seguridad para Windows. Contiene herramientas altamente destructivas, clasificadas como malware por algunos antivirus y soluciones de seguridad  ([VirusTotal report](https://www.virustotal.com/es/file/63c60e798a5738e10cb6fda1975c360d9889b4c437c2c04bd20ec967926c9b7e/analysis/1551278322/)), y pueden dañar su sistema si se usan incorrectamente. Por tanto, úselo bajo su propio riesgo.

![Dextroyer](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/dextroyer.png)

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/dextroyer"
```

## DATA SHEET

---

|Download|OS|Size|Unzip Password|
| :---: | :---: | :---: | :---: |
|[Dextroyer.exe (.zip)](https://github.com/maravento/vault/raw/master/dextroyer/Dextroyer.zip)|Windows 7/8/10 x86 x64|13.4 MB|dextroyer|

## HOW TO USE

---

Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip Dextroyer.exe (.zip) to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen

Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima Dextroyer.exe (.zip) en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla

### IMPORTANT BEFORE USE

Some malwares ([Neshta](https://www.virustotal.com/es/file/c5af1e0383d10d5405ac7c8dd7332816a5635040c18333c9d191683743d41491/analysis/1396203101/), [Ground](https://www.virustotal.com/#/file/89c1fe36715d9821145edd86b67d4f1a2ec2b81c6b5c1aa03b88e7e76d760996/detection), etc.), prevent the execution of Dextroyer with privileges, so if double clicking on Dextroyer does not execute or leaves any message related to the ".exe", then click with the right mouse button on Dextroyer and select "Run as Administrator".

Algunos malwares ([Neshta](https://www.virustotal.com/es/file/c5af1e0383d10d5405ac7c8dd7332816a5635040c18333c9d191683743d41491/analysis/1396203101/), [Ground](https://www.virustotal.com/#/file/89c1fe36715d9821145edd86b67d4f1a2ec2b81c6b5c1aa03b88e7e76d760996/detection), etc.) impiden la ejecución de Dextroyer con privilegios, por tanto si al hacer doble clic sobre Dextroyer no se ejecuta o sale algún mensaje relacionado con el ".exe", entonces haga clic con el botón derecho del mouse sobre Dextroyer y seleccione "Ejecutar como Administrador".

## TOOLS INCLUDED

---

### CLEANERS

#### Clean USB

The Clean USB tool is to exclusively remove malware from USB mass storage devices (USB flash drives, USB external storage drives, SD Cards, etc.), however, if you have stored software or executable files (.bat, .bin, .com, .cmd, .db, .exe, .vbs, dll, etc) and / or files encrypted by ransomware, Dextroyer will remove them. We recommend running the USB Backup or USB Sync tools (in the Backup Tools menu) before performing any cleaning operations (See [Most common file types used by Malware](https://www.virustotal.com/en/statistics/)). Make sure that the Windows PC where you are going to carry out the disinfection of the USB is not contaminated with malware or create a disinfection-infection loop, so it is recommended to run "Clean PC" before "Clean USB".

La herramienta Clean USB es para eliminar exclusivamente malware de dispositivos de almacenamiento masivo USB (memorias USB -pendrives-, discos de almacenamiento externos USB, SD Cards, etc), sin embargo, si tiene almacenado software o archivos ejecutables (.bat, .bin, .com, .cmd, .db, .exe, .vbs, dll, etc) y/o archivos cifrados por ransomware, Dextroyer los eliminará. Recomendamos ejecutar las herramientas USB Backup o USB Sync (en menú Backup Tools) antes de realizar cualquier operación de limpieza (Vea [Tipos de archivos más comunes utilizados por Malware](https://www.virustotal.com/en/statistics/)). Asegúrese que el Windows PC donde va a realizar la desinfección de la USB no esté contaminado de malware o creará un bucle de desinfección-infección, por lo que se recomienda  ejecutar "Clean PC" antes de "Clean USB"

![CleanUSB](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/cleanusb.png "Clean USB")

#### Clean PC

The "Clean PC" tool is used to clean the malware of your PC and to execute it press the "Clean PC" button and the cleaning will begin. When finished, it will restart your PC

La herramienta "Clean PC" se utiliza para limpiar el malware de su PC y para ejecutarla pulse el botón "Clean PC" y comenzará la limpieza. Al finalizar reiniciará su PC

![CleanPC](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/cleanpc.png "Clean PC")

### PC TOOLS

#### Autorun Killer

Before performing any cleaning procedure, it is recommended to deactivate the autorun of units (autorun) on your PC with the Autorun Killer tool (in the System Tools menu). After disabling it, restart the PC to take the changes.

Antes de realizar cualquier procedimiento de limpieza, se recomienda desactivar el autoarranque de unidades (autorun) en su PC. Puede hacerlo manualmente o con la herramienta Autorun Killer (en el menú System Tools). Después de desactivarlo, reinicie el PC para que tome los cambios

<img src="https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/autorun1.png" width="300" hspace="2"/> <img src="https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/autorun2.png" width="280" hspace="2"/> <img src="https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/autorun3.png" width="200" hspace="2"/>

#### SysRestore

If after running Clean PC, in "Normal Mode" or "Safe Mode", you do not get the expected results, it is possible that the system files of your Windows are compromised. If this is the case, run the SysRestore tool (in the System Tools menu) in "Safe Mode". Note that after running SysRestore you must run the Autorun Killer tool again to deactivate the autostart of units

Si después de ejecutar Clean PC, en "Modo Normal" o "Modo Seguro", no obtiene los resultados esperados, es posible que los archivos de sistema de su Windows estén comprometidos. Si es el caso, ejecute la herramienta SysRestore (en el menú System Tools) en "Modo Seguro". Tenga en cuenta que después de ejecutar SysRestore deberá ejecutar nuevamente la herramienta Autorun Killer para desactivar el autoarranque de unidades

![SysRestore](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/sysrestore.png "SysRestore")

#### SafeBoot

You can start in "Safe Mode" manually (for Win7 start the PC by pressing the F8 key and higher versions, press the shift key (Shift) and click on the reset button) or you can do it with the SafeBoot tool (in the System Tools menu). To restart in "Safe Mode", press the "Safe Mode" button and to return to the normal start, press the "Normal Mode" button

Puede iniciar en "Modo Seguro" manualmente (para Win7 iniciar el PC presionando la tecla "F8" y versiones superiores, pulsar la tecla mayúscula "Shift" y hacer clic sobre el botón de reinicio) o puede hacerlo con la herramienta SafeBoot (en el menú System Tools).  Para reiniciar en "Modo seguro", presione el botón "Safe Mode" y para regresar al inicio normal, presione el botón "Normal Mode"

![SafeBoot](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/safeboot.png "SafeBoot")

#### Fix Print

Some malware blocks the print queue and the icons of the installed printers disappear. This tool repairs the print queue

Algunos malware bloquean la cola de impresión y desaparecen los íconos de las impresoras instaladas. Esta herramienta repara la cola de impresión

![FixPrint](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/fixprint.png "FixPrint")

#### Regedit Back

Make a backup of the Windows Registry into homedrive (e.g  c:\Backup\RegBackup_2016.07.05-12.53.22.reg)

Realiza un backup del Registro de Windows en el disco local (ej. c:\Backup\RegBackup_2016.07.05-12.53.22.reg)

![Regedit Backup](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/regeditback.png "Regedit Backup")

### USB TOOLS

#### BlackUSB

Tool to block unauthorized devices USB, HID, HDC, Bluetooth, IEEE, SmartCardReader, PCMCIA, Printers, SCSI, RAID, etc. Cleans previous device installations, rescans those connected and blocks new ones

Herramienta para bloquear dispositivos no autorizados USB, HID, HDC, Bluetooth, IEEE, SmartCardReader, PCMCIA, Printers, SCSI, RAID, etc. Limpia instalaciones previas de dispositivos, reescanea los conectados y bloquea los nuevos

![BlackUSB](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/blackusb.png "BlackUSB")

##### ⚠️ WARNING: BEFORE YOU CONTINUE

- Do not press **BLOCK** button twice in a row or it will block all USB/HID devices. / No pulse el botón **BLOCK**, dos veces seguidas, o bloqueará todos los dispositivos USB/HID
- If you have defined [GPO policies](https://en.wikipedia.org/wiki/Group_Policy) on your system, they will be rewritten. Make a GPO backup before using BlackUSB / Si tiene establecidas [políticas GPO](https://es.wikipedia.org/wiki/Directiva_de_Grupo) en su sistema, serán reescritas. Haga backup GPO antes de usar BlackUSB
- To add a new USB/HID device to your whitelist (excluded from blocking) you must press the RESTORE button to remove the restrictions, then connect the new device and finally press BLOCK button / Para incorporar un nuevo dispositivo USB/HID a su lista blanca (excluidos de bloqueo) debe pulsar el botón RESTORE para eliminar las restricciones, luego conectar el nuevo dispositivo y finalmente pulsar el botón BLOCK
- After executing the BLOCK option, the **whitelist.txt** report file, which contains the white list of USB/HID devices excluded from the lock, will be displayed on your desktop. This list will be deleted when using the RESTORE option / Despues de ejecutar la opción BLOCK, aparecerá en su escritorio el archivo de reporte **whitelist.txt**, que contiene la lista blanca de dispositivos USB/HID excluidos del bloqueo. Esta lista será eliminada al utilizar la opción RESTORE
- For more information visit [BlackUSB](https://github.com/maravento/vault/tree/master/blackusb) / Para mayor información visite [BlackUSB](https://github.com/maravento/vault/tree/master/blackusb)

#### USB Ports Control

Disable and enable the USB ports on your PC for mass storage devices. Does not affect web, keyboards, mice, printers, cameras etc

Deshabilita y Habilita los puertos usb de su PC para dispositivos de almacenamiento masivo. No afecta cámaras web, teclados, mouse, impresoras, etc

![USB Ports Control](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/usbportcontrol.png)

#### USB Write Tool

Enables and disables read or write USB devices

Deshabilita y Habilita la lectura o escritura de dispositivos usb

![USB Write Tool](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/usbwritecontrol.png "USB Write Tool")

#### USB Sync

Synchronize, in mirror mode, data from a USB device to the USBsync folder (e.g. c:\USBsync) and vice versa, with the options BACKUP and RESTORE, therefore the changes you make in your data, after executing the options of migration BACKUP or RESTORE, will be eliminated. If you do not execute any option, the window will close in 10 seconds.

Sincroniza, en modo espejo, los datos de un dispositivo USB a la carpeta USBsync (ej. c:\USBsync) y viceversa, con las opciones BACKUP y RESTORE, por tanto los cambios que realice en sus datos, después de ejecutadas las opciones de migración BACKUP o RESTORE, será eliminados. Si no ejecuta ninguna opción, la ventana cerrará en 10 segundos.

![USBSync](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/usbsync.png "USB Sync")

#### USB Backup

It makes a backup USB to your PC. It's stored in a folder into homedrive (e.g. c:\Backup\2016.04.21-20.13.55.)

Hace un backup de USB al PC. Se almacena en una carpeta en el disco local (ej. c:\Backup\2016.04.21-20.13.55.)

![USB Backup](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/backupusb.png "USB Backup")

#### USB Selector

Some tools (Clean USB, USB Sync, USB Backup, etc.) use a USB Selector. This selector identifies the letter of the unit where the USB storage device is connected. The selection must be confirmed, entering the letter manually (in uppercase or lowercase, without dots)

Algunas herramientas (Clean USB, USB Sync, USB Backup, etc) utilizan un Selector de USB. Este selector identifica la letra de la unidad donde está conectado el dispositivo de almacenamiento USB. Se debe confirmar la selección, introduciendo la letra manualmente (en mayúscula o minúscula, sin puntos)

![USB Selector](https://raw.githubusercontent.com/maravento/vault/master/dextroyer/img/usbselector.png "USB Selector")

##### ⚠️ WARNING: BEFORE YOU CONTINUE

In some cases, Windows does not correctly recognize some USB devices, so the USB selector will not identify the drive letter. To know how Windows detects your USB device, run the following command:

En algunos casos, Windows no reconoce correctamente algunos dispositivos USB, por tanto el selector USB no identificará la letra de unidad. Para saber cómo Windows detecta su dispositivo USB, ejecute el siguiente comando:

```bash
wmic logicaldisk get caption,description,name,drivetype,providername,volumename

0 = Unknown
1 = No Root Directory
2 = Removable Disk (Disco Extraíble)
3 = Local Fixed Disk (Disco Fijo Local)
4 = Network Drive
5 = Compact Disc
6 = RAM Disk
```

If appears as "Removable Disk", Windows detected it correctly and the USB selector will also detect it. But if it appears as "Local Fixed Disk", Windows detected it as a local hard disk and the USB selector will not detect it. For more information press [HERE](https://answers.microsoft.com/es-es/windows/forum/windows_7-hardware/por-qu%C3%A9-mi-pc-reconoce-mi-disco-duro-externo/c11a0cb2-5ba0-41b1-8d55-bafd21f09542?auth=1)

Si aparece como "Disco Extraíble", Windows lo detectó correctamente y el selector USB también lo hará. Pero si aparece como "Disco Fijo Local", Windows lo detectó como un disco duro local y el selector USB no lo detectará. Para mayor información pulse [AQUI](https://answers.microsoft.com/es-es/windows/forum/windows_7-hardware/por-qu%C3%A9-mi-pc-reconoce-mi-disco-duro-externo/c11a0cb2-5ba0-41b1-8d55-bafd21f09542?auth=1)

## COMPATIBILITY

---

- Some tools included in Dextroyer may not work properly in VMs, USB devices with non-traditional formats, multi-reading units / Algunas herramientas incluidas de Dextroyer pueden no funcionar correctamente en VMs, dispositivos usb con formatos no-tradicionales, unidades multilectoras
- On USB devices with NTFS partitions, Dextroyer not have access to "System Volume Information" folder and "$RECYCLE.BIN" (Not applicable for FAT/FAT32/ExFAT) / En dispositivos USB con particiones NTFS, Dextroyer no tendrá acceso a carpetas "System Volume Information" y "$RECYCLE.BIN" (No aplica para FAT/FAT32/ExFAT)
- Dextroyer can cause irreparable damage if it is executed in an operating system different from the compatible ones (Win 7/8/10 x86 x64) / Dextroyer puede causar daños irreparables si es ejecutado en un sistema operativo diferente a los compatibles (Win 7/8/10 x86 x64)
- The USB Sync and USB Backup tools use [Robust File Copy](https://en.wikipedia.org/wiki/Robocopy), which has some limitations and may not achieve the desired results. Use them at your own risk / Las herramientas USB Sync y USB Backup utilizan [Robust File Copy](https://es.wikipedia.org/wiki/Robocopy), el cual tiene algunas limitaciones y puede no obtener los resultados deseados. Úselas bajo su propio riesgo

## USED TOOLS

---

- [Autoplay Indigo Rose](https://www.indigorose.com/autoplay-media-studio/)
- [Helge Klein SetACL](https://helgeklein.com/download/)
- [make-sfx 74cz](http://74.cz/es/make-sfx/index.php)
- [Ransomware Database](https://docs.google.com/spreadsheets/u/1/d/1TWS238xacAto-fLKh1n5uTsdijWdCEsGIM0Y0Hvmc5g/pubhtml#)
- [kinomakino ransomware_file_extensions](https://raw.githubusercontent.com/kinomakino/ransomware_file_extensions/master/extensions.csv)
- [Resource Hacker](http://www.angusj.com/resourcehacker/)
- [Rkill BleepingComputer](https://www.bleepingcomputer.com/download/rkill/)
- [Robust File Copy](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [SteelWerX](https://fstaal01.home.xs4all.nl/swreg-us.html)
- [TCC Jpsoft](https://jpsoft.com/products/tcc-cmd-prompt.html)
- [unzip mkssoftware](https://www.mkssoftware.com/docs/man1/unzip.1.asp)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
