# [NetScan](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
    NetScan is a portable tool for network scanning using Nmap on Windows, with an alternative GUI frontend based on Zenity. It deploys Nmap with all its dependencies silently and unattended, and allows executing different scanning levels while generating HTML reports.
    </td>
    <td style="width: 50%; white-space: nowrap;">
    NetScan es una herramienta portable para realizar escaneos de red usando Nmap en Windows, con un frontend GUI alternativo basado en Zenity. Despliega Nmap con todas sus dependencias de forma silenciosa y desatendida, y permite ejecutar diferentes niveles de escaneo generando reportes en HTML.
    </td>
  </tr>
</table>

## NETSCAN ON WINDOWS

---

### Data Sheet

| File |  OS  | Size |
| :--: | :--: | :--: |
| [netscan.exe (.zip)](https://mega.nz/file/2Z8ShAwD#02jFrwjB9qM55kIWZOf525s8wKGYLGDpbLd1D6O4dKc) | Windows 10/11 x64 | 78,2 MB |

### Package Contents

- [nmap](https://nmap.org/download#windows)
- [npcap](https://nmap.org/download#windows)
- [libxslt (xsltproc)](https://www.zlatkovic.com/pub/libxml/)
- [Microsoft Visual C++ Runtimes](https://gitlab.com/stdout12/vcredist/-/releases)

### How to Use

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>netscan.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>netscan.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

### ⚠️ WARNING

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <strong>Before continuing:</strong> If you have Nmap or Npcap already installed on your PC, it is recommended to uninstall them before using this tool to avoid version conflicts.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <strong>Antes de continuar:</strong> Si tiene Nmap o Npcap instalado en su PC, se recomienda desinstalarlo antes de usar esta herramienta para evitar conflictos de versiones.
    </td>
  </tr>
</table>

### Start

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Upon startup, it will prompt you to connect to your data network before continuing. Press OK to continue or Cancel to abort.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Al iniciar, le pedirá que se conecte a su red de datos antes de continuar. Presione OK para continuar o Cancel para abortar.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-welcome.png)](https://www.maravento.com)

### Scan Selector

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Select the scan mode. Press OK to continue or Cancel to abort.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Seleccione el modo de escaneo. Presione OK para continuar o Cancel para abortar.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-selector.png)](https://www.maravento.com)

### Scanning Modes

| Scan Mode | Nmap Options | Description | Descripción |
| --------- | ------------ | ----------- | ----------- |
| 1. LAN Scan | `-sS -T4 -F -sV` | Fast network scan with service detection | Escaneo rápido de red con detección de servicios |
| 2. Advanced LAN Scan | `-sS -T4 -F -sV -sC --max-retries 3 --host-timeout 5m` | Deep scanning with scripts | Escaneo profundo con scripts |
| 3. IP Scan | `-sS -T4 -F -sV --version-intensity 8 -sC -O --script vuln --traceroute -oA scan_ip --max-retries 3 --host-timeout 10m` | Comprehensive single-host audit with OS detection, vulnerability scanning, and detailed service enumeration | Auditoría completa de un host con detección de OS, escaneo de vulnerabilidades y enumeración detallada de servicios |

### Installation Messages

| Message | Description | Descripción |
| ------- | ----------- | ----------- |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-extract.png) | Extracting NetScan content during execution. | Extrayendo contenido de NetScan durante la ejecución. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-visual.png) | Installing MS Visual C++ Runtimes. | Instalando MS Visual C++ Runtimes |

### Scan Messages

| Message | Description | Descripción |
| ------- | ----------- | ----------- |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-ipscan.png) | Option 3: Scanning for a specific IPv4. Ranges are not accepted. | Opción 3: Escaneo de IPv4 específica. No acepta rangos. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-invalidip.png) | Invalid IPv4 address entered. | Introdujo una dirección IPv4 inválida. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-scanning.png) | Scanning IP address or network. | Escaneando dirección IP o red. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-advanced.png) | Intense scanning. | Escaneo intenso. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-end.png) | Scan completed successfully. | El escaneo finalizó exitosamente. |

### Error Messages

| Message | Description | Descripción |
|-------- | ----------- | ----------- |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-cancel.png) | You pressed the "Cancel" button or an error occurred during installation. | Presionó el botón "Cancelar" u ocurrió un error durante la instalación. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-errordependencies.png) | An error occurred during dependency installation. | Ocurrió un error durante la instalación de las dependencias. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-nointernet.png) | No internet connectivity detected. | No se detectó conectividad a internet. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-osincompatible.png) | You are using the installer on an incompatible operating system. | Está usando el instalador en un sistema operativo incompatible. |

