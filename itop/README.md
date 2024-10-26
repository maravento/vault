# [iTop](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

**iTop** is an all-in-one, open-source ITSM platform designed to streamline IT operations. iTop offers a highly customizable, low-code Configuration Management Database (CMDB), along with advanced tools for handling requests, incidents, problems, changes, and service management. iTop is ITIL-compliant, making it ideal for organizations looking for standardized and scalable IT processes.

**iTop** es una plataforma ITSM de código abierto todo en uno diseñada para optimizar las operaciones de TI. iTop ofrece una base de datos de gestión de configuración (CMDB) de código bajo y altamente personalizable, junto con herramientas avanzadas para gestionar solicitudes, incidentes, problemas, cambios y gestión de servicios. iTop es compatible con ITIL, lo que lo hace ideal para organizaciones que buscan procesos de TI estandarizados y escalables.

## DATA SHEET

---

|File|OS|Size|
| :---: | :---: | :---: |
|[iTop.exe (.zip)](https://mega.nz/file/SNkH2B5R#kfqwOlLEebsnWg5qlBznxy8flCaDtl-w4uY749vSMTE)|Windows 10/11 x64|67.8 MB|

### Supported Versions of iTop and Stacks

- [iTop v3.2.0-2-14758](https://sourceforge.net/projects/itop/files/itop/)
- [WampServer v3.3.5 x64 update v3.3.6](https://wampserver.aviatechno.net/)
- [XAMPP v8.2.12-0-VS16 x64](https://sourceforge.net/projects/xampp/files/)
- [Uniform Server v15.0.2 ZeroXV (UZero)](https://sourceforge.net/projects/miniserver/files/)

Backward compatibility is not guaranteed. / No se garantiza compatibilidad con versiones anteriores.

### Hardware & Software requirements

Check the minimum requirements [HERE](https://www.itophub.io/wiki/page?id=latest:install:requirements). / Verifique los requerimientos mínimos [AQUÍ](https://www.itophub.io/wiki/page?id=latest:install:requirements)

## HOW TO USE

---

Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip `iTop.exe` (.zip) to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen

Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima `iTop.exe` (.zip) en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla

### ⚠️ WARNING: STOP SERVICES

Stop Apache/MySQL services before proceeding. / Detenga los servicios de Apache/MySQL, antes de proseguir.

### START

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-ini.png)](https://www.maravento.com)

Press OK to begin. If you choose CANCEL, you will abort the process and the following window will appear: / Pulse OK para comenzar. Si elije CANCEL, abortará el proceso y saldrá la siguiente ventana:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-cancel.png)](https://www.maravento.com)

### STACK SELECTOR

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-menu.png)](https://www.maravento.com)

Select the Stack you have installed (WampServer, Xampp, UniServerZ) and press OK. / Seleccione el Stack que tenga instalado (WampServer, Xampp, UniServerZ) y presione OK.

If you do not have any of these Stacks installed, you will get the following message: / Si no tiene ninguno de estos Stack instalados, saldrá el siguiente mensaje:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-nostack.png)](https://www.maravento.com)

So before you proceed, make sure that the Stack of your choice is installed. Below are the paths accepted by the installer: / Por tanto, antes de continuar, asegúrese de que el Stack de su elección esté instalado. A continuación, los path aceptados por el instalador:

- WampServer: %HOMEDRIVE%\wamp64
- Xampp: %HOMEDRIVE%\xampp
- UniformServerZ: %HOMEDRIVE%\UniServerZ

### INSTALLATION

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-run.png)](https://www.maravento.com)

The installation of iTop will start, with its dependencies and configurations, and when finished the following message will appear: / Iniciará la instalación de iTop, con sus dependencias y configuraciones y al terminar saldrá el siguiente mensaje:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-complete.png)](https://www.maravento.com)

### ⚠️ WARNING: START SERVICES

Start the Apache/MySQL services before proceeding. / Inicie los servicios de Apache/MySQL, antes de proseguir.

### DESKTOP SHORTCUT

[![Image](https://raw.githubusercontent.com/maravento/vault/master/itop/img/itop-icons.png)](https://www.maravento.com)

During the installation, two shortcuts are created on your PC's desktop. Double-click on `iTop Wizard (.url)` which will take you to the iTop setup URL. / Durante la instalación se crean dos accesos directos en el escritorio de su PC. Haga doblé clic en `iTop Wizard (.url)` que lo llevará a la URL de la configuración de iTop.

Once you have completed the iTop setup, close your browser. From now on, to access iTop, you will need to use the second shortcut on your desktop called `iTop (.url)` which will take you to the login URL, where you will enter the credentials you chose in the iTop setup. / Una vez concluida la configuración de iTop, cierre su navegador. Y a partir de ahora, para acceder a iTop, deberá usar el segundo acceso directo de su escritorio llamado `iTop (.url)` que lo llevará a la URL de ingreso, en la cual introducirá las credenciales que eligió en la configuración de iTop.

### WIZARD

To start the iTop setup, double-click the `iTop Wizard (.url)` icon and follow the instructions described in the PDF located in the wizard folder of this repository or on your PC's desktop: / Para iniciar la configuración de iTop, haga doble clic en el ícono `iTop Wizard (.url)` y siga las instrucciones descritas en el PDF que se encuentra en la carpeta wizard de este repositorio o en el escritorio de su PC:

[iTop-Wizard.pdf](https://raw.githubusercontent.com/maravento/vault/master/itop/wizard/iTop-Wizard.pdf)

### IMPORTANT BEFORE USE ITOP

- The default database is iTop with the format: / La base de datos por defecto es iTop con el formato: `utf8mb4_unicode_ci`.
- This installer modifies the default values ​​of `post_max_size=64M` for PHP and `max_allowed_packet=50M` for MySQL, across stacks. If the value of `post_max_size` is greater than `40M` and the value of `max_allowed_packet` is greater than `1M`, there will be no configuration changes. / Este instalador modifica los valores por defecto de `post_max_size=64M` para PHP y `max_allowed_packet=50M` para MySQL, en los diferentes Stacks. Si el valor de `post_max_size` es superior a `40M` y el valor de `max_allowed_packet` es superior a `1M`, no habrá cambios en la configuración.
- If you have any questions about your Stack parameters or during the configuration you get any conflicts or warning messages from iTop related to Apache/PHP/MySQL, for more information, please visit: / Si tiene alguna duda sobre los parámetros de su Stack o durante la configuración se presenta algún conflicto o mensajes de advertencia de iTop, relacionados con Apache/PHP/MySQL, para obtener mayor información, ingrese a: `http://localhost/info.php`.

### CHANGING PORTS

If you decide to change the Apache/MySQL ports on your Stack, you will also need to change them in iTop. To do this, download the following script that will help you through the process: / Si decide cambiar los puertos de Apache/MySQL en su Stack, también deberá cambiarlos en iTop. Para esto descargue el siguiente script que le ayudará en el proceso:

[itopconf.bat](https://github.com/maravento/vault/blob/master/scripts/batch/itopconf.bat)

You will also need to change the URL of the `iTop.url` shortcut on your desktop. / También deberá cambiar la URL del acceso directo `iTop.url` en su escritorio.

Example: Changing the Apache port from 80 to 8080: / Ejemplo: Cambio del puerto Apache, de 80 a 8080:

`http://localhost/itop/web/pages/UI.php` 

by/por:

`http://localhost:8080/itop/web/pages/UI.php`

## PACKAGES AND TOOLS

---

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [ACPU](https://github.com/krakjoe/apcu)
- [Checksum Control](https://sourceforge.net/projects/checksumcontrol/)
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

Maravento Studio has no relationship with the developers of iTop. We also don't use iTop, we don't promote it, and we don't provide support. Maravento Studio only supports the iTop installer, which is an open source project, sponsored by [Uniopos SAS](https://co.linkedin.com/in/lancord). Only the sponsor of this installer may use it for commercial purposes. / Maravento Studio no tiene ninguna relación con los desarrolladores de iTop Files. Tampoco usamos iTop, no lo promocionamos y no brindamos soporte. Maravento Studio solo brinda soporte al instalador iTop, que es un proyecto de código abierto, patrocinado por [Uniopos SAS](https://co.linkedin.com/in/lancord). Solo el patrocinador de este instalador, podrá usarlo con fines comerciales.
