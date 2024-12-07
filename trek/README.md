# [Trek](https://www.maravento.com)

[![status-frozen](https://img.shields.io/badge/status-frozen-blue.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     <b>Trek</b> is a SQL database rescue tool. It is used when there is damage to the software, which prevents it from being exported by traditional methods.
    </td>
    <td width="50%">
     <b>Trek</b> es una herramienta de rescate de bases de datos SQL. Se usa cuando hay daños en el software, que impiden exportarlas por métodos tradicionales.
    </td>
  </tr>
</table>

## DATA SHEET

---

|File|OS|Size|
| :---: | :---: | :---: |
|[trek.exe (.zip)](https://raw.githubusercontent.com/maravento/vault/master/trek/trek.zip)|Windows 7/10 x86 x64|3.6 MB|

## HOW TO USE

---

<table width="100%">
  <tr>
    <td width="50%">
     Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip <code>Trek.exe (.zip)</code> to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen.
    </td>
    <td width="50%">
     Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima <code>Trek.exe (.zip)</code> en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla.
    </td>
  </tr>
</table>

### DUMP/RAW SELECTOR

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_selector.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     <b>DUMP</b> option exports/imports MySQL databases in <code>.sql</code> format.
    </td>
    <td width="50%">
     La opción <b>DUMP</b> exporta/importa bases de datos MySQL en formato <code>.sql</code>.
    </td>
  </tr>
  <tr>
    <td width="50%">
     <b>RAW</b> option exports/imports raw MySQL databases (<code>\mysql(%version%)\data</code> folder).
    </td>
    <td width="50%">
     La opción <b>RAW</b> exporta/importa bases de datos MySQL en crudo (carpeta <code>\mysql(%version%)\data</code>).
    </td>
  </tr>  
</table>

### MySQL DUMP

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_ini.png)](https://www.maravento.com)

#### BACKUP

<table width="100%">
  <tr>
    <td width="50%">
     Pressing <b>BACKUP</b> will export the database with the extension <code>.sql</code> and the following window will appear requesting the MySQL connection data:
    </td>
    <td width="50%">
     Pressing <b>BACKUP</b> will export the database with the extension <code>.sql</code> and the following window will appear requesting the MySQL connection data:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_backup.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     Complete the fields, with your username, password and name of the database to export. Upon completion, the <code>.sql</code> output file will be saved to the TrekDump folder, dbnamed-date-time (Ex: <code>c:\TrekDump\mydbname_2021_08_26_09_48_26.sql</code>). Check the <code>error.txt</code> file to see if there were any errors during the process. When finished, the following message will appear:
    </td>
    <td width="50%">
     Complete los campos, con su usuario, contraseña y nombre de la base de datos a exportar. Al terminar, el archivo de salida <code>.sql</code> se guardará en la carpeta TrekDump, con el nombredb-fecha-hora (Ej: <code>c:\TrekDump\mydbname_2021_08_26_09_48_26.sql</code>). Verifique el archivo <code>error.txt</code> para conocer si hubo algún error durante el proceso. Al terminar, saldrá el siguiente mensaje:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_backup_end.png)](https://www.maravento.com)

#### RESTORE

<table width="100%">
  <tr>
    <td width="50%">
     Pressing <b>RESTORE</b> will import the database with the <code>.sql</code> extension and the following window will appear, requesting the location where the file to import is saved, with the <code>.sql</code> extension:
    </td>
    <td width="50%">
     Al presionar <b>RESTORE</b>, importará la base de datos con extensión <code>.sql</code> y saldrá la siguiente ventana, solicitando la ubicación donde tiene guardado el archivo a importar, con extensión <code>.sql</code>:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_sql_file.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     After selecting the <code>.sql</code> file, the following window will appear requesting the connection data to MySQL:
    </td>
    <td width="50%">
     Después de seleccionar el archivo <code>.sql</code>, saldrá la siguiente ventana solicitando los datos de conexión a MySQL:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_restore.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     Complete the fields, with your username, password and dbname to import. When finished, the following message will appear:
    </td>
    <td width="50%">
     Complete los campos, con su usuario, contraseña y nombredb a importar. Al terminar saldrá el siguiente mensaje:
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_restore_end.png)](https://www.maravento.com)

#### IMPORTANT BEFORE USE DUMP OPTION

<table width="100%">
  <tr>
    <td width="50%">
     - The MySQL service must be running, before using the DUMP options.
    </td>
    <td width="50%">
     - El servicio de MySQL debe estar ejecutándose, antes de usar las opciones de DUMP.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - To use the DUMP options you must create a username and password with maximum privileges. The use of the <code>root</code> user is not recommended.
    </td>
    <td width="50%">
     - Para utilizar las opciones de DUMP es necesario crear un usuario y contraseña con privilegios máximos. No se recomienda el uso del usuario <code>root</code>.
    </td>
  </tr>
    <td width="50%">
     - The <code>.sql</code> file to be imported must not contain spaces and/or special characters.
    </td>
    <td width="50%">
     - El archivo <code>.sql</code> a importar no debe contener espacios y/o caracteres especiales.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - If the <code>.sql</code> file to import exceeds the maximum size allowed parameter, the error <code>ERROR 2006 (HY000) at line NUMBER: MySQL server has gone away</code> will be output (this will not be displayed in Trek). To fix this, increase the value in the <code>max_allowed_packet</code> parameter of the <code>my.cnf</code> or <code>my.ini</code> file, depending on which stack you are using. Example:
    </td>
    <td width="50%">
     - Si el archivo <code>.sql</code> a importar excede el tamaño máximo permitido saldrá el error <code>ERROR 2006 (HY000) at line NUMBER: MySQL server has gone away</code> (este no se mostrará en Trek). Para solucionarlo, incremente el tamaño máximo permitido en el parámetro <code>max_allowed_packet</code> del archivo <code>my.cnf</code> o <code>my.ini</code>, en dependencia del stack que utilice. Ejemplo:
    </td>
  </tr>
</table>

  ```shell
  max_allowed_packet = 100M
  ```

<table width="100%">
  <tr>
    <td width="50%">
     - If the <code>.sql</code> file to be imported contains a database (CREATE DATABASE statement), a new database will not be created and the existing one will be kept. Otherwise it will be created.
    </td>
    <td width="50%">
     - Si el archivo </code>.sql</code> a importar contiene una base de datos (CREATE DATABASE statement), no se creará una nueva base de datos y se conservará la existente. Caso contrario se creará.
    </td>
  </tr>
</table>

  ```shell
  A database already exists in the file: dbfile.sql
  The database will not be created: dbname
  # or
  There is no database in the file: dbfile.sql
  The database will be created: dbname
  ```

<table width="100%">
  <tr>
    <td width="50%">
     - MySQL will display a warning notice during the process. This is because you entered the password on the command line to be able to do the BACKUP or RESTORE.
    </td>
    <td width="50%">
     - MySQL mostrará un aviso de advertencia durante el proceso. Esto se debe a que introdujo la contraseña en línea de comandos para poder hacer el BACKUP o RESTORE.
    </td>
  </tr>
</table>

  [![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_warning.png)](https://www.maravento.com)

### MySQL RAW

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_raw_ini.png)](https://www.maravento.com)

<table width="100%">
  <tr>
    <td width="50%">
     MySQL RAW copies SQL databases, their structure and associated files from <code>\mysql-%version%\data</code> to <code>%HOMEDRIVE%\TrekRAW</code> folder, using BACKUP option and vice versa, with RESTORE option. You must select the MySQL folder to be able to perform the BACKUP or RESTORE. Example:
    </td>
    <td width="50%">
     MySQL RAW copia las bases de datos MySQL, su estructura y archivos asociados de las carpetas <code>\mysql-%version%\data</code>, a la carpeta <code>%HOMEDRIVE%\TrekRAW</code>, usando la opción BACKUP y viceversa, con la opcion RESTORE. Usted deberá seleccionar la carpeta MySQL para poder realizar BACKUP o RESTORE. Ejemplo:
    </td>
  </tr>
  <tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_raw_folder.png)](https://www.maravento.com)

#### Most Common Paths to MySQL Folder: / Rutas más Comunes a la Carpeta MySQL

```shell
Wamp: \wamp64\bin\mysql\mysql(version)
Xamp: \xampp\mysql
UZero: \UniServerZ\core\mysql
MySQL Server (no-install package .zip): \mysql\mysql(version)
MySQL (Community Server): \Program Files\MySQL\MySQL(version)
```

#### IMPORTANT BEFORE USE RAW OPTION

<table width="100%">
  <tr>
    <td width="50%">
     - When you finish running BACKUP or RESTORE, you must start MySQL Server service manually.
    </td>
    <td width="50%">
     - Al terminar la ejecución de BACKUP or RESTORE, usted debe iniciar el servicio MySQL Server manualmente.
    </td>
  </tr>
    <td width="50%">
     - When using the BACKUP or RESTORE options, when they finish, you should refer to the <code>Trek.txt</code> file on your desktop.
    </td>
    <td width="50%">
     - Al usar las opciones BACKUP o RESTORE, cuando finalicen, debe consultar el archivo <code>Trek.txt</code> en su escritorio.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - Do not use this tool to migrate or restore databases with different structures.
    </td>
    <td width="50%">
     - No use esta herramienta para migrar o restaurar bases de datos con estructuras diferentes.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - MySQL RAW option uses the <a href="https://es.wikipedia.org/wiki/Robocopy" target="_blank">Robust File Copy</a> tool, which has some limitations and may not obtain the desired results. Use at your own risk.
    </td>
    <td width="50%">
     - La opción MySQL RAW utiliza la herramienta <a href="https://es.wikipedia.org/wiki/Robocopy" target="_blank">Robust File Copy</a>, la cual tiene algunas limitaciones y puede no obtener los resultados deseados. Úsela bajo su propio riesgo.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - MySQL RAW option excludes SSL related files (.pem), because these are unique, so after using the RESTORE option, you may have issues with access or content if it was encrypted with an SSL certificate. More information <a href="https://dba.stackexchange.com/a/267757/208609" target="_blank">HERE</a>.
    </td>
    <td width="50%">
     - La opción MySQL RAW excluye los archivos relacionados con SSL (*.pem), debido a que estos son únicos, por tanto después de usar la opción RESTORE, puede tener problemas con el acceso o contenido si estaba cifrado con un certificado SSL. Más información <a href="https://dba.stackexchange.com/a/267757/208609" target="_blank">AQUI</a>.
    </td>
  </tr>
    <td width="50%">
     - When you start Trek, it automatically creates the TrekRAW folder on your HOMEDRIVE (ex: <code>c:\TrekRAW</code>). All actions are performed within this folder (BACKUP or RESTORE), therefore your input or output files should be in this folder.
    </td>
    <td width="50%">
     - Cuando inicia Trek, automáticamente crea la carpeta TrekRAW en su HOMEDRIVE (ej: <code>c:\TrekRAW</code>). Todas las acciones se realizan dentro de esta carpeta (BACKUP o RESTORE), por tanto sus archivos de entrada o salida, deberán estar en esta carpeta.
    </td>
  </tr>
</table>

## PACKAGES AND TOOLS

---

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [MySQL Dump](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)
- [Resource Turner](http://www.restuner.com/)
- [Robust File Copy](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [stahlworks ZipUnzip](http://stahlworks.com/dev/index.php?tool=zipunzip)
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
