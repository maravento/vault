# [Lightsquid](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://lightsquid.sourceforge.net/)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>Lightsquid</b> is a webapp that works exclusively with <a href="https://www.squid-cache.org/" target="_blank">Squid-Cache</a>, extracting from <code>access.log</code> the necessary data to show the traffic statistics of the local network.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>Lightsquid</b> es una webapp que trabaja exclusivamente con <a href="https://www.squid-cache.org/" target="_blank">Squid-Cache</a>, extrayendo de <code>access.log</code> los datos necesarios para mostrar las estadísticas del tráfico de la red local.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/lightsquid
```

## DATA SHEET

---

| Last Official Version | Unofficial Update | Theme | HowTo |
| :---: | :---: | :---: | :---: |
| [v1.8-7 (2009)](https://lightsquid.sourceforge.net/) | [v1.8.1 (2021)](https://github.com/finisky/lightsquid-1.8.1) | [Metro (2020)](https://www.sysadminsdecuba.com/2020/09/lightsquid/) | [Post (SP-ES)](https://www.maravento.com/2022/10/lightsquid.html) |

### Important Before Using

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     - If any IP addresses on your local network do not go through the Squid proxy, then they will not appear in the reports.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     - Si alguna dirección IP de su red local no pasan por el proxy Squid, entonces no aparecerá en los reportes.
    </td>
  </tr>
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     - This project is not a Next Generation (NG) version. It is a fork of the unofficial version <a href="https://github.com/finisky/lightsquid-1.8.1" target="_blank">v1.8.1</a>, updated with <a href="https://github.com/finisky/lightsquid-1.8.1/issues/1" target="_blank">fixes</a>.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     - Este proyecto no es una versión de Nueva Generación (NG). Es un fork de la versión no oficial <a href="https://github.com/finisky/lightsquid-1.8.1" target="_blank">v1.8.1</a>, actualizado con <a href="https://github.com/finisky/lightsquid-1.8.1/issues/1" target="_blank">correcciones</a>.
    </td>
  </tr>
    <tr>
    <td style="width: 50%; white-space: nowrap;">
     - Tested on Ubuntu 22.04/24.04
    </td>
    <td style="width: 50%; white-space: nowrap;">
     - Probado en Ubuntu 22.04/24.04
    </td>
  </tr>
</table>

## HOW TO INSTALL

---

```bash
wget -c https://raw.githubusercontent.com/maravento/vault/master/lightsquid/install.sh && sudo chmod +x install.sh && sudo ./install.sh
```

Access: [http://localhost/lightsquid/index.cgi](http://localhost/lightsquid/index.cgi)

[![Image](https://raw.githubusercontent.com/maravento/vault/master/lightsquid/img/lightsquid.png)](https://www.maravento.com/)

## HOW TO USE

---

### First Run

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To run it for the first time, open the terminal and run:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para ejecutarlo por primera vez, abra el terminal y ejecute:
    </td>
  </tr>
</table>

```bash
sudo /var/www/lightsquid/lightparser.pl
```

### Error

[![Image](https://raw.githubusercontent.com/maravento/vault/master/lightsquid/img/report.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The first time you open LightSquid in your browser, you may receive an error message. This is because you haven't run the <code>/var/www/lightsquid/lightparser.pl</code> script for the first time, or your LAN traffic hasn't passed through Squid, so there's no data in the <code>/var/www/lightsquid/report</code> folder.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     La primera vez que abra LightSquid en su navegador, puede salir un mensaje de error. Esto se debe a que no ha ejecutado por primera vez el script <code>/var/www/lightsquid/lightparser.pl</code> o el tráfico de su LAN no ha pasado por Squid y, por tanto, no hay datos en la carpeta <code>/var/www/lightsquid/report</code>.
    </td>
  </tr>
</table>

### Parameters

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The LightSquid installation script adds a task to the crontab to run every 10 seconds. You can change it according to your preferences.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script de instalación de LightSquid agrega una tarea al crontab, para que se ejecute cada 10 segundos. Puedes cambiarla según tus preferencias.
    </td>
  </tr>
</table>

```bash
*/10 * * * * /var/www/lightsquid/lightparser.pl today
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     If you want to generate a report immediately, you can run it manually:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Si quiere generar un reporte de inmediato, puede ejecutarlo manualmente:
    </td>
  </tr>
