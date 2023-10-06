# [Lightsquid](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://lightsquid.sourceforge.net/)

**Lightsquid** is a webapp that works exclusively with [Squid-Cache](https://www.squid-cache.org/), extracting from `access.log` the necessary data to show the traffic statistics of the local network.

**Lightsquid** es una webapp que trabaja exclusivamente con [Squid-Cache](https://www.squid-cache.org/), extrayendo de `access.log` los datos necesarios para mostrar las estadísticas del tráfico de la red local.

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/lightsquid"
```

## DATA SHEET

---

| Developer | Fork | Theme | HowTo |
| :-------: | :--: | :---: | :---: |
| [v1.8-7 (2009)](https://lightsquid.sourceforge.net/) | [v1.8.1 (2021)](https://github.com/finisky/lightsquid-1.8.1) | [Metro (2020)](https://www.sysadminsdecuba.com/2020/09/lightsquid/) | [Post (ESP)](https://www.maravento.com/2022/10/lightsquid.html) |

### Important before using

- This project is a fork of [v1.8.1](https://github.com/finisky/lightsquid-1.8.1), updated with [fixes](https://github.com/finisky/lightsquid-1.8.1/issues/1) / Este proyecto es un fork de [v1.8.1](https://github.com/finisky/lightsquid-1.8.1), actualizado con [correcciones](https://github.com/finisky/lightsquid-1.8.1/issues/1).
- If any IP addresses on your local network do not go through the Squid proxy, then they will not appear in the reports. / Si alguna dirección IP de su red local no pasan por el proxy Squid, entonces no aparecerá en los reportes.
- Tested on: / Probado en: Ubuntu 22.04 LTS x64.

## HOW TO INSTALL

---

```bash
wget -c https://raw.githubusercontent.com/maravento/vault/master/lightsquid/lsinstall.sh && sudo chmod +x lsinstall.sh && sudo ./lsinstall.sh
```

## HOW TO USE

---

### Access

[http://localhost/lightsquid/index.cgi](http://localhost/lightsquid/index.cgi)

[![Image](https://raw.githubusercontent.com/maravento/vault/master/lightsquid/lightsquid.png)](https://www.maravento.com/)

### Crontab

The LightSquid install script runs a command that by default schedules the crontab to run lightsquid every 10 seconds and bandata every 12 seconds. You can adjust it according to your preferences. / El script de instalación de LightSquid ejecuta un comando que programa por defecto en el crontab la ejecución de lightsquid cada 10 segundos y de bandata cada 12 segundos. Puede ajustarlo según sus preferencias.

```bash
*/10 * * * * /var/www/lightsquid/lightparser.pl today
*/12 * * * * /etc/init.d/bandata.sh"
```

### Scan Users

To scan your users, choose your network range. e.g.: / Para escanear sus usuarios, elija su rango de red. ej:

```bash
sudo nbtscan 192.168.1.0/24
```

### Parameters

**To run it for the first time: / Para ejecutarlo por primera vez:**

```bash
sudo /var/www/lightsquid/lightparser.pl
```

**To run it manually: / Para ejecutarlo manualmente:**

To run the script manually: / Para ejecutar el script manualmente:

```bash
sudo /var/www/lightsquid/lightparser.pl today
```

**To add users: / Para agregar usuarios:**

```bash
sudo nano /var/www/lightsquid/realname.cfg
# example:
192.168.1.2 Client1
192.168.1.3 CEO
```

**To exclude users: / Para excluir usuarios:**

```bash
sudo nano /var/www/lightsquid/skipuser.cfg
# example
192.168.1.1
```

**To modify the default theme Metro: / Para modificar el tema por defecto Metro:**

```bash
sudo nano /var/www/lightsquid/lightsquid.cfg
# choose theme (default "metro")
#$templatename        ="base";
$templatename        ="metro_tpl";
```

## BAN DATA (Optional)

---

This section is to block users who have overcome the consumption of data default by the sysadmin. / Esta sección es para bloquear a los usuarios que hayan superado el consumo de datos predeterminado por el sysadmin.

**To run it manually: / Para ejecutarlo manualmente:**

```bash
sudo /etc/init.d/bandata.sh
```

**Replace localnet interface (installation script does the replacement): / Reeplace su interface de red local (el script de instalación hace el reemplazo):**

```bash
sudo nano /etc/init.d/bandata.sh
# replace localnet interface (enpXsX)
lan=eth1
```

**To check the banned IPs: / Para verificar las IPs baneadas:**

```bash
cat /etc/acl/{banmonth,banweek,banday}.txt | uniq
```

### Data Limit

You can use GBytes, MBytes or Bytes, for example 0.5G or 512M or 536870912. By default, the consumption limit values are: 1 Gigabyte (1G) daily data, 5 Gigabyte (5G) weekly data and 20 Gigabyte (20G ) monthly data / Puede usar GBytes, MBytes o Bytes, por ejemplo 0.5G o 512M o 536870912. Por defecto, los valores del límite de consumo son: 1 Gigabyte (1G) de datos diarios, 5 Gigabyte (3G) de datos semanal y 20 Gigabyte (20G) de datos mensual.

#### By Day

The script checks the Lightsquid current day report and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next day. / El script verifica el informe del día actual de Lightsquid y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará al día siguiente.

To change the daily data limit in `bandata.sh`: / Para cambiar el límite de datos diario en `bandata.sh`:

```bash
max_bandwidth_day="1G"
```

#### By Week

The script checks that it is Monday and the previous week's reports from Lightsquid, and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next Monday. / El script verifica que sea Lunes y los informes de la semana anterior de Lightsquid, y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará el lunes siguiente.

To change the weekly data limit in `bandata.sh` / Para cambiar el límite de datos semanal en `bandata.sh`:

```bash
max_bandwidth_week="5G"
```

#### By Month

The script checks the current month's reports from Lightsquid and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next month. / El script verifica los informes del mes actual de Lightsquid y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará al mes siguiente.

To change the monthly data limit in `bandata.sh` / Para cambiar el límite de datos mensual en `bandata.sh`:

```bash
max_bandwidth_month="20G"
```

### Data Statistics

Traffic statistics are displayed in the web application and also users who exceeded the limit. To change the data limit in `lightsquid.cfg` statistics: / Las estadísticas del tráfico se muestran en la aplicación web y también los usuarios que sobrepasaron el límite. Para cambiar el límite de datos en las estadísticas de `lightsquid.cfg`:

```bash
sudo nano /var/www/lightsquid/lightsquid.cfg
```

And modify the following line: / Y modificar la siguiente línea:

```bash
#user maximum size per day limit (oversize)
$perusertrafficlimit = 1000*1024*1024;
```

**Nomenclature:** 10 = 10 MBytes, 512 = 512 Mbytes, 1000 = 1 Gbytes...

By default it comes in 1000. Do not modify the value 1024. / Por defecto viene en 1000. No modifique el valor 1024.

### Reports (Optional)

LightSquid can generate reports in PDF, CSV, etc., but it will only show the TOP domains. If you want all visited domains on your local network in a single ACL, suitable for Squid, run the following command: / LightSquid puede generar reportes en PDF, CSV, etc., pero solo mostrará los dominios TOP. Si quiere todos los dominios visitados de su red local en una sola ACL, apta para Squid, ejecute el siguiente comando:

```bash
find /var/www/lightsquid/report -type f -name '[0-9]*.[0-9]*.[0-9]*.[0-9]*' -exec grep -oE '[[:alnum:]_.-]+\.([[:alnum:]_.-]+)+' {} \; | sed 's/^\.//' | sed -r 's/^(www|ftp|ftps|ftpes|sftp|pop|pop3|smtp|imap|http|https)\.//g' | sed -r '/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/d' | tr -d ' ' | awk '{print "." $1}' | sort -u > sites.txt
```

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
