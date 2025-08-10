# [ITSM](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     ITSM (IT Service Management) is a structured approach to designing, implementing, managing and optimizing information technology services within an organization. Its main objective is to align IT services with business needs, improving operational efficiency and end-user experience.
     This package includes two open source web applications designed for ITSM: iTop and GLPI
    </td>
    <td style="width: 50%; white-space: nowrap;">
     ITSM (Gestión de Servicios de TI) es un enfoque estructurado para diseñar, implementar, gestionar y optimizar los servicios de tecnología de la información dentro de una organización. Su objetivo principal es alinear los servicios de TI con las necesidades del negocio, mejorando la eficiencia operativa y la experiencia del usuario final.
     Este paquete incluye dos aplicaciones web de código abierto diseñadas para la ITSM: iTop y GLPI
    </td>
  </tr>
</table>

## iTop

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>iTop</b> is an all-in-one, open-source ITSM platform designed to streamline IT operations. iTop offers a highly customizable, low-code Configuration Management Database (CMDB), along with advanced tools for handling requests, incidents, problems, changes, and service management. iTop is ITIL-compliant, making it ideal for organizations looking for standardized and scalable IT processes.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>iTop</b> es una plataforma ITSM de código abierto todo en uno diseñada para optimizar las operaciones de TI. iTop ofrece una base de datos de gestión de configuración (CMDB) de código bajo y altamente personalizable, junto con herramientas avanzadas para gestionar solicitudes, incidentes, problemas, cambios y gestión de servicios. iTop es compatible con ITIL, lo que lo hace ideal para organizaciones que buscan procesos de TI estandarizados y escalables.
    </td>
  </tr>
</table>

## GLPI

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>GLPI</b> (Gestionnaire Libre de Parc Informatique): This is a comprehensive ITSM solution that combines inventory management, help desk and IT asset management. It also includes advanced features for ticket, contract and project management, offering an intuitive and extensible interface through plugins.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>GLPI</b> (Gestionnaire Libre de Parc Informatique): Es una solución integral de ITSM que combina la gestión de inventarios, el soporte técnico y la administración de activos de TI. Además, incluye funcionalidades avanzadas para la gestión de tickets, contratos y proyectos, ofreciendo una interfaz intuitiva y extensible mediante plugins.
    </td>
  </tr>
</table>

## DATA SHEET

---

