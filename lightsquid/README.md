# [Lightsquid](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://lightsquid.sourceforge.net/)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     <b>Lightsquid</b> is a webapp that works exclusively with <a href="https://www.squid-cache.org/" target="_blank">Squid-Cache</a>, extracting from <code>access.log</code> the necessary data to show the traffic statistics of the local network.
    </td>
    <td width="50%">
     <b>Lightsquid</b> es una webapp que trabaja exclusivamente con <a href="https://www.squid-cache.org/" target="_blank">Squid-Cache</a>, extrayendo de <code>access.log</code> los datos necesarios para mostrar las estadísticas del tráfico de la red local.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/lightsquid
```

## DATA SHEET

---

| Last Official Version | Unofficial Update | Theme | HowTo | Teste on |
| :-------------------: | :---------------: | :---: | :---: | :------: |
| [v1.8-7 (2009)](https://lightsquid.sourceforge.net/) | [v1.8.1 (2021)](https://github.com/finisky/lightsquid-1.8.1) | [Metro (2020)](https://www.sysadminsdecuba.com/2020/09/lightsquid/) | [Post (SP-ES)](https://www.maravento.com/2022/10/lightsquid.html) | Ubuntu 22.04 LTS x64 |

### Important Before Using

<table width="100%">
  <tr>
    <td width="50%">
     - If any IP addresses on your local network do not go through the Squid proxy, then they will not appear in the reports.
    </td>
    <td width="50%">
     - Si alguna dirección IP de su red local no pasan por el proxy Squid, entonces no aparecerá en los reportes.
    </td>
  </tr>
  <tr>
    <td width="50%">
     - This project is not a Next Generation (NG) version. It is a fork of the unofficial version <a href="https://github.com/finisky/lightsquid-1.8.1" target="_blank">v1.8.1</a>, updated with <a href="https://github.com/finisky/lightsquid-1.8.1/issues/1" target="_blank">fixes</a>.
    </td>
    <td width="50%">
     - Este proyecto no es una versión de Nueva Generación (NG). Es un fork de la versión no oficial <a href="https://github.com/finisky/lightsquid-1.8.1" target="_blank">v1.8.1</a>, actualizado con <a href="https://github.com/finisky/lightsquid-1.8.1/issues/1" target="_blank">correcciones</a>.
    </td>
  </tr>
</table>

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

<table width="100%">
  <tr>
    <td width="50%">
     The LightSquid install script runs a command that by default schedules the crontab to run lightsquid every 10 seconds and bandata every 12 seconds. You can adjust it according to your preferences.
    </td>
    <td width="50%">
     El script de instalación de LightSquid ejecuta un comando que programa por defecto en el crontab la ejecución de lightsquid cada 10 segundos y de bandata cada 12 segundos. Puede ajustarlo según sus preferencias.
    </td>
  </tr>
</table>

```bash
*/10 * * * * /var/www/lightsquid/lightparser.pl today
*/12 * * * * /etc/init.d/bandata.sh"
```

### Scan Users

**To scan your users, choose your network range. e.g.: | Para escanear sus usuarios, elija su rango de red. ej:**

```bash
sudo nbtscan 192.168.1.0/24
```

### Parameters

**To run it for the first time: | Para ejecutarlo por primera vez:**

```bash
sudo /var/www/lightsquid/lightparser.pl
```

**To run it manually: | Para ejecutarlo manualmente:**

```bash
sudo /var/www/lightsquid/lightparser.pl today
```

**To add users: | Para agregar usuarios:**

```bash
sudo nano /var/www/lightsquid/realname.cfg
# example:
192.168.1.2 Client1
192.168.1.3 CEO
```

**To exclude users: | Para excluir usuarios:**

```bash
sudo nano /var/www/lightsquid/skipuser.cfg
# example
192.168.1.1
```

**To modify the default theme Metro: | Para modificar el tema por defecto Metro:**

```bash
sudo nano /var/www/lightsquid/lightsquid.cfg
# choose theme (default "metro")
#$templatename        ="base";
$templatename        ="metro_tpl";
```

## BAN DATA (Optional)

---

<table width="100%">
  <tr>
    <td width="50%">
     This section is to block users who have overcome the consumption of data default by the sysadmin.
    </td>
    <td width="50%">
     Esta sección es para bloquear a los usuarios que hayan superado el consumo de datos predeterminado por el sysadmin.
    </td>
  </tr>
</table>

**To run it manually: | Para ejecutarlo manualmente:**

```bash
sudo /etc/init.d/bandata.sh
```

**Replace localnet interface (installation script does the replacement): | Reeplace su interface de red local (el script de instalación hace el reemplazo):**

```bash
sudo nano /etc/init.d/bandata.sh
# replace localnet interface (enpXsX)
lan=eth1
```

**To check the banned IPs: | Para verificar las IPs baneadas:**

```bash
cat /etc/acl/{banmonth,banweek,banday}.txt | uniq
```

### Data Limit

<table width="100%">
  <tr>
    <td width="50%">
     You can use GBytes, MBytes or Bytes, for example 0.5G or 512M or 536870912. By default, the consumption limit values are: 1 Gigabyte (1G) daily data, 5 Gigabyte (5G) weekly data and 20 Gigabyte (20G ) monthly data.
    </td>
    <td width="50%">
     Puede usar GBytes, MBytes o Bytes, por ejemplo 0.5G o 512M o 536870912. Por defecto, los valores del límite de consumo son: 1 Gigabyte (1G) de datos diarios, 5 Gigabyte (3G) de datos semanal y 20 Gigabyte (20G) de datos mensual.
    </td>
  </tr>
</table>

#### By Day

<table width="100%">
  <tr>
    <td width="50%">
     The script checks the Lightsquid current day report and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next day.
    </td>
    <td width="50%">
     El script verifica el informe del día actual de Lightsquid y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará al día siguiente.
    </td>
  </tr>
</table>

**To change the daily data limit in `bandata.sh`: | Para cambiar el límite de datos diario en `bandata.sh`:**

```bash
max_bandwidth_day="1G"
```

#### By Week

<table width="100%">
  <tr>
    <td width="50%">
     The script checks that it is Monday and the previous week's reports from Lightsquid, and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next Monday.
    </td>
    <td width="50%">
     El script verifica que sea Lunes y los informes de la semana anterior de Lightsquid, y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará el lunes siguiente.
    </td>
  </tr>
</table>

**To change the weekly data limit in `bandata.sh` | Para cambiar el límite de datos semanal en `bandata.sh`:**

```bash
max_bandwidth_week="5G"
```

#### By Month

<table width="100%">
  <tr>
    <td width="50%">
     The script checks the current month's reports from Lightsquid and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next month.
    </td>
    <td width="50%">
     El script verifica los informes del mes actual de Lightsquid y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará al mes siguiente.
    </td>
  </tr>
</table>

**To change the monthly data limit in `bandata.sh` | Para cambiar el límite de datos mensual en `bandata.sh`:**

```bash
max_bandwidth_month="20G"
```

### Data Statistics

<table width="100%">
  <tr>
    <td width="50%">
     Traffic statistics are displayed in the web application and also users who exceeded the limit. To change the data limit in </code>lightsquid.cfg</code> statistics:
    </td>
    <td width="50%">
     Las estadísticas del tráfico se muestran en la aplicación web y también los usuarios que sobrepasaron el límite. Para cambiar el límite de datos en las estadísticas de </code>lightsquid.cfg</code>:
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/lightsquid/lightsquid.cfg
```

