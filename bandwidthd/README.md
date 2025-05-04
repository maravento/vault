# [BandwidthD](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://bandwidthd.sourceforge.net/)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      <b>BandwidthD</b> tracks usage of TCP/IP network subnets and builds html files with graphs to display utilization. Charts are built by individual IPs, and by default display utilization over 2 day, 8 day, 40 day, and 400 day periods. Furthermore, each ip address's utilization can be logged out at intervals of 3.3 minutes, 10 minutes, 1 hour or 12 hours in cdf format, or to a backend database server. HTTP, TCP, UDP, ICMP, VPN, and P2P traffic are color coded.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      <b>BandwidthD</b> rastrea el uso de subredes de red TCP/IP y crea archivos html con gráficos para mostrar la utilización. Los gráficos se crean por IP individuales y, de forma predeterminada, muestran la utilización en períodos de 2 días, 8 días, 40 días y 400 días. Además, la utilización de cada dirección IP puede cerrarse sesión a intervalos de 3,3 minutos, 10 minutos, 1 hora o 12 horas en formato cdf, o en un servidor de base de datos back-end. El tráfico HTTP, TCP, UDP, ICMP, VPN y P2P está codificado por colores.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/bandwidthd
```

## DATA SHEET

---

| Developers | Last Version | HowTo |
| :---: | :---: | :---: |
| [David Hinkle, Brice Beaman, Andreas Henriksson](https://bandwidthd.sourceforge.net/) | [v2.0.1 (NethServer. 2005)](https://github.com/NethServer/bandwidthd) | [Post (ESP)](https://www.maravento.com/2021/08/bandwidthd.html) |

### Important before using

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      This application contains many bugs in the logs, so use it at your own risk.<br>
      Tested on Ubuntu 22.04 LTS x64.<br>
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Esta aplicación contiene muchos bugs en los Logs, por tanto úsela bajo su propio riesgo.<br>
      Probado en: Ubuntu 22.04 LTS x64.<br>
    </td>
  </tr>
</table>

## HOW TO INSTALL

---

```bash
wget -c https://raw.githubusercontent.com/maravento/vault/master/bandwidthd/bwinstall.sh && sudo chmod +x bwinstall.sh && sudo ./bwinstall.sh
```

## HOW TO USE

---

### Access

[http://localhost/bandwidthd/](http://localhost/bandwidthd/)

[![Image](https://raw.githubusercontent.com/maravento/vault/master/bandwidthd/img/bandwidthd.png)](https://www.maravento.com/)

### Virtualhost

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      BandwidthD works on port 80 and this can cause conflicts with other applications using this port and the configuration file has no option to change it, so the install script sets up a virtualhost on port 41000. To change it, for example, for 42000 or whatever, run:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      BandwidthD trabaja por el puerto 80 y esto puede generar conflictos con otras aplicaciones que usen este puerto y el archivo de configuración no tiene opción para cambiarlo, por tanto, el script de instalación configura un virtualhost en el puerto 41000. Para cambiarlo, por ejemplo, por 42000 o cualquier otro, ejecute:
    </td>
  </tr>
</table>

```bash
sudo sed -i "s:41000:42000:g" /etc/apache2/sites-available/bandwidthd.conf
sudo sed -i "s:41000:42000:g" /etc/apache2/port.conf
```

### Logs

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      BandwidthD logs are located in the folder:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Los logs de BandwidthD se encuentran en la carpeta:
    </td>
  </tr>
</table>

```bash
/var/lib/bandwidthd/
htdocs  log.1.0.cdf  log.2.0.cdf  log.3.0.cdf log.4.0.cdf
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      And the graphs are located in the htdocs folder and mean the following:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Y las gráficas se encuentran en la carpeta htdocs y significan lo siguiente:
    </td>
  </tr>
</table>

```bash
Daily report = log.1.0.cdf-log.1.5.cdf (htdocs/index.html)
Weekly report = log.2.0.cdf-log.2.5.cdf (htdocs/index2.html)
Monthly report = log.3.0.cdf-log.3.5.cdf (htdocs/index3.html)
Yearly report = log.4.0.cdf-log.4.5.cdf (htdocs/index4.html)
```

#### Log Bugs

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      The daily graph shows up to 4000 local IP addresses every 200 seconds (3.3 min), updates the report weekly every 10 min, monthly every hour and yearly every 12 hours. However, it is well known that in some scenarios these stats do not do what they are supposed to (check <a href="https://sourceforge.net/p/bandwidthd/discussion/308609/thread/b5f2356a/" target="_blank">BandwidthD forum</a>). The specific problem is that the logs do not rotate. In fact, they can manually run the script to rotate to no avail. To fix this, the install script creates a task in crontab that sends a <code>kill</code> command to <code>pid</code> so it can do the rotation, giving it 5 minutes of time to generate statistics (twice as long as the config file says default for graph generation which is 2.5 minutes) and restart the daemon:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      El gráfico diario muestra hasta 4000 direcciones IP locales cada 200 segundos (3.3 min), actualiza el reporte el semanal cada 10 min, mensual cada hora y anual cada 12 horas. Sin embargo, es bien conocido que en algunos escenarios estas estadísticas no hacen lo que se supone (ver <a href="https://sourceforge.net/p/bandwidthd/discussion/308609/thread/b5f2356a/" target="_blank">foro de BandwidthD</a>). El problema concreto es que los log no rotan. De hecho, pueden ejecutar manualmente el script para rotar sin resultados. Para solucionarlo, el script de instalación crea una tarea en crontab que envía un comando <code>kill</code> al <code>pid</code> para que pueda hacer la rotación, le da 5 minutos de tiempo para generar estadísticas (el doble de tiempo que el archivo de configuración establece por defecto para la generación de gráficas que es 2.5 minutos) y reinicia el demonio:
    </td>
  </tr>