| File | OS | Size |
| :---: | :---: | :---: |
| [itsm.exe (.zip)](https://mega.nz/file/eZ0AEZaK#mNvOfJ0lklv_eITycEpnwhct-NLW3hUe5pZaEPwTGP4) | Windows 10/11 x64 | 127,1 MB |

## Supported Versions

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     These minimum versions or later are supported:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Se admiten las siguientes versiones mínimas o posteriores:
    </td>
  </tr>
</table>

### Web-based ITSM solutions

- [glpi-10.0.19](https://glpi-project.org/downloads/)
- [iTop-3.2.1-1-16749](https://sourceforge.net/projects/itop/files/itop/)

### Stacks

- [WampServer v3.x x64](https://wampserver.aviatechno.net/)
- [XAMPP v8.x x64](https://sourceforge.net/projects/xampp/files/)
- [Uniform Server v15.x ZeroXV (UZero)](https://sourceforge.net/projects/miniserver/files/)

### Dependencies (Included)

- [Microsoft Visual C++ Redistributable Runtimes](https://github.com/abbodi1406/vcredist)
- [graphviz v13.x x64](https://graphviz.org/download/)
- [apcu v8.x x64 ts](https://github.com/krakjoe/apcu)

### Prerequisites

- [For GLPI](https://glpi-install.readthedocs.io/en/latest/prerequisites.html)
- [For iTop](https://www.itophub.io/wiki/page?id=latest:install:requirements)

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>itsm.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>itsm.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

### ⚠️ WARNING: STOP SERVICES

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Stop Apache/MySQL services before proceeding.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Detenga los servicios de Apache/MySQL, antes de proseguir.</td>
  </tr>
</table>

### START

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-ini.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Select Web-based ITSM and press OK.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Seleccione ITSM basado en web y presione OK.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-select.png)](https://www.maravento.com)

### STACK SELECTOR

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-stack.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Select the Stack you have installed (WampServer, Xampp, UniServerZ) and press OK.
    </td>
    <td style="width: 50%; white-space: nowrap;">
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
    <td style="width: 50%; white-space: nowrap;">
     It will start installing your choice of itsm, with its dependencies and configurations and when finished the following message will appear:
    </td>
    <td style="width: 50%; white-space: nowrap;">
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
    <td style="width: 50%; white-space: nowrap;">
     Start the Apache/MySQL services before proceeding.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Inicie los servicios de Apache/MySQL, antes de proseguir.
    </td>
  </tr>
</table>

### DESKTOP SHORTCUT

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itsm/img/itsm-icons.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     - During the installation, several shortcuts are created on your PC's desktop. For iTop 2 and GLPI 1, to run iTop for the first time, double-click on <code>iTop Wizard.url</code> which will take you to the iTop setup URL.<br>
     - Once iTop setup is complete, close your browser and delete the shortcut <code>iTop Wizard.url</code>.<br>
     - From now on, every time you want to access iTop, you will need to use the shortcut on your desktop called <code>iTop.url</code>, which will take you to the login URL. There you will need to enter the credentials you set up during the post-installation of iTop.<br>
     - For GLPI, there is only one shortcut <code>GLPI.url</code>, which you will use both to launch it for the first time, and to log in after installation.<br>
     - If double-clicking the iTop or GLPI shortcut on your desktop does not open the URL in your browser, close your browser completely and try again.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     - Durante la instalación se crean varios accesos directos en el escritorio de su PC. Para iTop 2 y GLPI 1. Para ejecutar iTop por primera vez haga doblé clic en <code>iTop Wizard.url</code> que lo llevará a la URL de la configuración de iTop.<br>
     - Una vez concluida la configuración de iTop, cierre su navegador y elimine el acceso directo <code>iTop Wizard.url</code>.<br>
     - A partir de ahora, cada vez que desee acceder a iTop, deberá utilizar el acceso directo en su escritorio llamado <code>iTop.url</code>, el cual lo llevará a la URL de ingreso. Allí deberá introducir las credenciales que configuró durante la post-instalación de iTop.<br>
     - Para GLPI solo hay un acceso directo <code>GLPI.url</code>, el cual usará tanto para iniciar por primera vez, como para ingresar después de instalado.<br>
     - Si al hacer doble clic sobre el acceso directo de iTop o GLPI en su escritorio, no abre la URL en el navegador, cierre el navegador completamente e inténtelo nuevamente.
    </td>
  </tr>
</table>

### WIZARD

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     You can check the iTop and GLPI settings in the shortcuts on your PC desktop named <a href="https://raw.githubusercontent.com/maravento/vault/master/itsm/wizard/iTop-Wizard.pdf" target="_blank">iTop-Wizard.pdf</a> and <a href="https://raw.githubusercontent.com/maravento/vault/master/itsm/wizard/GLPI-Wizard.pdf" target="_blank">GLPI-Wizard.pdf</a>.
</td>
    <td style="width: 50%; white-space: nowrap;">
     Puede consultar las configuraciones de iTop y GLPI en los accesos directos del escritorio de su PC llamados <a href="https://raw.githubusercontent.com/maravento/vault/master/itsm/wizard/iTop-Wizard.pdf" target="_blank">iTop-Wizard.pdf</a> y <a href="https://raw.githubusercontent.com/maravento/vault/master/itsm/wizard/GLPI-Wizard.pdf" target="_blank">GLPI-Wizard.pdf</a>.
    </td>
  </tr>
</table>

### ACCESS BY IP/PORT

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     If you decide to access iTop via the IP address of the PC where iTop is installed, or change the port in Apache (e.g., from 80 to 8080), download the following script that will modify the iTop configuration to allow access in any of these scenarios:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Si decide acceder a iTop mediante la dirección IP del PC donde esté instalado iTop, o cambia el puerto en Apache (e.j:80 por 8080), descargue el siguiente script que modificará la configuración de iTop para que pueda acceder en cualquiera de estos escenarios:
    </td>
  </tr>
</table>

| iTop URL Change (localhost + local IP) |
|----------------------------------------|
|[itopconf.ps1](https://raw.githubusercontent.com/maravento/vault/master/itsm/scripts/itopconf.ps1)|

#### How To Run

| Windows 10 | Windows 11 |
|------------|------------|
| Right-click on the script and select "Run with PowerShell" | Right-click on the script and select "Run with PowerShell". <br> In case it fail do the following: <br> - Open Windows PowerShell as Administrator. <br> - Run the following command to allow script execution: <br> ```Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force``` <br> - Now run the script `itopconf.ps1`. <br> - Once the script has finished, restore the execution policy to a more secure setting by running: <br> ```Set-ExecutionPolicy Restricted -Scope CurrentUser -Force``` |

| Access Example: |
|-----------------|
|`http://localhost/itop/web/pages/UI.php`|
|`http://localhost:8080/itop/web/pages/UI.php`|
|`http://192.168.1.10/itop/web/pages/UI.php`|
|`http://192.168.1.10:8080/itop/web/pages/UI.php`|

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     GLPI does not require any additional configuration. You can access it via localhost or the IP address of the PC where it is installed and the port change must be set in the Apache vhost. E.g.:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     GLPI no necesita configuraciones adicionales. Puede acceder por localhost o la dirección IP del PC donde esté instalado y el cambio de puerto deberá establecerlo en el vhost de Apache. E.j:
    </td>
  </tr>
</table>

| Access Example: |
|-----------------|
|`http://localhost/glpi`|
|`http://localhost:8080/glpi`|
|`http://192.168.1.10/glpi`|
|`http://192.168.1.10:8080/glpi`|

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     If you have problems accessing the iTop or GLPI startup or configuration URL, check your browser's proxy settings or run the following command with administrative privileges:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Si tiene problemas al acceder a la URL de inicio o configuración de iTop o GLPI, revise la configuración de proxy de su navegador o ejecute el siguiente comando con privilegios administrativos:
    </td>
  </tr>
</table>

```bash
netsh winhttp import proxy source=ie
```

### TELEMETRY

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     ITSM sends information to the developer, only for the purpose of verifying that the installation has been completed successfully. This information is used exclusively for statistical purposes and to improve the installer, without collecting personal data or compromising user privacy. Example:
    </td>
    <td style="width: 50%; white-space: nowrap;">
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
- [ACPU Main](https://pecl.php.net/package/APCu)
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

## ITSM SOFTWARE LICENSE

---

| Software | Licence |
| --- | --- |
| [iTop License](https://raw.githubusercontent.com/Combodo/iTop/refs/heads/develop/license.txt) | ![AGPLv3 License](https://img.shields.io/badge/License-AGPLv3-blue.svg) |
| [GLPI License](https://raw.githubusercontent.com/glpi-project/glpi/refs/heads/main/LICENSE)  | ![GPLv3 License](https://img.shields.io/badge/License-GPLv3-blue.svg) |

## PROJECT LICENSES

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
    <td style="width: 50%; white-space: nowrap;">
     Maravento Studio has no relationship with the developers of iTop or GLPI. We also do not use them, do not promote them, and do not provide support. Maravento Studio only provides support for the ITSM installer, which is an open source project, sponsored by <a href="https://co.linkedin.com/in/lancord" target="_blank">Uniopos SAS</a>. Only the sponsor of this installer may use it for commercial purposes.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Maravento Studio no tiene ninguna relación con los desarrolladores de iTop o GLPI. Tampoco los usamos, no los promocionamos y no brindamos soporte. Maravento Studio solo brinda soporte al instalador ITSM, que es un proyecto de código abierto, patrocinado por <a href="https://co.linkedin.com/in/lancord" target="_blank">Uniopos SAS</a>. Solo el patrocinador de este instalador, podrá usarlo con fines comerciales.
    </td>
  </tr>
</table>