</table>

```bash
sudo /var/www/lightsquid/lightparser.pl today
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To add users:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para agregar usuarios:
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/lightsquid/realname.cfg
# example:
192.168.1.2 Client1
192.168.1.3 CEO
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To exclude users:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para excluir usuarios:
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/lightsquid/skipuser.cfg
# example
192.168.1.1
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To scan the devices on your local network, choose any of the following commands along with your network's IP range. e.g.:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para escanear los dispositivos de su red local, elija cualquiera de estos comandos y el rango de IP de su red. ej:
    </td>
  </tr>
</table>

```bash
# Install required tools
sudo apt install -y nbtscan nmap arp-scan nast sudo netdiscover
# Run the following commands to scan your local network:
# 1. Using nbtscan
sudo nbtscan 192.168.1.0/24
# 2. Using nmap
sudo nmap -sn 192.168.1.0/24
# 3. Using arp-scan
sudo arp-scan --localnet
# 4. Using nast
sudo nast -m
# 5. Using netdiscover
sudo netdiscover
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To modify the default theme Metro:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para modificar el tema por defecto Metro:
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/lightsquid/lightsquid.cfg
# choose theme (default "metro")
#$templatename        ="base";
$templatename        ="metro_tpl";
```

### Data Statistics

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Traffic statistics are displayed in the web application, along with the users who exceeded their limits. To change the data limit in the <code>lightsquid.cfg</code> statistics:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Las estadísticas del tráfico se muestran en la aplicación web, junto con los usuarios que superaron el límite. Para cambiar el límite de datos en las estadísticas de <code>lightsquid.cfg</code>:
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/lightsquid/lightsquid.cfg

# Nomenclature: 10 = 10 MBytes, 512 = 512 Mbytes, 1000 = 1 Gbytes...
# By default it comes in 1000. Do not modify the value 1024.

#user maximum size per day limit (oversize)
$perusertrafficlimit = 1000*1024*1024;
```

### Reports

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     LightSquid can generate reports in PDF, CSV, and other formats, but it will only display the top domains. If you want to retrieve all the domains visited on your local network in a single ACL suitable for Squid, run the following command:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     LightSquid puede generar reportes en PDF, CSV, etc., pero solo mostrará los dominios principales (TOP). Si desea obtener todos los dominios visitados en su red local en una sola ACL apta para Squid, ejecute el siguiente comando:
    </td>
  </tr>
</table>

```bash
find /var/www/lightsquid/report -type f -name '[0-9]*.[0-9]*.[0-9]*.[0-9]*' -exec grep -oE '[[:alnum:]_.-]+\.([[:alnum:]_.-]+)+' {} \; | sed 's/^\.//' | sed -r 's/^(www|ftp|ftps|ftpes|sftp|pop|pop3|smtp|imap|http|https)\.//g' | sed -r '/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/d' | tr -d ' ' | awk '{print "." $1}' | sort -u > sites.txt
```

## BAN DATA (Optional)

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top; padding-right: 20px;">
      <p>
        <strong>Bandata</strong> is a script that sets data usage limits -daily, weekly, and monthly- for IP addresses on a LAN monitored with Squid and LightSquid, and automatically blocks those that exceed the established quotas.
      </p>
      <p><em>Note: Weekends are excluded from the calculation and the limits must match those configured in LightSquid.</em></p>
    </td>
    <td style="width: 50%; vertical-align: top; padding-left: 20px;">
      <p>
        <strong>Bandata</strong> es un script que establece límites de consumo de datos -diario, semanal y mensual- para direcciones IP de una LAN monitorizada con Squid y LightSquid, y bloquea automáticamente aquellas que superan las cuotas establecidas.
      </p>
      <p><em>Nota: Los fines de semana quedan excluidos del cálculo y los límites deben coincidir con los configurados en LightSquid.</em></p>
    </td>
  </tr>
</table>


### Install

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To install the script Bandata, run:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para instalar el script Bandata, ejecute:
    </td>
  </tr>
</table>

