# [UniOPOS](https://uniopos.com/)

[![status-frozen](https://img.shields.io/badge/status-frozen-blue.svg)](https://sourceforge.net/projects/unicentaopos/files/releases/)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     <b>uniOPOS</b> it is a preconfigured installation package of uniCenta OPOS for Points of Sales (POS/ERP Open Source).
    </td>
    <td width="50%">
     <b>uniOPOS</b> es un paquete de instalación preconfigurado de uniCenta OPOS para Puntos de Ventas (POS/ERP Open Source).
    </td>
  </tr>
</table>

## UNIOPOS FOR WINDOWS

---

### Data Sheet

|File|OS|Size|
| :---: | :---: | :---: |
| [uniOPOS.exe (.zip)](https://mega.nz/file/vUUTXarT#w5UQlnc-KkzCIlqsBqmk6wjY6_r-zhAQEIxkYQO6Ov8) | Windows 7/8/10/11 x64 | 1.58 GB |

### Important About uniOPOS

<table width="100%">
  <tr>
    <td width="50%">
     This project has become deprecated, due to uniCenta oPOS 5x. For more information:
    </td>
    <td width="50%">
     Este proyecto ha quedado obsoleto, debido a uniCenta oPOS 5x. Para mayor información:
    </td>
  </tr>
</table>

- [uniCenta-oPos-5.0-Migration-Guide.pdf](https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/docs/uniCenta-oPos-5.0-Migration-Guide.pdf)

### How to Use

<table width="100%">
  <tr>
    <td width="50%">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>uniOPOS.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td width="50%">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>uniOPOS.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

### Important Before Use

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniopos-selector.png">
</div>

<table width="100%">
  <tr>
    <td width="50%">
     uniOPOS contains three (3) options. Select the one you are going to work with. At the end of the installation of each package the following message will appear:
    </td>
    <td width="50%">
     uniOPOS contiene tres (3) opciones. Seleccione con el que va a trabajar. Al finalizar la instalación de cada paquete saldrá el siguiente mensaje:
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniopos-end.png">
</div>

#### About SO

<table width="100%">
  <tr>
    <td width="50%">
     - Some bundled packages are only compatible with 64-bit architecture.
    </td>
    <td width="50%">
     - Algunos paquetes incluidos solo son compatibles con arquitectura 64 bits.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - Backward compatibility to Windows 10 is not guaranteed.
    </td>
    <td width="50%">
     - La compatibilidad con versiones anteriores a Windows 10 no está garantizada.
    </td>
  </tr>
</table>

#### About Dependencies

<table width="100%">
  <tr>
    <td width="50%">
     - According to the <a href="https://unicenta.com/pages/install-unicenta-opos/" target="_blank">Minimum Requirements</a>, uniCenta oPOS depends on Java. Therefore, uniOPOS includes:
    </td>
    <td width="50%">
     - De acuerdo a los <a href="https://unicenta.com/pages/install-unicenta-opos/" target="_blank">Requisitos Mínimos</a>, uniCenta oPOS depende de Java. Por tanto, uniOPOS incluye:
    </td>
  </tr>
</table>

  ```shell
  Oracle Java 8 Update 421 x86 x64
  ```

<table width="100%">
  <tr>
    <td style="width: 50%; padding-bottom: 10px;">
     - According to the developers, <a href="https://unicenta.com/pages/configure-unicenta-opos/" target="_blank">uniCenta oPOS v4x only uses MySQL Server and v5.7.x is recommended</a>.
    </td>
    <td style="width: 50%; padding-bottom: 10px;">
     - Según los desarrolladores, <a href="https://unicenta.com/pages/configure-unicenta-opos/" target="_blank">uniCenta oPOS v4x solamente utiliza MySQL Server y v5.7.x es la recomendada</a>.
    </td>
  </tr>
  <tr>
    <td style="width: 50%; padding-bottom: 10px;">
     - According to the <a href="https://dev.mysql.com/doc/refman/5.7/en/windows-installation.html" target="_blank">official MySQL channel</a>, MySQL Community v5.7 Server requires Microsoft Visual C++ 2019 Redistributable Package to run on Windows platforms (This requirement changed over time: MySQL 5.7.37 and earlier require Microsoft Visual C++ 2013 Redistributable Package, MySQL 5.7.38 and 5.7.39 require both, and only the Microsoft Visual C++ 2019 Redistributable Package is required as of MySQL 5.7.40). Therefore, uniOPOS includes:
    </td>
    <td style="width: 50%; padding-bottom: 10px;">
     - Según el <a href="https://dev.mysql.com/doc/refman/5.7/en/windows-installation.html" target="_blank">official MySQL channel</a>, MySQL Community v5.7 Server requiere Microsoft Visual C++ 2019 Redistributable Package para ejecutarse en plataformas Windows (Este requisito cambió con el tiempo: MySQL 5.7.37 y anteriores requieren Microsoft Visual C++ 2013 Redistributable Package, MySQL 5.7.38 y 5.7.39 requieren ambos, y solo se requiere el paquete redistribuible de Microsoft Visual C++ 2019 a partir de MySQL 5.7.40). Por tanto, uniOPOS incluye:
    </td>
  </tr>
</table>


  ```shell
  Microsoft Visual Basic/C++ Runtime x86
  Microsoft Visual C++ 2005 Redistributable x86 x64
  Microsoft Visual C++ 2008 Redistributable x86 x64
  Microsoft Visual C++ 2010 Redistributable x86 x64
  Microsoft Visual C++ 2012 Redistributable x86 x64
  Microsoft Visual C++ 2013 Redistributable x86 x64
  Microsoft Visual C++ 2022 Redistributable x86 x64
  ```

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniopos-deps.png">
</div>

#### About Backup

<table width="100%">
  <tr>
    <td width="50%">
    If you have previous versions of uniOPOS (or some of its components: uniCenta oPOS (<code>unicentaopos.properties</code>), MySQL Server (DBs & config), etc.) installed on your system, it is highly recommended that you remove or stop the related services. uniOPOS can also remove previous versions of its components, so Backup before using it.
    </td>
    <td width="50%">
    Si tiene versiones previas de uniOPOS (o de algunos de sus componentes: uniCenta oPOS (<code>unicentaopos.properties</code>), MySQL Server (DBs & config), etc), instaladas en su sistema, se recomenda encarecidamente que las elimine o detenga los servicios relacionados. uniOPOS también puede eliminar versiones previas de sus componentes, por tanto haga Backup antes de usarlo.
    </td>
  </tr>
</table>

#### About DB

<table width="100%">
  <tr>
    <td width="50%">
     - Always check the port in the uniCenta oPOS Control Panel (example: <code>jdbc:mysql://localhost:3306/</code>) that matches the port in use of MySQL Server.
    </td>
    <td width="50%">
     - Verifique siempre el puerto en el Panel de Control de uniCenta oPOS (ejemplo: <code>jdbc:mysql://localhost:3306/</code>) que coincida con el puerto en uso de MySQL Server.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - If you are going to work with MariaDB instead of MySQL Server (not recommended by developer), edit your <code>.sql</code> file and replace the line <code>ROW_FORMAT=COMPACT;</code> by <code>ROW_FORMAT=DYNAMIC;</code>.
    </td>
    <td width="50%">
     - Si va a trabajar con MariaDB en lugar de MySQL Server (no recomendado por el desarrollador), edite su archivo <code>.sql</code> y reemplace la línea <code>ROW_FORMAT=COMPACT;</code> por <code>ROW_FORMAT=DYNAMIC;</code>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - To manage databases, the options "Install" and "Portable" include phpMyAdmin. Option "WebServer" includes <a href="https://www.heidisql.com/" target="_blank">HeidiSQL</a>.
    </td>
    <td width="50%">
     - Para administrar bases de datos, las opciones "Instalación" y "Portable" incluyen phpMyAdmin. La opción "WebServer" incluye <a href="https://www.heidisql.com/" target="_blank">HeidiSQL</a>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - From uniCenta oPOS 4.5 only the Database Transfer tool is available. It will upgrade any previous uniCenta oPOS version from 3.0 and also includes Openbravo POS 2.30.
    </td>
    <td width="50%">
     - Desde uniCenta oPOS 4.5 solo está disponible la herramienta de Transferencia de Base de Datos. Actualizará cualquier versión anterior de uniCenta oPOS de 3.0 y también incluye Openbravo POS 2.30.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - Note that utf8 (MySQL 5.5 and earlier), utf8mb3 (MySQL 5.7), utf8mb4 (MySQL 8.0 and later).
    </td>
    <td width="50%">
     - Tenga en cuenta que utf8 (MySQL 5.5 y versiones anteriores), utf8mb3 (MySQL 5.7), utf8mb4 (MySQL 8.0 y versiones posteriores).
    </td>
  </tr>
  <tr>
    <td width="50%">
     - It is recommended to increase the following values of <code>my.ini</code> or <code>my.cnf</code>:
    </td>
    <td width="50%">
     - Se recomienda incrementar los siguientes valores de <code>my.ini</code> o <code>my.cnf</code>:
    </td>
  </tr>
</table>

  ```shell
  innodb_log_file_size = 512M
  innodb_log_buffer_size = 32M
  innodb_strict_mode = 0
  max_allowed_packet = 128M
  ```

#### About phpMyAdmin

<table width="100%">
  <tr>
    <td width="50%">
     According to <a href="https://docs.phpmyadmin.net/en/latest/faq.html#faq1-16" target="_blank">phpMyAdmin FAQ1.16</a>), it is recommended to increase the following values of <code>php.ini</code>:
    </td>
    <td width="50%">
     De acuerdo con <a href="https://docs.phpmyadmin.net/en/latest/faq.html#faq1-16" target="_blank">phpMyAdmin FAQ1.16</a>, se recomienda incrementar los siguientes valores de <code>php.ini</code>:
    </td>
  </tr>
</table>

```shell
max_execution_time = 300
max_input_time = 200
memory_limit = 512M
post_max_size = 256M
upload_max_filesize = 256M
```

#### About Java 8

<table width="100%">
  <tr>
    <td width="50%">
     - If you work with IPv4 and want to prevent Java from connecting through the IPv6 stack, run in cmd (as admin) the following command:
    </td>
    <td width="50%">
     - Si trabaja con IPv4 y quiere evitar que Java se conecte a través de la pila IPv6, ejecute en cmd (como admin) el siguiente comando:
    </td>
  </tr>
</table>

  `setx _JAVA_OPTIONS -Djava.net.preferIPv4Stack=true`

<table width="100%">
  <tr>
    <td width="50%">
     - Beginning with the April 2021 releases of OpenJDK, TLS 1.0 and TLS 1.1 is disabled by default. If you use a version higher than Java v8u211, when connecting uniCenta oPOS with MySQL Server an error will appear:
    </td>
    <td width="50%">
     - A partir de las versiones de abril de 2021 de OpenJDK, TLS 1.0 y TLS 1.1 están deshabilitados de forma predeterminada. Si usa una versión superior a Java v8u211, al conectar uniCenta oPOS con MySQL Server saldrá error:
    </td>
  </tr>
</table>

  ```shell
  com.mysql.jdbc.exceptions.jdbc4.CommunicationsException:
  Communications link failure
  Error: javax.net.ssl.SSLHandshakeException: No appropriate protocol
  (protocol is disabled or cipher suites are inappropriate)
  ```

  **There are several methods to solve it: | There are several methods to solve it:**

  - [Java Rolling Back, by the developer forum](https://unicenta.com/community/postid/11846/):

  > Downgrade to version: | Degradar a la versión:
  > [Java a SE Runtime Environment 8u211](https://www.oracle.com/ca-en/java/technologies/javase/javase8u211-later-archive-downloads.html) or add `?useSSL=no`

  - [Disable the TLS anon and NULL cipher suites, by azul](https://support.azul.com/hc/en-us/articles/360061143191-TLSv1-v1-1-No-longer-works-after-upgrade-No-appropriate-protocol-error):

   > Edit (as admin) file (depends on your version of java): | Editar (como admin) el archivo (depende de su versión de java):
   >
   > `Program Files\Java\jre-1.8(XXX)\lib\security\java.security`
   >
   > And disable or remove the following SSL line, save the changes and reboot the PC: | Y desactive o elimine la siguiente línea SSL, guarde los cambios y reinicie el PC:

  ```shell
  # jdk.tls.disabledAlgorithms=SSLv3, TLSv1, TLSv1.1, RC4, DES, MD5withRSA, \
  #      DH keySize < 1024, EC keySize < 224, 3DES_EDE_CBC, anon, NULL, \
  #      include jdk.disabled.namedCurves
  ```

  - [Connecting Securely Using SSL by MySQL](https://dev.mysql.com/doc/connector-j/8.0/en/connector-j-reference-using-ssl.html#:~:text=TLSv1.2%20and%20TLSv1.3.-,Notes,-Since%20Connector/J):
  > Add string connection.
  >
  > Before Connector/J 8.0.28: `jdbc:mysql://localhost:3306/database_name?enabledTLSProtocols=TLSv1.2`
  >
  > Since Connector/J 8.0.28 and later: `jdbc:mysql://localhost:3306/database_name?tlsVersions=TLSv1.2`
  >
  >  After Java changes and reboot, uniCenta oPOS will now be able to connect: | Después de los cambios en Java y reinicio, uniCenta oPOS ya podrá conectarse:

  <div align="center">
    <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/unicenta_connected.png" width="80%" height="80%">
  </div>

### Install Pack

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/unioposwamp.png">
</div>

#### Content of Install Pack

- [uniCenta oPOS v4.6.4 (.exe)](https://sourceforge.net/projects/unicentaopos/)
- [Wampserver v3.3.0 x64 - Update 3.3.6 (.exe)](https://wampserver.aviatechno.net/?lang=en) (included: Apache 2.4.54.2 - PHP 7.4.33/8.0.26/8.1.13/8.2.0 - MySQL 5.7.40|8.0.31 - MariaDB 10.10.2)

#### Important Before Use Install Pack

<table width="100%">
  <tr>
    <td width="50%">
     - uniCenta oPOS + WampServer only for Windows 10/11 x64.
    </td>
    <td width="50%">
     - uniCenta oPOS + WampServer únicamente para Windows 10/11 x64.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - If you select uniCenta oPOS + WampServer, keep in mind that installs MySQL Server (By default service start automatically) and MariaDB (By default service does not start automatically).
    </td>
    <td width="50%">
     - Si selecciona uniCenta oPOS + WampServer, tenga en cuenta que instala MySQL Server (Por defecto inicia automáticamente) y MariaDB (por defecto el servicio no inicia automáticamente).
    </td>
  </tr>
  <tr>
    <td width="50%">
     - Installation is done in insecure mode, so access to <code>root</code> account is <b>without a password</b> (you must create one).
    </td>
    <td width="50%">
     - La instalacion se realiza en  modo inseguro, por tanto el acceso a la cuenta <code>root</code> es <b>sin contraseña</b> (deberá crear una).
    </td>
  </tr>
  <tr>
    <td width="50%">
     - uniCenta oPOS + WampServer uses port 80 by default for Apache/phpMyAdmin, therefore it is recommended to release this port (<ins>Note</ins>: if you use the IIS World Wide Web Publishing service, installing this package will change the IIS service to <code>manual</code>, to avoid conflicts).
    </td>
    <td width="50%">
     - uniCenta oPOS + WampServer usa el puerto 80 por defecto para Apache/phpMyAdmin, por tanto se recomienda liberar este puerto (<ins>Nota</ins>: si usa el servicio de IIS World Wide Web Publishing, la instalación de este paquete cambiará el servicio IIS a <code>manual</code>, para evitar conflictos).
    </td>
  </tr>
</table>

### Portable Pack

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/unioposuniserver.png">
</div>

#### Content of Portable Pack

- [uniCenta OPOS v4.6.4 _no_installer](https://sourceforge.net/projects/unicentaopos/)
- [Uniform Server ZeroXV (v15.0.2)](https://sourceforge.net/projects/miniserver/files/Uniform%20Server%20ZeroXV/) (Additional modules included: [adminer v4.8.3, mysql autoback v1.0.2, uniservice v2.5.2](https://sourceforge.net/projects/miniserver/files/Uniform%20Server%20ZeroXV/ZeroXV%20Modules/), and [mysql v5.7.37 from ZeroIV](https://sourceforge.net/projects/miniserver/files/Uniform%20Server%20ZeroXIV/ZeroXIV%20Modules/))

#### Self-Extracting

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/portablesrv-extract.png">
</div>

#### Shortcut and Folder

<table width="100%">
  <tr>
    <td width="50%">
     Go to the destination folder <code>%HOMEDRIVE%\PortableSrv\</code> and find the shortcuts to start Unicenta and Uniserver.
    </td>
    <td width="50%">
     Vaya a la carpeta de destino <code>%HOMEDRIVE%\PortableSrv\</code> y encontrará los accesos directos para iniciar Unicenta y UniserverZ.
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/portablesrv-shortcut.png">
</div>

#### Important Before Use Portable Pack

<table width="100%">
  <tr>
    <td width="50%">
     - If you select uniCenta oPOS + UZero, when installation is finished, you must run <code>UniController</code> with administrative privileges. It will ask you <code>Enter new MySQL root password or press cancel</code>. It is recommended to change default password <code>root</code>.
    </td>
    <td width="50%">
     - Si selecciona uniCenta oPOS + UZero, al terminar la instalación, debe ejecutar <code>UniController</code> con privilegios administrativos. Solicitará <code>Ingresa la nueva contraseña de root de MySQL o presiona cancelar</code>. Se recomienda cambiar la contraseña por defecto <code>root</code>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - While Apache is running to prevent problems, php menu option is disabled (greyed out).
    </td>
    <td width="50%">
     - Mientras Apache se ejecuta para evitar problemas, la opción de menú php está deshabilitada (atenuada).
    </td>
  </tr>
  <tr>
    <td width="50%">
     - According to the [UZero PHP documentation](https://www.uniformserver.com/ZeroXI_documentation/php.html), it works with three (3) versions of <code>php.ini</code> (<code>php_test.ini</code>, <code>php_development.ini</code> and <code>php_production.ini</code>). The default is <code>php_production.ini</code>, so if you don't choose another configuration file in the PHP menu, any configuration changes will have to be made in the <code>php_production.ini</code> file.
    </td>
    <td width="50%">
     - Según la [documentación de UZero PHP](https://www.uniformserver.com/ZeroXI_documentation/php.html), trabaja con tres (3) versiones de <code>php.ini</code> (<code>php_test.ini</code>, <code>php_development.ini</code> and <code>php_production.ini</code>). Por defecto <code>php_production.ini</code>, por tanto, si no elije otro archivo de configuración en el menú PHP, cualquier cambio en la configuración deberá hacerlo en el archivo <code>php_production.ini</code>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - phpMyAdmin starts by default in French language. To change it, open the phpMyAdmin administration page, log in, find the "Paramètres d'affichage (Appearance Settings)" section and change the language in the "Langue (Language)" drop-down menu.
    </td>
    <td width="50%">
     - phpMyAdmin inicia por defecto en idioma francés. Para cambiarlo, abra la página de administración de phpMyAdmin, inicie sesión, busque la sección de "Paramètres d'affichage (Configuración de Apariencia)" y cambie el idioma en el menú desplegable "Langue (Language)".
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/phpmyadmin-language.png" width="80%" height="80%">
</div>

<table width="100%">
  <tr>
    <td width="50%">
     To start it automatically with your system, go to the path `%HOMEDRIVE%\PortableSrv\UniserverZ\permanent` and run the `permanent.bat` script with privileges and follow the instructions on the screen. Or open the `Extra\PC-Win Start-Up` menu and check the boxes for autostart.
    </td>
    <td width="50%">
     Para iniciarlo automáticamente con su sistema, vaya al path `%HOMEDRIVE%\PortableSrv\UniserverZ\permanent` y ejecute con privilegios el script `permanent.bat` y siga las instrucciones en pantalla. O abra el menú `Extra\PC-Win Start-Up` y marque las casillas correspondientes al inicio automático.
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniserverzero.png">
</div>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniserverrun.png" width="80%" height="80%">
</div>

### WebServer Pack

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/webserver-start.png">
</div>

#### Content of WebServer Pack

- [uniCenta oPOS WebServer v4.6.4 (.zip)](https://sourceforge.net/projects/unicentaopos/)
- [HeidiSQL v12.8 x64 Portable.zip (.exe)](https://www.heidisql.com/download.php)
- [MySQL Server v5.7.44 x64 (no-install package .zip)](https://dev.mysql.com/downloads/mysql/5.7.html#downloads/)

#### Desktop Launcher

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/desktop_webserver.png">
</div>

#### Important Before Use WebServer Pack

<table width="100%">
  <tr>
    <td width="50%">
    - Exclude the <code>%HOMEDRIVE%\websrv</code> folder from your antivirus or security solution.
    </td>
    <td width="50%">
    - Excluya la carpeta <code>%HOMEDRIVE%\websrv</code> de su antivirus o solución de seguridad.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - This package delete previous folder (<code>%HOMEDRIVE%\websrv</code>) before installing, therefore make backup of your DBs and configurations before executing it. Read <a href="https://github.com/maravento/uniopos#about-backup" target="_blank">About Backup</a>.
    </td>
    <td width="50%">
     - Este paquete elimina la carpeta previa (<code>%HOMEDRIVE%\websrv</code>) antes de instalar, por tanto haga backup de sus DBs y configuraciones antes de ejecutarlo. Lea <a href="https://github.com/maravento/uniopos#about-backup" target="_blank">About Backup</a>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - Keep in mind the same requirements as described in <a href="https://github.com/maravento/uniopos#about-db" target="_blank">About DB</a>, <a href="https://github.com/maravento/uniopos#about-java" target="_blank">About Java</a>.
    </td>
    <td width="50%">
     - Tenga en cuenta los mismos requerimientos descritos en: <a href="https://github.com/maravento/uniopos#about-db" target="_blank">About DB</a>, <a href="https://github.com/maravento/uniopos#about-java" target="_blank">About Java</a>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - HeidiSQL is compatible with Win 10/11 (and Win 7 with some limitations) and to connect to MS SQL servers enabled for TLS 1.2 requires <a href="https://www.microsoft.com/en-us/download/confirmation.aspx?id=56730" target="_blank">OLE DB Driver 18 for SQL Server</a>.
    </td>
    <td width="50%">
     - HeidiSQL es compatible con Win 10/11 (y Win 7 con algunas limitaciones) y para conectarse a servidores MS SQL habilitados para TLS 1.2 requiere <a href="https://www.microsoft.com/en-us/download/confirmation.aspx?id=56730" target="_blank">OLE DB Driver 18 for SQL Server</a>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - The path of MySQL Data DB is <code>%HOMEDRIVE%\websrv\mysql\data\mysql\</code>.
    </td>
    <td width="50%">
     - El path de MySQL Data DB es: <code>%HOMEDRIVE%\websrv\mysql\data\mysql\</code>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - MySQL Server Installation is in insecure mode, so access to <code>root</code> account is <b>without a password</b> (you must create one).
    </td>
    <td width="50%">
     - La instalacion de MySQL Server es en modo inseguro, por tanto el acceso a la cuenta <code>root</code> es <b>sin contraseña</b> (deberá crear una).
    </td>
  </tr>
  <tr>
    <td width="50%">
     - uniCenta oPOS Web Server includes <a href="https://www.eclipse.org/jetty/" target="_blank">Jetty</a>, therefore you do not need to install apache, nginx or another web server.
    </td>
    <td width="50%">
     - uniCenta oPOS Web Server incluye <a href="https://www.eclipse.org/jetty/" target="_blank">Jetty</a>, por tanto no necesita instalar apache, nginx u otro web server.
    </td>
  </tr>
</table>

<table width="100%">
  <tr>
    <td width="50%">
     <b>Default User</b>
    </td>
    <td width="50%">
     <b>Default Pass</b>
    </td>
    <td width="50%">
     <b>Access</b>
    </td>
  </tr>
  <tr>
    <td width="50%">
     admin
    </td>
    <td width="50%">
     pwd
    </td>
    <td width="50%">
     <a href="http://localhost/phpmyadmin" target="_blank">phpMyAdmin</a>
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/unicentalocalhost.png" width="80%" height="80%">
</div>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/unicentawebserver.png" width="80%" height="80%">
</div>

<table width="100%">
  <tr>
    <td width="50%">
     To access uniCenta oPOS Web Server from another computer's browser, you must use static IP on your server. And replace IP:port in <code>\unicenta-webserver\jetty.properties</code>.
    </td>
    <td width="50%">
     Para acceder a uniCenta oPOS Web Server desde el navegador de otro equipo, debe usar IP estática en su servidor. Y cambiar la IP:Puerto en <code>\unicenta-webserver\jetty.properties</code>.
    </td>
  </tr>
</table>

```shell
:: Line to change localhost to your server IP or 0.0.0.0
org.webswing.server.host=localhost
:: Line to change the port
org.webswing.server.http.port=8080
```

- Activate "Allow Server Printing"

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/allowserverprint.png" width="80%" height="80%">
</div>

## UNIOPOS FOR LINUX

---

### How to Use Linux Pack

```shell
wget -c -q https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/scripts/uniopos.sh
sed -i "s:your_user:$USER:g" uniopos.sh
sudo chmod +x uniopos.sh
sudo ./uniopos.sh
```

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniopos-linux.png" width="80%" height="80%">
</div>

#### Important Before Use Linux Pack

|Tested On|Default User AMPPS|Default Pass AMPPS|Default User LAMP|Default Pass LAMP|Default phpMyAdmin|
| :---: | :---: | :---: |:---: |:---: |:---: |
|Ubuntu 20.04/22.04 x64|root|mysql|root|uniopos|[phpMyAdmin](http://localhost/phpmyadmin)|

<table width="100%">
  <tr>
    <td width="50%">
     - To connect uniCenta oPOS to MySQL Server you must create a new username/password in phpMyAdmin.
    </td>
    <td width="50%">
     - Para conectar uniCenta oPOS a MySQL Server debe crear un nuevo usuario/password en phpMyAdmin.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - LAMP is the recommended installation option. Includes <a href="https://bitnami.com/stack/lamp/installer/changelog.txt" target="_blank">MySQL Server v5.7.28</a>. Do not update or it will stop working for uniCenta oPOS. Also, [Bitnami has discontinued support for most native Linux installers as of June 30, 2021, included <a href="https://blog.bitnami.com/2021/04/amplifying-our-focus-on-cloud-native.html" target="_blank">Bitnami has discontinued support for most native Linux installers as of June 30, 2021</a>.
    </td>
    <td width="50%">
     - LAMP es la opción de instalación recomendada. Incluye <a href="https://bitnami.com/stack/lamp/installer/changelog.txt" target="_blank">MySQL Server v5.7.28</a>. No la actualice o dejará de funcionar para uniCenta oPOS. Además, <a href="https://blog.bitnami.com/2021/04/amplifying-our-focus-on-cloud-native.html" target="_blank">Bitnami ha descontinuado el soporte para la mayoría de los instaladores nativos para Linux a partir del 30 de junio de 2021</a>.
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/bitnamylamp.png" width="80%" height="80%">
</div>
<br />
<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/lampunicenta.png" width="80%" height="80%">
</div>

<table width="100%">
  <tr>
    <td width="50%">
     - uniCenta oPOS has two versions. Install and Web Server.
    </td>
    <td width="50%">
     - uniCenta oPOS tiene dos versiones. Install y Web Server.
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/unicenta-linux-selector.png">
</div>

##### About uniCenta oPOS on Linux

<table width="100%">
  <tr>
    <td width="50%">
     - When the installation is finished, start uniCenta oPOS by double clicking on the shortcut on the desktop.
    </td>
    <td width="50%">
     - Al terminar la instalación, inicie uniCenta oPOS con doble clic en el acceso directo en el escritorio.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - If you don't have a graphical environment, run the following command:
    </td>
    <td width="50%">
     - Si no tiene entorno gráfico, ejecute el siguiente comando:
    </td>
  </tr>
</table>

```shell
# start
sudo /opt/unicentaopos-4.6.4/start.sh
# kill
sudo pkill -f 'java'
```

##### About uniCenta oPOS Web Server on Linux

<table width="100%">
  <tr>
    <td width="50%">
     - If you installed uniCenta oPOS Web Server and you are going to use AMPPS or LAMP, do not enable Apache Web Server (MySQL Server only).
    </td>
    <td width="50%">
     - Si instaló uniCenta oPOS Web Server y va a usar AMPPS o LAMP, no active Apache Web Server (solo MySQL Server).
    </td>
  </tr>
  <tr>
    <td width="50%">
     - To start uniCenta oPOS Web Server, open the terminal and run the following script:
    </td>
    <td width="50%">
     - Para iniciar uniCenta oPOS Web Server, abra el terminal y ejecute el siguiente script:
    </td>
  </tr>
</table>

```shell
# start
sudo /opt/unicenta-webserver/run.sh
# kill
sudo pkill -f 'java'
```

<table width="100%">
  <tr>
    <td width="50%">
     - When it initialises open a browser tab:
    </td>
    <td width="50%">
     - Cuando se inicializa, abra una pestaña del navegador:
    </td>
  </tr>
</table>

```shell
http://localhost:8080/unicentaopos/
```

<table width="100%">
  <tr>
    <td width="50%">
     - For more information about uniCenta oPOS Web Server, see the section <a href="https://github.com/maravento/uniopos#important-before-use-webserver-pack" target="_blank">Important Before Use WebServer Pack</a>.
    </td>
    <td width="50%">
     - Para mayor información sobre uniCenta oPOS Web Server consulte la sección <a href="https://github.com/maravento/uniopos#important-before-use-webserver-pack" target="_blank">Important Before Use WebServer Pack</a>.
    </td>
  </tr>
</table>

##### LAMP / AMPPS by Command Line

<table width="100%">
  <tr>
    <td width="50%">
     If you don't have a graphical environment, you can work by command line:
    </td>
    <td width="50%">
     Si no tiene entorno gráfico, puede trabajar por línea de comandos:
    </td>
  </tr>
</table>

LAMP:

```shell
# start/stop/restart/status
sudo /opt/bitnami/ctlscript.sh restart mysql
sudo /opt/bitnami/ctlscript.sh restart apache
```

AMPPS:

```shell
# start
sudo /usr/local/ampps/apache/bin/httpd
sudo /usr/local/ampps/mysql/bin/mysqld
# kill
sudo killall httpd
sudo killall mysqld
```

#### Linux Bugs

<table width="100%">
  <tr>
    <td width="50%">
     Java 8 is a third party repository and a bug report may appear (To purge Java check <a href="https://askubuntu.com/a/185250/828892" target="_blank">HERE</a>):
    </td>
    <td width="50%">
     Java 8 es un repositorio de terceros y puede aparecer un informe de error (Para eliminar Java verifique <a href="https://askubuntu.com/a/185250/828892" target="_blank">AQUÍ</a>):
    </td>
  </tr>
</table>

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/javareport.png" width="50%" height="50%">
</div>

#### AMPPS Warning

<table width="100%">
  <tr>
    <td width="50%">
     uniCenta oPOS works with MySQL Server v5.7.x. AMPPS v3.8 contains MySQL Server v5.6.37 and a warning may appear:
    </td>
    <td width="50%">
     uniCenta oPOS funciona con MySQL Server v5.7.x. AMPPS v3.8 contiene MySQL Server v5.6.37 y puede aparecer una advertencia:
    </td>
  </tr>
</table>

<div align="center">
  <img width="80%" src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/ampps.png" width="80%" height="80%">
</div>

#### Content of Package for Linux

- [megatools](https://megatools.megous.com/)
- [Oracle Java SE v8.x](https://www.oracle.com/co/java/technologies/javase/javase8-archive-downloads.html)
- [AMPPS v3.8](https://ampps.com/downloads/)

### uniCenta oPOS Package for Linux - No Java

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniopos_test.png">
</div>

#### How to Use uniCenta oPOS Package for Linux - No Java

```shell
wget -c -q https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/scripts/uniopos_nojava.sh
sed -i "s:your_user:$USER:g" uniopos_nojava.sh
sudo chmod +x uniopos_nojava.sh
sudo ./uniopos_nojava.sh
```

#### Content of uniCenta oPOS Package for Linux - No Java

- [megatools](https://megatools.megous.com/)
- [LAMP v7.1.33-0 x64 (Bitnami)](https://bitnami.com/stack/lamp)
- [uniCenta oPOS Beta v5.0.1 (.deb)](https://unicenta.com/downloads/downloads/)

#### Important About uniCenta oPOS Package for Linux - No Java

<table width="100%">
  <tr>
    <td width="50%">
     Once you start uniCenta oPOS Beta v5.0.1, in the library you must replace the line:
    </td>
    <td width="50%">
     Una vez inicie uniCenta oPOS Beta v5.0.1, en la librería debe reemplazar la línea:
    </td>
  </tr>
</table>

```shell
/home/user/./mysql-connector-java-5.1.39.jar
# by: / por:
/opt/unicentaopos/lib/app/lib/mysql-connector-java-5.1.39.jar
```

<div align="center">
  <img width="80%" src="https://raw.githubusercontent.com/maravento/vault/master/uniopos/resources/img/uniopos_test_connected.png" width="80%" height="80%">
</div>

## Packages and Tools Used

---

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [AMPPS v3.8 x64 (Softaculous)](http://www.ampps.com/downloads)
- [Fart-It](https://sourceforge.net/projects/fart-it/files/)
- [HeidiSQL](https://www.heidisql.com/download.php)
- [LAMP v7.1.33-0 x64 (Bitnami)](https://bitnami.com/stack/lamp)
- [megatools](https://megatools.megous.com/)
- [MySQL Server (no-install package .zip)](https://dev.mysql.com/downloads/mysql/5.7.html#downloads/)
- [Oracle Java 8](https://www.java.com/en/download/manual.jsp)
- [Oracle Java SE 1.8.0_212 (PPA: Hellenic Schools Technical Support Team)](https://launchpad.net/~ts.sch.gr/+archive/ubuntu/ppa)
- [Relative shortcuts for Windows](https://www.csparks.com/Relative/index.html)
- [Resource Turner](http://www.restuner.com/)
- [uniCenta oPOS](https://unicenta.com/download-files/installers/)
- [Uniform Zero (UZero)](https://sourceforge.net/projects/miniserver/files/)
- [vcredist](https://github.com/abbodi1406/vcredist/releases)
- [WampServer](https://wampserver.aviatechno.net/?lang=en)
- [Webmin (Optional)](https://www.webmin.com/)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

## End-of-Life (EOL) | End-of-Support (EOS)

---

<table width="100%">
  <tr>
    <td width="50%">
     This project has reached EOL - EOS. No longer supported or updated.
    </td>
    <td width="50%">
     Este proyecto a alcanzado EOL - EOS. Ya no cuenta con soporte o actualizaciones.
    </td>
  </tr>
</table>

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
     Maravento Studio has no relationship with the developers of uniCenta OPOS. We also don't use it, we don't promote it, and we don't provide support. Maravento Studio only supports the uniOPOS installer, which is an open source project, sponsored by <a href="https://co.linkedin.com/in/lancord)" target="_blank">UuniOPOS SAS</a>. Only the sponsor of this installer may use it for commercial purposes.
    </td>
    <td width="50%">
     Maravento Studio no tiene ninguna relación con los desarrolladores de uniCenta OPOS. Tampoco lo usamos, no lo promocionamos y no brindamos soporte. Maravento Studio solo brinda soporte al instalador uniOPOS, que es un proyecto de código abierto, patrocinado por <a href="https://co.linkedin.com/in/lancord)" target="_blank">uniOPOS SAS</a>. Solo el patrocinador de este instalador, podrá usarlo con fines comerciales.
    </td>
  </tr>
</table>
