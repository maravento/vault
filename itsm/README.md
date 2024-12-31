# [ITSM](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     ITSM (IT Service Management) is a structured approach to designing, implementing, managing and optimizing information technology services within an organization. Its main objective is to align IT services with business needs, improving operational efficiency and end-user experience.
     This package includes two open source web applications designed for ITSM: iTop and GLPI
    </td>
    <td width="50%">
     ITSM (Gestión de Servicios de TI) es un enfoque estructurado para diseñar, implementar, gestionar y optimizar los servicios de tecnología de la información dentro de una organización. Su objetivo principal es alinear los servicios de TI con las necesidades del negocio, mejorando la eficiencia operativa y la experiencia del usuario final.
     Este paquete incluye dos aplicaciones web de código abierto diseñadas para la ITSM: iTop y GLPI
    </td>
  </tr>
</table>

## iTop

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

## GLPI

<table width="100%">
  <tr>
    <td width="50%">
     <b>GLPI</b> (Gestionnaire Libre de Parc Informatique): This is a comprehensive ITSM solution that combines inventory management, help desk and IT asset management. It also includes advanced features for ticket, contract and project management, offering an intuitive and extensible interface through plugins.
    </td>
    <td width="50%">
     <b>GLPI</b> (Gestionnaire Libre de Parc Informatique): Es una solución integral de ITSM que combina la gestión de inventarios, el soporte técnico y la administración de activos de TI. Además, incluye funcionalidades avanzadas para la gestión de tickets, contratos y proyectos, ofreciendo una interfaz intuitiva y extensible mediante plugins.
    </td>
  </tr>
</table>

## DATA SHEET

---