```bash
wget -c https://raw.githubusercontent.com/maravento/vault/master/lightsquid/bandata/bdinstall.sh && sudo chmod +x bdinstall.sh && sudo ./bdinstall.sh
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The Bandata installation script adds a task to the crontab to run every 10 seconds. You can change it according to your preferences.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script de instalación de Bandata agrega una tarea al crontab, para que se ejecute cada 12 segundos. Puedes cambiarla según tus preferencias:
    </td>
  </tr>
</table>

```bash
*/12 * * * * /etc/scr/bandata.sh"
```

### Warning

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     When a user's IP address exceeds the quota limit -daily, weekly, or monthly- they will be redirected to the Warning portal:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Cuando la IP de un usuario supera el límite de cuota -diaria, semanal o mensual-, será redirigida al portal de advertencia (Warning):
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/lightsquid/img/warning.png)](https://www.maravento.com/)

```bash
http://SERVERIP:18880 or http://localhost:18880
```

### Server IP | LocalNet Prefix

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     During installation the script Bandata will ask for the IP address of the server where it will be installed (e.g. 192.168.0.10) and the LAN prefix (e.g. 192.168*):
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Durante la instalación el script Bandata preguntará la dirección IP del servidor donde se instalará (ej: 192.168.0.10) y el prefijo de la LAN (ej: 192.168*):
    </td>
  </tr>
</table>

### Banned IPs

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To check the banned IPs:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para verificar las IPs baneadas:
    </td>
  </tr>
</table>

```bash
cat /etc/acl/{banmonth,banweek,banday}.txt | uniq
```

### Data Limit

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To set the data limit, you can use GBytes, MBytes, or Bytes; for example: 0.5G, 512M, or 536870912. By default, the data usage limits are: 1 Gigabyte (1G) per day, 5 Gigabytes (5G) per week, and 20 Gigabytes (20G) per month.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para establecer el límite de datos, puede usar GBytes, MBytes o Bytes; por ejemplo: 0.5G, 512M o 536870912. Por defecto, los valores del límite de consumo son: 1 Gigabyte (1G) diario, 5 Gigabytes (5G) semanales y 20 Gigabytes (20G) mensuales.
    </td>
  </tr>
</table>

#### By Day

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The script checks the current day's LightSquid report and blocks any local network user who exceeds the defined data limit. The block will be lifted the following day. To change the daily data limit in <code>bandata.sh</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script verifica el informe del día actual de LightSquid y bloquea a cualquier usuario de la red local que supere el consumo establecido. El bloqueo se levantará al día siguiente. Para cambiar el límite de datos diario en <code>bandata.sh</code>:
    </td>
  </tr>
</table>

```bash
max_bandwidth_day="1G"
```

#### By Week

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Every Monday, the script analyzes the bandwidth usage from the weekdays (Monday to Friday) of the previous week. If any local network user exceeds the weekly limit (default: 5G), they will be blocked. To change the weekly data limit in <code>bandata.sh</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Cada lunes, el script analiza el consumo de los días hábiles (lunes a viernes) de la semana anterior. Si un usuario de la red local supera el límite semanal (por defecto 5G), será bloqueado. Para cambiar el límite de datos semanal en <code>bandata.sh</code>:
    </td>
  </tr>
</table>

```bash
max_bandwidth_week="5G"
```

#### By Month

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     At any time, the script can analyze the accumulated traffic during the weekdays of the current month (excluding weekends). If any user exceeds the monthly limit (default: 20G), they will be blocked immediately. To change the monthly data limit in <code>bandata.sh</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     En cualquier momento, el script puede analizar el tráfico acumulado durante los días hábiles del mes actual (excluyendo fines de semana). Si detecta que un usuario ha superado el límite mensual (por defecto 20G), lo bloqueará de inmediato. Para cambiar el límite de datos mensual en <code>bandata.sh</code>:
    </td>
  </tr>
</table>

```bash
max_bandwidth_month="20G"
```

## End-of-Life (EOL) | End-of-Support (EOS)

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     This project has reached EOL - EOS. No longer supported or updated.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Este proyecto a alcanzado EOL - EOS. Ya no cuenta con soporte o actualizaciones.
    </td>
  </tr>
</table>

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
