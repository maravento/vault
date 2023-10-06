# [Stack](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://github.com/maravento/vault)

**Stack** contains stack installation package for linux / **Stack** contiene paquete de instalación stack para Linux

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/stack"
```

## HOW TO USE

---

```bash
wget -q -N https://raw.githubusercontent.com/maravento/vault/master/stack/stack.sh && sudo chmod +x stack.sh && sudo ./stack.sh
```

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/stack/img/setupstack.png" width="60%" height="60%">
</div>

### LAMP

<div align="center">
  <img src="https://raw.githubusercontent.com/maravento/vault/master/stack/img/lamp.png" width="80%" height="80%">
</div>

### AMPPS

<div align="center">
  <img width="80%" src="https://raw.githubusercontent.com/maravento/vault/master/stack/img/ampps.png" width="80%" height="80%">
</div>

### LAMP / AMPPS Default

- Tested on: / probado en: Ubuntu 20.04/22.04 x64
- Default phpMyAdmin: [http://localhost/phpmyadmin](http://localhost/phpmyadmin)

#### Important Before Use LAMP Stack

- Default User **root** and Default Password **lampstack** (change it) / Usuario predeterminado **root** y contraseña predeterminada **lampstack** (cámbiela)
- To connect to MySQL Server you must create a new username/password in phpMyAdmin / Para conectar a MySQL Server debe crear un nuevo usuario/password en phpMyAdmin
- LAMP 7.1.33-0 is the latest released version of the Bitnami Stack for Linux with MySQL 5.7.x. Contains [MySQL Server v5.7.28, PHP v7.1.33, Apache v2.4.41](https://bitnami.com/stack/lamp/installer/changelog.txt) / LAMP 7.1.33-0 es la última versión lanzada de Bitnami Stack para Linux con MySQL 5.7.x. Contiene [MySQL Server v5.7.28, PHP v7.1.33, Apache v2.4.41](https://bitnami.com/stack/lamp/installer/changelog.txt).
- [Bitnami has discontinued support for most native Linux installers as of June 30, 2021](https://blog.bitnami.com/2021/04/amplifying-our-focus-on-cloud-native.html) / [Bitnami ha descontinuado el soporte para la mayoría de los instaladores nativos para Linux a partir del 30 de junio de 2021](https://blog.bitnami.com/2021/04/amplifying-our-focus-on-cloud-native.html)

#### Important Before Use AMPPS Stack

- Default User **root** and Default Password **mysql** (change it) / Usuario predeterminado **root** y contraseña predeterminada **mysql** (cámbiela)
- AMPPS for Linux include: [Softaculous 4.9.3, Apache 2.4.27, OpenSSL 1.0.1t, PHP 7.1.1, PHP 7.0.22, PHP 5.6.31, PHP 5.5.38, PHP 5.4.45 and 5.3.29, ionCube PHP Loader v10.0.0, Xdebug 2.5.5, PERL 5.26.0, Python 3.6.2 with mod_wsgi 4.5.17 module, MySQL 5.6.37, phpMyAdmin 4.4.15.5, SQLite Manager 1.2.4, MongoDB 3.4.7, RockMongo 1.1.7, Pure-FTPd Server 1.0.36](https://www.ampps.com/blog/ampps-3-8/)

### LAMP / AMPPS by Command Line

By command line / Por línea de comandos

```shell
### LAMP ###
# start/stop/restart/status
sudo /opt/bitnami/ctlscript.sh restart mysql
sudo /opt/bitnami/ctlscript.sh restart apache
# kill LAMP app
for process in $(ps -ef | grep -i '[a]pache*\|[m]ysql*\|bitnami'); do sudo killall $process &> /dev/null; done
# remove
sudo /opt/bitnami/uninstall
```

```shell
### AMPPS ###
# start
sudo /usr/local/ampps/apache/bin/httpd
sudo /usr/local/ampps/mysql/bin/mysqld
# kill processes
sudo killall httpd
sudo killall mysqld
# kill ampps app
for process in $(ps -ef | grep -i '[a]pache*\|[m]ysql*\|ampps'); do sudo killall $process &> /dev/null; done
# remove
sudo rm -rf /usr/local/ampps/
```

## CONTENT

---

- [AMPPS v3.8 x64 (Softaculous)](http://www.ampps.com/downloads)
- [LAMP v7.1.33-0 x64 (Bitnami)](https://bitnami.com/stack/lamp)

## EOL

---

This project has reached EOL (End of Life). No longer supported or updated / Este proyecto a alcanzado EOL (End of Life). Ya no cuenta con soporte o actualizaciones

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