|File|OS|Size|
| :---: | :---: | :---: |
|[itsm.exe (.zip)](https://mega.nz/file/GAlSADxL#DIzfjWyEMyL4bLvpHrJ8kh1QZsMoiBDx00e8hkRcYvk)|Windows 10/11 x64|104 MB|

## Supported Versions

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

### Web-based ITSM solutions

- [glpi-10.0.17](https://glpi-project.org/downloads/)
- [iTop v3.2.0-2-14758](https://sourceforge.net/projects/itop/files/itop/)

### Stacks

- [WampServer v3.3.7 x64](https://wampserver.aviatechno.net/)
- [XAMPP v8.2.12-0-VS16 x64](https://sourceforge.net/projects/xampp/files/)
- [Uniform Server v15.0.2 ZeroXV (UZero)](https://sourceforge.net/projects/miniserver/files/)

### Dependencies (Included)

- [Microsoft Visual C++ Redistributable Runtimes](https://github.com/abbodi1406/vcredist)
- [graphviz x64](https://graphviz.org/download/)
- [apcu v8.x x64 ts](https://github.com/krakjoe/apcu)

### Hardware & Software Requirements

- [For GLPI](https://glpi-install.readthedocs.io/en/latest/prerequisites.html)
- [For iTop](https://www.itophub.io/wiki/page?id=latest:install:requirements)

## HOW TO USE

---

<table width="100%">
  <tr>
    <td width="50%">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>itsm.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td width="50%">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>itsm.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
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

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-ini.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     Select Web-based ITSM and press OK.
    </td>
    <td width="50%">
     Seleccione ITSM basado en web y presione OK.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-select.png)](https://www.maravento.com)

### STACK SELECTOR

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-stack.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     Select the Stack you have installed (WampServer, Xampp, UniServerZ) and press OK.
    </td>
    <td width="50%">
     Seleccione el Stack que tenga instalado (WampServer, Xampp, UniServerZ) y presione OK.
    </td>
  </tr>
</table>

#### Paths Accepted by ITSM Installer

|WampServer|Xampp|UniformServerZ|
| :---: | :---: | :---: |
|%HOMEDRIVE%\wamp64|%HOMEDRIVE%\xampp|%HOMEDRIVE%\UniServerZ|

### INSTALLATION

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-run.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     It will start installing your choice of itsm, with its dependencies and configurations and when finished the following message will appear:
    </td>
    <td width="50%">
     Iniciará la instalación de su selección de itsm, con sus dependencias y configuraciones y al terminar saldrá el siguiente mensaje:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-complete.png)](https://www.maravento.com)

#### Additional Installation Messages

| Message | Description | Descripción |
|---------|-------------|-------------|
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-canceled.png) | You have pressed the "Cancel" button or an error has occurred during installation. | Ha pulsado el botón "Cancelar" o ha ocurrido un error durante la instalación. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-nostack.png) | The installer did not detect any installed stacks. | El instalador no detectó stacks instalados. |
| ![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-so.png) | You are using the installer on an Incompatible Operating System. | Está usando el instalador en un Sistema Operativo Incompatible. |

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

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-icons.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     During the installation, several shortcuts are created on your PC's desktop. For iTop 2 and GLPI 1, to run iTop for the first time, double-click on <code>iTop Wizard (.url)</code> which will take you to the iTop setup URL.<br>
     Once iTop setup is complete, close your browser. From now on, to access iTop, you will need to use the second shortcut on your desktop called <code>iTop (.url)</code> which will take you to the login URL, where you will enter the credentials you chose in the iTop setup.<br>
     For GLPI, there is only one shortcut <code>GLPI (.url)</code>, which you will use both to launch it for the first time, and to log in after installation.<br>
     <strong>Important:</strong><br>
     If double-clicking the iTop or GLPI shortcut on your desktop does not open the URL in your browser, close your browser completely and try again.
    </td>
    <td width="50%">
     Durante la instalación se crean varios accesos directos en el escritorio de su PC. Para iTop 2 y GLPI 1. Para ejecutar iTop por primera vez haga doblé clic en <code>iTop Wizard (.url)</code> que lo llevará a la URL de la configuración de iTop.<br>
     Una vez concluida la configuración de iTop, cierre su navegador. Y a partir de ahora, para acceder a iTop, deberá usar el segundo acceso directo de su escritorio llamado <code>iTop (.url)</code> que lo llevará a la URL de ingreso, en la cual introducirá las credenciales que eligió en la configuración de iTop.<br>
     Para GLPI solo hay un acceso directo <code>GLPI (.url)</code>, el cual usará tanto para iniciar por primera vez, como para ingresar después de instalado.<br>
     <strong>Importante</strong>:<br>
     Si al hacer doble clic sobre el acceso directo de iTop o GLPI en su escritorio, no abre la URL en el navegador, cierre el navegador completamente e inténtelo nuevamente.
    </td>
  </tr>
</table>

### WIZARD

<table width="100%">
  <tr>
    <td width="50%">
     You can check the iTop and GLPI settings in the shortcuts on your PC desktop named <code>iTop-Wizard.pdf</code> and <code>GLPI-Wizard.pdf</code>.
    </td>
    <td width="50%">
     Puede consultar las configuraciones de iTop y GLPI en los accesos directos del escritorio de su PC llamados <code>iTop-Wizard.pdf</code> y <code>GLPI-Wizard.pdf</code>.
    </td>
  </tr>
</table>

[GLPI-Wizard.pdf](https://raw.githubusercontent.com/maravento/vault/master/itsm/wizard/GLPI-Wizard.pdf)

[iTop-Wizard.pdf](https://raw.githubusercontent.com/maravento/vault/master/itsm/wizard/iTop-Wizard.pdf)

#### Important About iTop and GLPI

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

<table width="100%">
  <tr>
    <td width="50%">
     If you have problems accessing the iTop or GLPI startup or configuration URL, check your browser's proxy settings or run the following command with administrative privileges:
    </td>
    <td width="50%">
     Si tiene problemas al acceder a la URL de inicio o configuración de iTop o GLPI, revise la configuración de proxy de su navegador o ejecute el siguiente comando con privilegios administrativos:
    </td>
  </tr>
</table>

`netsh winhttp import proxy source=ie`

### TELEMETRY

<table width="100%">
  <tr>
    <td width="50%">
     ITSM sends information to the developer, only for the purpose of verifying that the installation has been completed successfully. This information is used exclusively for statistical purposes and to improve the installer, without collecting personal data or compromising user privacy. Example:
    </td>
    <td width="50%">
     ITSM envía información al desarrollador, únicamente con el propósito de verificar que la instalación se haya completado de manera exitosa. Esta información se utiliza exclusivamente para fines estadísticos y de mejora del instalador, sin recopilar datos personales ni comprometer la privacidad del usuario. Ejemplo:
    </td>
  </tr>
</table>

```bash
Package Installation
Hostname=DESKTOP-AJ4JSC8
User=Usuario
Date=mié. 13/11/2024 Time= 6:44:17,39
Status=Installed
Package: ITSM
```

## PACKAGES AND TOOLS

---

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [ACPU](https://github.com/krakjoe/apcu)
- [Checksum Control](https://sourceforge.net/projects/checksumcontrol/)
- [curl for Windows](https://curl.se/windows/)
- [Find & Replace Tool](https://findandreplace.io/)
- [GLPI](https://glpi-project.org/downloads/)
- [graphviz](https://graphviz.org/download/)
- [iTop](https://sourceforge.net/projects/itop/files/itop/)
- [Quick Batch File Compiler](https://www.abyssmedia.com/quickbfc/)
- [Resource Turner](http://www.restuner.com/)
- [stahlworks unzip and gzip](http://stahlworks.com/dev/index.php?tool=zipunzip)
- [tartool](https://github.com/senthilrajasek/tartool)
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
     MMaravento Studio has no relationship with the developers of iTop or GLPI. We also do not use them, do not promote them, and do not provide support. Maravento Studio only provides support for the ITSM installer, which is an open source project, sponsored by <a href="https://co.linkedin.com/in/lancord" target="_blank">Uniopos SAS</a>. Only the sponsor of this installer may use it for commercial purposes.
    </td>
    <td width="50%">
     Maravento Studio no tiene ninguna relación con los desarrolladores de iTop o GLPI. Tampoco los usamos, no los promocionamos y no brindamos soporte. Maravento Studio solo brinda soporte al instalador ITSM, que es un proyecto de código abierto, patrocinado por <a href="https://co.linkedin.com/in/lancord" target="_blank">Uniopos SAS</a>. Solo el patrocinador de este instalador, podrá usarlo con fines comerciales.
    </td>
  </tr>
</table>
