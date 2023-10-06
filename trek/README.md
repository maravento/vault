# [Trek](https://www.maravento.com)

[![status-frozen](https://img.shields.io/badge/status-frozen-blue.svg)](https://github.com/maravento/vault)

**Trek** is an experimental SQL database rescue tool. It is used when there is damage to the software, which prevents exporting by traditional methods.

**Trek** es una herramienta experimental de rescate de bases de datos SQL. Se usa cuando hay daños en el software, que impiden exportarlas por métodos tradicionales.

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/trek"
```

## DATA SHEET

---

|File|OS|Size|
| :---: | :---: | :---: |
|[trek.exe (.zip)](https://raw.githubusercontent.com/maravento/vault/master/trek/trek.zip)|Windows 7/8/10 x86 x64|3.6 MB|

## HOW TO USE

---

Disable your Antivirus, Antimalware, SmartScreen or any other security solution in your Operating System, close all windows and check the date and time of your PC is correct. Unzip `trek.exe` (.zip) to your desktop, execute it with double click (accept privileged execution) and follow the instructions on the screen

Desactive su Antivirus, Antimalware, SmartScreen o cualquier otra solución de seguridad en su Sistema Operativo, cierre todas las ventanas y verifique la fecha y hora de su PC sea la correcta. Descomprima `trek.exe` (.zip) en el escritorio, ejecutarlo con doble clic (acepte la ejecución con privilegios) y siga las instrucciones en pantalla

### DUMP/RAW SELECTOR

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_selector.png)](https://www.maravento.com)

**DUMP** option exports/imports MySQL databases in `.sql` format / La opción **DUMP** exporta/importa bases de datos MySQL en formato `.sql`

**RAW** option exports/imports raw MySQL databases (`\mysql(%version%)\data` folder) / La opción **RAW** exporta/importa bases de datos MySQL en crudo (carpeta `\mysql(%version%)\data`)

### MySQL DUMP

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_ini.png)](https://www.maravento.com)

#### BACKUP

Pressing BACKUP will export the database with the extension `.sql` and the following window will appear requesting the MySQL connection data: / Al presionar BACKUP, exportará la base de datos con extensión `.sql` y saldrá la siguiente ventana solicitando los datos de conexión a MySQL:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_backup.png)](https://www.maravento.com)

Complete the fields, with your username, password and name of the database to export. Upon completion, the `.sql` output file will be saved to the TrekDump folder, dbnamed-date-time (Ex: `c:\TrekDump\mydbname_2021_08_26_09_48_26.sql`). Check the `error.txt` file to see if there were any errors during the process. / Complete los campos, con su usuario, contraseña y nombre de la base de datos a exportar. Al terminar, el archivo de salida `.sql` se guardará en la carpeta TrekDump, con el nombredb-fecha-hora (Ej: `c:\TrekDump\mydbname_2021_08_26_09_48_26.sql`). Verifique el archivo `error.txt` para conocer si hubo algún error durante el proceso.

When finished, the following message will appear: / Al terminar, saldrá el siguiente mensaje:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_backup_end.png)](https://www.maravento.com)

#### RESTORE

Pressing RESTORE will import the database with the `.sql` extension and the following window will appear, requesting the location where the file to import is saved, with the `.sql` extension: / Al presionar RESTORE, importará la base de datos con extensión `.sql` y saldrá la siguiente ventana, solicitando la ubicación donde tiene guardado el archivo a importar, con extensión `.sql`:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_sql_file.png)](https://www.maravento.com)

After selecting the `.sql` file, the following window will appear requesting the connection data to MySQL: / Después de seleccionar el archivo `.sql`, saldrá la siguiente ventana solicitando los datos de conexión a MySQL:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_restore.png)](https://www.maravento.com)

Complete the fields, with your username, password and dbname to import. / Complete los campos, con su usuario, contraseña y nombredb a importar.

When finished, the following message will appear: / Al terminar saldrá el siguiente mensaje:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_restore_end.png)](https://www.maravento.com)

#### IMPORTANT BEFORE USE DUMP OPTION

- The MySQL service must be running, before using the DUMP options. / El servicio de MySQL debe estar ejecutándose, antes de usar las opciones de DUMP.
- To use the DUMP options you must create a username and password with maximum privileges. The use of the `root` user is not recommended. / Para usar las opciones de DUMP debe crear un usuario y contraseña con máximos privilegios. No se recomienda el uso del usuario `root`.
- the `.sql` file to import must not contain spaces and/or special characters. / El archivo `.sql` a importar no debe contener espacios y/o caracteres especiales.
- If the `.sql` file to import exceeds the maximum size allowed parameter, the error `ERROR 2006 (HY000) at line NUMBER: MySQL server has gone away` will be output (this will not be displayed in Trek). To fix this, increase the value in the `max_allowed_packet` parameter of the `my.cnf` or `my.ini` file, depending on which stack you are using. Example: / Si el archivo `.sql` a importar excede el tamaño máximo permitido saldrá el error `ERROR 2006 (HY000) at line NUMBER: MySQL server has gone away` (este no se mostrará en Trek). Para solucionarlo, incremente el tamaño máximo permitido en el parámetro `max_allowed_packet` del archivo `my.cnf` o `my.ini`, en dependencia del stack que utilice. Ejemplo:

  ```shell
  max_allowed_packet = 100M
  ```

- If the `.sql` file to be imported contains a database (CREATE DATABASE statement), a new database will not be created and the existing one will be kept. Otherwise it will be created. / Si el archivo `.sql` a importar contiene una base de datos (CREATE DATABASE statement), no se creará una nueva base de datos y se conservará la existente. Caso contrario se creará.

  ```shell
  A database already exists in the file: dbfile.sql
  The database will not be created: dbname
  # or
  There is no database in the file: dbfile.sql
  The database will be created: dbname
  ```

- MySQL will display a warning notice during the process. This is because you entered the password on the command line to be able to do the BACKUP or RESTORE. / MySQL mostrará un aviso de advertencia durante el proceso. Esto se debe a que introdujo la contraseña en línea de comandos para poder hacer el BACKUP o RESTORE.

  [![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_dump_warning.png)](https://www.maravento.com)

### MySQL RAW

[![Image](https://raw.githubusercontent.com/maravento/vault/master/trek/img/trek_raw_ini.png)](https://www.maravento.com)

MySQL RAW copies SQL databases, their structure and associated files from `\mysql-%version%\data` to `%HOMEDRIVE%\TrekRAW` folder, using BACKUP option and vice versa, with RESTORE option / MySQL RAW copia las bases de datos MySQL, su estructura y archivos asociados de las carpetas `\mysql-%version%\data`, a la carpeta `%HOMEDRIVE%\TrekRAW`, usando la opción BACKUP y viceversa, con la opcion RESTORE

You must select the MySQL folder to be able to perform the BACKUP or RESTORE. Example: / Usted deberá seleccionar la carpeta MySQL para poder realizar BACKUP o RESTORE. Ejemplo:

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

- When you finish running BACKUP or RESTORE, you must start MySQL Server service manually / Al terminar la ejecución de BACKUP or RESTORE, usted debe iniciar el servicio MySQL Server manualmente
- When using the BACKUP or RESTORE options, when they finish, you should refer to the `Trek.txt` file on your desktop / Al usar las opciones BACKUP o RESTORE, cuando finalicen, debe consultar el archivo `Trek.txt` en su escritorio
- Do not use this tool to migrate or restore databases with different structures / No use esta herramienta para migrar o restaurar bases de datos con estructuras diferentes
- MySQL RAW option uses the [Robust File Copy](https://es.wikipedia.org/wiki/Robocopy) tool, which has some limitations and may not obtain the desired results. Use at your own risk / La opción MySQL RAW utiliza la herramienta [Robust File Copy](https://es.wikipedia.org/wiki/Robocopy), la cual tiene algunas limitaciones y puede no obtener los resultados deseados. Úsela bajo su propio riesgo
- MySQL RAW option excludes SSL related files (.pem), because these are unique, so after using the RESTORE option, you may have issues with access or content if it was encrypted with an SSL certificate. More information [HERE](https://dba.stackexchange.com/a/267757/208609) / La opción MySQL RAW excluye los archivos relacionados con SSL (*.pem), debido a que estos son únicos, por tanto después de usar la opción RESTORE, puede tener problemas con el acceso o contenido si estaba cifrado con un certificado SSL. Más información [AQUI](https://dba.stackexchange.com/a/267757/208609)
- When you start Trek, it automatically creates the TrekRAW folder on your HOMEDRIVE (ex: `c:\TrekRAW`). All actions are performed within this folder (BACKUP or RESTORE), therefore your input or output files should be in this folder. / Cuando inicia Trek, automáticamente crea la carpeta TrekRAW en su HOMEDRIVE (ej: `c:\TrekRAW`). Todas las acciones se realizan dentro de esta carpeta (BACKUP o RESTORE), por tanto sus archivos de entrada o salida, deberán estar en esta carpeta.

## PACKAGES AND TOOLS

---

- [7zSFX Builder](https://sourceforge.net/projects/s-zipsfxbuilder/)
- [MySQL Dump](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html)
- [Resource Turner](http://www.restuner.com/)
- [Robust File Copy](https://docs.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy)
- [stahlworks ZipUnzip](http://stahlworks.com/dev/index.php?tool=zipunzip)
- [WinZenity](https://github.com/maravento/vault/tree/master/winzenity)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
