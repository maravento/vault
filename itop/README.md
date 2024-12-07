# [iTop](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     <b>iTop</b> is an all-in-one, open-source ITSM platform designed to streamline IT operations. iTop offers a highly customizable, low-code Configuration Management Database (CMDB), along with advanced tools for handling requests, incidents, problems, changes, and service management. iTop is ITIL-compliant, making it ideal for organizations looking for standardized and scalable IT processes.
    </td>
    <td width="50%">
     <b>iTop</b> es una plataforma ITSM de código abierto todo en uno diseñada para optimizar las operaciones de TI. iTop ofrece una base de datos de gestión de configuración (CMDB) de código bajo y altamente personalizable, junto con herramientas avanzadas para gestionar solicitudes, incidentes, problemas, cambios y gestión de servicios. iTop es compatible con ITIL, lo que lo hace ideal para organizaciones que buscan procesos de TI estandarizados y escalables.
    </td>
  </tr>
</table>

## DATA SHEET

---

|File|OS|Size|
| :---: | :---: | :---: |
|[iTop.exe (.zip)](https://mega.nz/file/uMtgSBxD#Y4Q1G-8cFKksaVF5bRCE72UIDITno3U-CMeKXXmjRx4)|Windows 10/11 x64|69.6 MB|

### Supported Versions

<table width="100%">
  <tr>
    <td width="50%">
     These minimum versions or later are supported:
    </td>
    <td width="50%">
     Se admiten las siguientes versiones mínimas o posteriores:
    </td>
  </tr>
</table>

- [iTop v3.2.0-2-14758](https://sourceforge.net/projects/itop/files/itop/)
- [WampServer v3.3.5 x64](https://wampserver.aviatechno.net/)
- [XAMPP v8.2.12-0-VS16 x64](https://sourceforge.net/projects/xampp/files/)
- [Uniform Server v15.0.2 ZeroXV (UZero)](https://sourceforge.net/projects/miniserver/files/)

### Hardware & Software Requirements

<table width="100%">
  <tr>
    <td width="50%">
     Check the minimum requirements <a href="https://www.itophub.io/wiki/page?id=latest:install:requirements" target="_blank">HERE</a>.
    </td>
    <td width="50%">
     Verifique los requerimientos mínimos <a href="https://www.itophub.io/wiki/page?id=latest:install:requirements" target="_blank">AQUI</a>.
    </td>
  </tr>
</table>

## HOW TO USE

---

<table width="100%">
  <tr>
    <td width="50%">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>iTop.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td width="50%">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>iTop.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

### ⚠️ WARNING: STOP SERVICES

<table width="100%">
  <tr>
    <td width="50%">
     Stop Apache/MySQL services before proceeding.
    </td>
    <td width="50%">
     Detenga los servicios de Apache/MySQL, antes de proseguir.</td>
  </tr>
</table>

### START

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-ini.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     Press OK to begin. If you choose CANCEL, you will abort the process and the following window will appear:
    </td>
    <td width="50%">
     Pulse OK para comenzar. Si elije CANCEL, abortará el proceso y saldrá la siguiente ventana:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-cancel.png)](https://www.maravento.com)

### STACK SELECTOR

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-menu.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     Select the Stack you have installed (WampServer, Xampp, UniServerZ) and press OK. If you do not have any of these Stacks installed, you will get the following message:
    </td>
    <td width="50%">
     Seleccione el Stack que tenga instalado (WampServer, Xampp, UniServerZ) y presione OK. Si no tiene ninguno de estos Stack instalados, saldrá el siguiente mensaje:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-nostack.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     So before you proceed, make sure that the Stack of your choice is installed. Below are the paths accepted by the installer:
    </td>
    <td width="50%">
     Por tanto, antes de continuar, asegúrese de que el Stack de su elección esté instalado. A continuación, los paths aceptados por el instalador:
    </td>
  </tr>
</table>

- WampServer: %HOMEDRIVE%\wamp64
- Xampp: %HOMEDRIVE%\xampp
- UniformServerZ: %HOMEDRIVE%\UniServerZ

### INSTALLATION

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-run.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     The installation of iTop will start, with its dependencies and configurations, and when finished the following message will appear:
    </td>
    <td width="50%">
     Iniciará la instalación de iTop, con sus dependencias y configuraciones y al terminar saldrá el siguiente mensaje:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-complete.png)](https://www.maravento.com)

### ⚠️ WARNING: START SERVICES

 <table width="100%">
  <tr>
    <td width="50%">
     Start the Apache/MySQL services before proceeding.
    </td>
    <td width="50%">
     Inicie los servicios de Apache/MySQL, antes de proseguir.
    </td>
  </tr>
</table>

### DESKTOP SHORTCUT

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-icons.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     During the installation, two shortcuts are created on your PC's desktop. Double-click on <code>iTop Wizard (.url)</code> which will take you to the iTop setup URL. Once you have completed the iTop setup, close your browser. From now on, to access iTop, you will need to use the second shortcut on your desktop called <code>iTop (.url)</code> which will take you to the login URL, where you will enter the credentials you chose in the iTop setup.
    </td>
    <td width="50%">
     Durante la instalación se crean dos accesos directos en el escritorio de su PC. Haga doblé clic en <code>iTop Wizard (.url)</code> que lo llevará a la URL de la configuración de iTop. Una vez concluida la configuración de iTop, cierre su navegador. Y a partir de ahora, para acceder a iTop, deberá usar el segundo acceso directo de su escritorio llamado <code>iTop (.url)</code> que lo llevará a la URL de ingreso, en la cual introducirá las credenciales que eligió en la configuración de iTop.
    </td>
  </tr>
</table>

### WIZARD

<table width="100%">
  <tr>
    <td width="50%">
     To start the iTop setup, double-click the <code>iTop Wizard (.url)</code> icon and follow the instructions described in the PDF located in the wizard folder of this repository or on your PC's desktop:
    </td>
    <td width="50%">
     Para iniciar la configuración de iTop, haga doble clic en el ícono <code>iTop Wizard (.url)</code> y siga las instrucciones descritas en el PDF que se encuentra en la carpeta wizard de este repositorio o en el escritorio de su PC:
    </td>
  </tr>
</table>

[iTop-Wizard.pdf](https://raw.githubusercontent.com/maravento/vault/master/itop/wizard/iTop-Wizard.pdf)

### IMPORTANT BEFORE USE ITOP

<table width="100%">
  <tr>
    <td width="50%">
     - The default database is iTop with the format: <code>utf8mb4_unicode_ci</code>.
    </td>
    <td width="50%">
     - La base de datos por defecto es iTop con el formato: <code>utf8mb4_unicode_ci</code>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - This installer modifies the default values of <code>post_max_size=64M</code> for PHP and <code>max_allowed_packet=50M</code> for MySQL, across stacks. If the value of <code>post_max_size</code> is greater than <code>40M</code> and the value of <code>max_allowed_packet</code> is greater than <code>1M</code>, there will be no configuration changes.
    </td>
    <td width="50%">
     - Este instalador modifica los valores por defecto de <code>post_max_size=64M</code> para PHP y <code>max_allowed_packet=50M</code> para MySQL, en los diferentes Stacks. Si el valor de <code>post_max_size</code> es superior a <code>40M</code> y el valor de <code>max_allowed_packet</code> es superior a <code>1M</code>, no habrá cambios en la configuración.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - If you have any questions about your Stack parameters or during the configuration you get any conflicts or warning messages from iTop related to Apache/PHP/MySQL, for more information, please visit: <a href="http://localhost/info.php" target="_blank">http://localhost/info.php</a>.
    </td>
    <td width="50%">
     - Si tiene alguna duda sobre los parámetros de su Stack o durante la configuración se presenta algún conflicto o mensajes de advertencia de iTop, relacionados con Apache/PHP/MySQL, para obtener mayor información, ingrese a: <a href="http://localhost/info.php" target="_blank">http://localhost/info.php</a>.
    </td>
  </tr>
</table>

### CHANGING PORTS

<table width="100%">
  <tr>
    <td width="50%">
     If you decide to change the Apache/MySQL ports on your Stack, you will also need to change them in iTop. To do this, download the following script that will help you through the process:
    </td>
    <td width="50%">
     Si decide cambiar los puertos de Apache/MySQL en su Stack, también deberá cambiarlos en iTop. Para esto descargue el siguiente script que le ayudará en el proceso:
    </td>
  </tr>
</table>

[itopconf.bat](https://github.com/maravento/vault/blob/master/scripts/batch/itopconf.bat)

<table width="100%">
  <tr>
    <td width="50%">
     You will also need to change the URL of the <code>iTop.url</code> shortcut on your desktop. Example: Changing the Apache port from 80 to 8080:
    </td>
    <td width="50%">
     También deberá cambiar la URL del acceso directo <code>iTop.url</code> en su escritorio. Ejemplo: Cambio del puerto Apache, de 80 a 8080:
    </td>
  </tr>
</table>

`http://localhost/itop/web/pages/UI.php`

by:

`http://localhost:8080/itop/web/pages/UI.php`

### TELEMETRY

<table width="100%">
  <tr>
    <td width="50%">
     iTop sends information to the developer, only for the purpose of verifying that the installation has been completed successfully. This information is used exclusively for statistical purposes and to improve the installer, without collecting personal data or compromising user privacy. Example:
    </td>
    <td width="50%">
     iTop envía información al desarrollador, únicamente con el propósito de verificar que la instalación se haya completado de manera exitosa. Esta información se utiliza exclusivamente para fines estadísticos y de mejora del instalador, sin recopilar datos personales ni comprometer la privacidad del usuario. Ejemplo:
    </td>
  </tr>
</table>

```bash
Package Installation
Hostname=DESKTOP-AJ4JSC8
User=Usuario
Date=mié. 13/11/2024 Time= 6:44:17,39
Status=Installed
Package: iTop
```

## PACKAGES AND TOOLS

---

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [ACPU](https://github.com/krakjoe/apcu)
- [Checksum Control](https://sourceforge.net/projects/checksumcontrol/)
- [curl for Windows](https://curl.se/windows/)
- [graphviz](https://graphviz.org/download/)
- [iTop - IT Service Management & CMDB Files](https://sourceforge.net/projects/itop/files/itop/)
- [Quick Batch File Compiler](https://www.abyssmedia.com/quickbfc/)
- [Resource Turner](http://www.restuner.com/)
- [stahlworks ZipUnzip](http://stahlworks.com/dev/index.php?tool=zipunzip)
- [Uniform Server](https://sourceforge.net/projects/miniserver/files/)
- [vcredist](https://github.com/abbodi1406/vcredist)
- [WampServer](https://wampserver.aviatechno.net/)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)
- [XAMPP](https://sourceforge.net/projects/xampp/files/)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## NOTICE

---

<table width="100%">
  <tr>
    <td width="50%">
     Maravento Studio has no relationship with the developers of iTop. We also don't use iTop, we don't promote it, and we don't provide support. Maravento Studio only supports the iTop installer, which is an open source project, sponsored by <a href="https://co.linkedin.com/in/lancord)" target="_blank">Uniopos SAS</a>. Only the sponsor of this installer may use it for commercial purposes.
    </td>
    <td width="50%">
     Maravento Studio no tiene ninguna relación con los desarrolladores de iTop. Tampoco usamos iTop, no lo promocionamos y no brindamos soporte. Maravento Studio solo brinda soporte al instalador iTop, que es un proyecto de código abierto, patrocinado por <a href="https://co.linkedin.com/in/lancord)" target="_blank">Uniopos SAS</a>. Solo el patrocinador de este instalador, podrá usarlo con fines comerciales.
    </td>
  </tr>
</table>