### Npcap

![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-npcap.png)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     NetScan requires Npcap, included in its free version. This dependency is not installed automatically, as it is not an OEM version and does not support silent installation (<code>/S</code> option). You will need to manually complete the Npcap installation when prompted by the installer. Npcap's free version allows use on up to 5 machines. For more information, see <a href="https://npcap.com/oem/">Npcap OEM</a>.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     NetScan requiere Npcap, incluido en su versión gratuita. La instalación de esta dependencia no es desatendida, ya que al no ser una versión OEM, no acepta instalación silenciosa (opción <code>/S</code>). Deberá completar manualmente la instalación de Npcap cuando el instalador la solicite. La versión gratuita de Npcap permite su uso en hasta 5 equipos. Para más información, consulte <a href="https://npcap.com/oem/">Npcap OEM</a>.
    </td>
  </tr>
</table>

### Report

![Image](https://raw.githubusercontent.com/maravento/vault/master/netscan/img/netscan-report.png)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     NetScan will save the scan reports to the <code>Desktop\Report</code> folder, depending on the scan type, and each file will include a timestamp (date and time the scan was executed).
    </td>
    <td style="width: 50%; white-space: nowrap;">
     NetScan guardará los reportes de escaneo en la carpeta <code>Desktop\Report</code>, según el tipo de escaneo, y cada archivo incluirá un timestamp (fecha y hora en que se ejecutó el escaneo).
    </td>
  </tr>
</table>

### Telemetry

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     NetScan sends information to the developer, only for the purpose of verifying that the installation has been completed successfully. This information is used exclusively for statistical purposes and to improve the installer, without collecting personal data or compromising user privacy. Example:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     NetScan envía información al desarrollador, únicamente con el propósito de verificar que la instalación se haya completado de manera exitosa. Esta información se utiliza exclusivamente para fines estadísticos y de mejora del instalador, sin recopilar datos personales ni comprometer la privacidad del usuario. Ejemplo:
    </td>
  </tr>
</table>

```bash
Package Installation
Hostname=DESKTOP-AJ4JSC8
User=User
Date=mié. 13/11/2024 Time= 6:44:17,39
Status=Installed
Package: NetScan
```

### Packages and Tools

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [curl for Windows](https://curl.se/windows/)
- [libxslt (xsltproc)](https://www.zlatkovic.com/pub/libxml/)
- [nmap](https://nmap.org/download#windows)
- [npcap](https://nmap.org/download#windows)
- [Quick Batch File Compiler](https://www.abyssmedia.com/quickbfc/)
- [RapidCRC Unicode](https://www.ov2.eu/programs/rapidcrc-unicode)
- [vcredist](https://gitlab.com/stdout12/vcredist/-/releases)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

## NETSCAN ON LINUX

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap; vertical-align: top; padding-right: 10px;">
      <p><strong>NetScan can run on Linux with the same scan modes:</strong></p>
      <p>
        1. <code>LAN Scan</code><br>
        2. <code>Advanced LAN Scan</code><br>
        3. <code>IP Scan</code>
      </p>
      <p>
        NetScan will save scan reports in the <code>/home/$USER/Report</code> folder,
        according to the scan type.<br> Each file will include a timestamp
        (date and time when the scan was executed).
      </p>
    </td>
    <td style="width: 50%; white-space: nowrap; vertical-align: top; padding-left: 10px;">
      <p><strong>NetScan puede ejecutarse en Linux con los mismos modos de escaneo:</strong></p>
      <p>
        1. <code>LAN Scan</code><br>
        2. <code>Advanced LAN Scan</code><br>
        3. <code>IP Scan</code>
      </p>
      <p>
        NetScan guardará los reportes de escaneo en la carpeta <code>/home/$USER/Report</code>,
        según el tipo de escaneo.<br> Cada archivo incluirá un timestamp
        (fecha y hora en que se ejecutó el escaneo).
      </p>
    </td>
  </tr>
</table>

```bash
wget -q https://raw.githubusercontent.com/maravento/vault/master/netscan/linux/netreport.sh -O netreport.sh
chmod +x netreport.sh
sudo ./netreport.sh
```

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