</table>

```bash
0 0 * * * /bin/kill -HUP $(cat /var/run/bandwidthd.pid) && sleep 5m && /etc/init.d/bandwidthd restart
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      It may happen that the log does the rotation, but the graphs are not generated and the daily traffic of the previous day continues to appear, instead of the counter at 0. In this case, the installation script creates another task that solves it, deleting the file rotated, programming the following command in cron:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Puede suceder que el log haga la rotación, pero las gráficas no se generen y siga apareciendo el tráfico diario del día anterior, en lugar del contador a 0. En este caso, el script de instalación crea otra tarea que lo soluciona, eliminando el archivo rotado, programando el siguiente comando en el cron:
    </td>
  </tr>
</table>

```bash
@daily cat /dev/null | tee /var/lib/bandwidthd/log.1.0.cdf && sleep 5m && /etc/init.d/bandwidthd restart
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      To clear all logs, open the terminal and run the following command with privileges:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Para vaciar todos los logs, abra el terminal y ejecute con privilegios el siguiente comando:
    </td>
  </tr>
</table>

```bash
sudo cat /dev/null | sudo tee /var/lib/bandwidthd/log.* && sudo /etc/init.d/bandwidthd restart
```

### Network Configuration

```bash
sudo bandwidthd -l
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      Example of default ranges from the configuration file:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Ejemplo de rangos por defecto del archivo de configuración:
    </td>
  </tr>
</table>

```bash
sudo cat /etc/bandwidthd/bandwidthd.conf | grep subnet
# matches none of these subnets will be ignored.
#subnet 192.168.0.0/24
subnet 169.254.0.0/16 # LAN
subnet 192.168.0.0/24 # WAN
subnet 192.168.122.0/24 # others interfaces
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      The installation script will ask you to set your network range and mask. You can also do it manually:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      El script de instalación le pedirá que establezca su rango de red y máscara. También puede hacerlo manualmente:
    </td>
  </tr>
</table>

```bash
# Example for LAN
sudo sed -i "s:169.254.0.0/16:XXX.XXX.XX.0/24:g" /etc/bandwidthd/bandwidthd.conf
# Example for WAN
sudo sed -i "s:192.168.0.0/24:XXX.XXX.XX.0/24:g" /etc/bandwidthd/bandwidthd.conf
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      It is suggested not to change "any" in case you have two interfaces you can monitor both:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Se sugiere no cambiar "any" por si tiene dos interfaces pueda monitorear ambas:
    </td>
  </tr>
</table>

```bash
# Device to listen on
# Bandwidthd listens on the first device it detects
# by default.  Run "bandwidthd -l" for a list of
# devices.
#dev "eth0"

dev "any"
```

## BAN DATA (Optional)

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      This section is to block users who have overcome the consumption of data default by the sysadmin.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Esta sección es para bloquear a los usuarios que hayan superado el consumo de datos predeterminado por el sysadmin.
    </td>
  </tr>
</table>

**To run it manually: | Para ejecutarlo manualmente:**

```bash
sudo /etc/init.d/bwbandata.sh
```

**crontab (every 15 min):**

```bash
*/15 * * * * /etc/init.d/bwbandata.sh
```

**To check the Allowed/Blocked IPs: | Para verificar las IPs Permitidas/Bloqueadas:**

```bash
# Banned IPs
cat /etc/acl/bwbandata.txt
# Allowed IPs
cat /etc/acl/bwallowdata.txt
```

**Replace localnet interface: | Reeplace su interface de red local:**

```bash
sudo nano /etc/init.d/bwbandata.sh

# replace localnet interface (enpXsX)
lan=eth1
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      During the installation, the script shows the network interfaces and you must choose the interface for LAN and the script makes the change.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Durante la instalación, el script muestra las interfaces de red y deberá elegir la interface para LAN y el script hace el cambio.
    </td>
  </tr>
</table>

### Data Limit

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      The script checks the Lightsquid current day report and blocks any user, within the local network, who exceeds the set consumption. The block will be removed the next day.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      El script verifica el informe del día actual de Lightsquid y bloquea a cualquier usuario, dentro de la red local, que supere el consumo establecido. El bloqueo se levantará al día siguiente.
    </td>
  </tr>
</table>

**To change the daily data limit in `bandata.sh` | Para cambiar el límite de datos diarios en `bandata.sh`:**

```bash
sudo nano /etc/init.d/bwbandata.sh

### BANDATA FOR BANDWIDTHD
# maximum daily data consumption: 1 Gbyte = 1G
max_bandwidth="1G"
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      The data quota is expressed in Mbytes or Gbytes (not in Mbps or Gbps which is speed). The nomenclature to use can be in GBytes instead of Bytes, for example 0.5G or 512M or 536870912. By default, we select 1 Gigabyte (GB) of data = 1073741824 byte (B).
    </td>
    <td style="width: 50%; white-space: nowrap;">
      La cuota de datos está expresada en Mbytes o Gbytes (no en Mbps o Gbps que es velocidad). La nomenclatura a usar puede ser en GBytes en lugar de Bytes, por ejemplo 0.5G o 512M o 536870912. Por defecto, seleccionamos 1 Gigabyte (GB) de datos = 1073741824 byte (B).
    </td>
  </tr>
</table>

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