**And modify the following line: | Y modificar la siguiente línea:**

```bash
#user maximum size per day limit (oversize)
$perusertrafficlimit = 1000*1024*1024;
```

**Nomenclature:** 10 = 10 MBytes, 512 = 512 Mbytes, 1000 = 1 Gbytes...

**By default it comes in 1000. Do not modify the value 1024. | Por defecto viene en 1000. No modifique el valor 1024.**

### Reports (Optional)

<table width="100%">
  <tr>
    <td width="50%">
     LightSquid can generate reports in PDF, CSV, etc., but it will only show the TOP domains. If you want all visited domains on your local network in a single ACL, suitable for Squid, run the following command:
    </td>
    <td width="50%">
     LightSquid puede generar reportes en PDF, CSV, etc., pero solo mostrará los dominios TOP. Si quiere todos los dominios visitados de su red local en una sola ACL, apta para Squid, ejecute el siguiente comando:
    </td>
  </tr>
</table>

```bash
find /var/www/lightsquid/report -type f -name '[0-9]*.[0-9]*.[0-9]*.[0-9]*' -exec grep -oE '[[:alnum:]_.-]+\.([[:alnum:]_.-]+)+' {} \; | sed 's/^\.//' | sed -r 's/^(www|ftp|ftps|ftpes|sftp|pop|pop3|smtp|imap|http|https)\.//g' | sed -r '/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/d' | tr -d ' ' | awk '{print "." $1}' | sort -u > sites.txt
```

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
