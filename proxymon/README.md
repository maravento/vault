# [Proxy Monitor](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      <b>Proxy Monitor</b> is a web application designed to work exclusively with the <a href="https://www.squid-cache.org/" target="_blank">Squid-Cache</a> proxy server and requires the <a href="https://httpd.apache.org/" target="_blank">Apache2</a> web server. It reads traffic information from Squid's <code>access.log</code> to generate detailed statistics and usage reports for the local network. Use the tabs at the top of the dashboard to access each analysis module.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      <b>Proxy Monitor</b> es una aplicación web diseñada para funcionar exclusivamente con el servidor proxy <a href="https://www.squid-cache.org/" target="_blank">Squid-Cache</a> y requiere el servidor web <a href="https://httpd.apache.org/" target="_blank">Apache2</a>. Obtiene la información de tráfico desde el archivo <code>access.log</code> de Squid para generar estadísticas detalladas e informes de uso de la red local. Utilice las pestañas en la parte superior del panel para acceder a cada módulo de análisis.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/proxymon
```

### Minimum Requirements

|   OS   |   CPU   |   RAM   |   Storage   |   Dependencies   |
| :----: | :-----: | :-----: | :---------: | :--------------: |
| Ubuntu 24.04.x | Intel Core i5/Xeon/AMD Ryzen 5 (≥ 3.0 GHz) | 16 GB | 2 GB SSD | Squid Cache v6.13, Apache v2.4.58, PHP 8.3.6 |

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
     - The results shown in <a href="#squidmon_search">Squidmon Search</a> and <a href="#traffic_search">Traffic Search</a> are examples and may vary depending on your environment, dataset size, historical data volume, and computational resources available for ACL processing.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     - Los resultados mostrados en <a href="#squidmon_search">Squidmon Search</a> y <a href="#traffic_search">Traffic Search</a> son ejemplos y pueden variar según tu entorno, tamaño del conjunto de datos, volumen de datos históricos y recursos computacionales disponibles para el procesamiento de ACLs.
    </td>
  </tr>
</table>

## HOW TO INSTALL

---

```bash
wget -O proxymon.sh https://raw.githubusercontent.com/maravento/vault/refs/heads/master/proxymon/proxymon.sh && sudo chmod +x proxymon.sh && sudo ./proxymon.sh
```

### Features & Options

```bash
# Proxy Monitor module installation/uninstallation script
#
# Description:
#   This script installs or uninstalls the Proxy Monitor application.
#   Proxy Monitor provides traffic monitoring and reporting for Squid proxy servers
#   with Squidmon, LightSquid, SARG, Sqstat and Squid Analyzer modules.
#
# Features:
# - LightSquid traffic reporting module (fast reports, per-user statistics, and daily/monthly traffic)
# - SQStat for real-time monitoring
# - SARG report generator (detailed and customizable reports)
# - SquidAnalyzer log analysis module (graphical traffic statistics and usage trends)
# - Bandata script for bandwidth control, usage limits, and quota management (integrated with LightSquid)
# - Squidmon statistics module (advanced statistics, report printing, and ACL-driven operations)
# - Warning portal for quota limit notifications
# - Automatic dependency checking
# - Crontab task management
# - Apache virtual host configuration
#
# Usage:
#   sudo ./proxymon.sh [OPTIONS]
#
# Options:
#   install      Install Proxy Monitor
#   uninstall    Uninstall Proxy Monitor
#   -h, --help   Show help message
#
# Examples:
#   sudo ./proxymon.sh              # Interactive menu
#   sudo ./proxymon.sh install      # Direct installation
#   sudo ./proxymon.sh uninstall    # Direct uninstallation
```

<b>Access Proxymon</b>: [http://localhost:18080](http://localhost:18080)

<b>Access Warning</b>: [http://localhost:18081](http://localhost:18081)

## HOW TO USE

---

### MONITOR (Squidmon)

[![squidmon](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-tab.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Squid Monitor (squidmon) provides detailed real-time traffic analysis and monitoring of your Squid proxy. It displays comprehensive statistics including blocked domains, blocked clients, traffic patterns, and ACL matching information. The module allows you to monitor, filter, and generate detailed reports on network activity and content blocking.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Squid Monitor (squidmon) proporciona análisis de tráfico en tiempo real y monitoreo detallado de su proxy Squid. Muestra estadísticas completas incluyendo dominios bloqueados, clientes bloqueados, patrones de tráfico e información de coincidencia de ACL. El módulo permite monitorear, filtrar y generar reportes detallados sobre actividad de red y bloqueo de contenido.
    </td>
  </tr>
</table>

<h4 id="config">Config</h4>

[![squidmon conf](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-config.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      This section defines the parameters that Squid Monitor uses to interpret and display network activity, including data sources (access control lists —ACLs—), the maximum number of lines to analyze from the Squid log, the time range of the data, and the automatic refresh interval. The default path for ACLs is <code>/etc/acl</code> and the following lists are integrated:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Esta sección define los parámetros que Squid Monitor utiliza para interpretar y visualizar la actividad de la red, incluyendo las fuentes de datos (listas de control de acceso —ACLs—), el número máximo de líneas a analizar del registro de Squid, el rango temporal de los datos y la frecuencia de actualización automática. El path por defecto de las ACLs es <code>/etc/acl</code> y se integran las siguientes listas:
    </td>
  </tr>
</table>

```bash
/etc/acl/blocktlds.txt=Blocked TLD
/etc/acl/blocksites.txt=Blocked Sites
regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Block IPv4
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      To change the path and lists, modify this section of <b>Config</b>, as shown in the image above, and also change the path in the script <code>bandata.sh</code>.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Para cambiar el path y las listas, modifíquese en esta sección de <b>Config</b>, como se muestra en la imagen superior y cambie también el path en el script <code>bandata.sh</code>.
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/proxymon/tools/bandata.sh
# path to ACLs folder
aclroute=/etc/acl
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      <b>⚠️ Important:</b> Any ACL you want to declare in Squidmon configuration must also be declared in your <code>squid.conf</code> for blocking to take effect. Example for declaring default ACLs:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      <b>⚠️ Importante:</b> Cualquier ACL que quiera declarar en la configuración de Squidmon, también deberá declararlas en su <code>squid.conf</code> para que surta efecto el bloqueo. Ejemplo para declarar las ACLs por defecto:
    </td>
  </tr>
</table>

```bash
sudo nano /etc/squid/squid.conf
#
# INSERT YOUR OWN RULE(S) HERE TO ALLOW ACCESS FROM YOUR CLIENTS
#
include /etc/squid/conf.d/*.conf
# Block: TLDs
# For more information visit: https://github.com/maravento/blackweb
acl blocktlds dstdomain "/etc/acl/blocktlds.txt"
http_access deny workdays blocktlds
# Block: sites
acl blocksites dstdomain "/etc/acl/blocksites.txt"
http_access deny workdays blocksites
# Block: IPv4
acl no_ip url_regex -i ^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+
http_access deny no_ip
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      <b style="color: #d9534f;">⚠️ Warning:</b> Default values are <b>24 hours</b> and <b>50,000 lines</b> from <i>access.log</i>. Increasing these values may slow down the module and raise system resource usage. Refer to the <a href="#squidmon_search"><b>Squidmon Search</b></a> section. To reset the filters to their default values, press the <b>Reset to Default</b> button.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      <b style="color: #d9534f;">⚠️ Advertencia:</b> Los valores por defecto son de <b>24 horas</b> y <b>50&nbsp;000 líneas</b> del archivo <i>access.log</i>. Aumentar estos valores puede ralentizar el módulo y elevar el uso de recursos del sistema. Consulte la sección <a href="#squidmon_search"><b>Squidmon Search</b></a>. Para resetear los filtros a sus valores por default, presione el botón <b>Reset to Default</b>.
    </td>
  </tr>
</table>

#### Top Blocked Domains & Clients

[![squidmon top_blocked](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-top.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>Top Blocked Domains:</b> Displays a list of the most frequently blocked domains on your network. Shows the domain name with port information and the total number of blocked requests for each domain. This helps identify which sites or services are being blocked most often and allows administrators to adjust blocking policies accordingly.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>Top Blocked Domains:</b> Muestra una lista de los dominios más bloqueados frecuentemente en su red. Muestra el nombre del dominio con información del puerto y el número total de solicitudes bloqueadas para cada dominio. Esto ayuda a identificar qué sitios o servicios se están bloqueando más frecuentemente y permite a los administradores ajustar las políticas de bloqueo en consecuencia.
    </td>
  </tr>
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>Top Blocked Clients:</b> Shows the client IP addresses with the highest number of blocked requests. Each entry displays the total requests made, blocked requests count, and the percentage of traffic that was blocked. This helps identify clients that frequently attempt to access restricted content and may require additional monitoring or bandwidth management.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>Top Blocked Clients:</b> Muestra las direcciones IP de los clientes con el mayor número de solicitudes bloqueadas. Cada entrada muestra el total de solicitudes realizadas, el conteo de solicitudes bloqueadas y el porcentaje del tráfico que fue bloqueado. Esto ayuda a identificar clientes que frecuentemente intentan acceder a contenido restringido y pueden requerir monitoreo adicional o gestión de ancho de banda.
    </td>
  </tr>
</table>

#### Traffic by Client IP

[![squidmon traffic](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-traffic-clients.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Provides an expandable view of all client IP addresses and their traffic statistics. For each client, you can see total requests, blocked requests, and allowed requests. The module includes advanced filtering options with ACL selection, search functionality to find specific IPs or domains, and time range reports (Last 24 Hours, Last 7 Days, Last 30 Days). Individual PDF reports can be generated for each client's traffic.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Proporciona una vista expandible de todas las direcciones IP de clientes y sus estadísticas de tráfico. Para cada cliente, puede ver el total de solicitudes, solicitudes bloqueadas y solicitudes permitidas. El módulo incluye opciones de filtrado avanzadas con selección de ACL, funcionalidad de búsqueda para encontrar IPs o dominios específicos, y reportes de rango de tiempo (Últimas 24 Horas, Últimos 7 Días, Últimos 30 Días). Se pueden generar reportes PDF individuales para el tráfico de cada cliente.
    </td>
  </tr>
</table>

#### Filtering and Search

[![squidmon acl](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-acls.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Squidmon provides powerful filtering capabilities, allowing you to classify traffic using ACLs (Access Control Lists) such as <b>Blocked TLD</b>, <b>Blocked Sites</b>, <b>Blocked Patterns</b>, <b>Block IPv4</b>, or <b>Unknown ACL</b> (any rule defined in <code>squid.conf</code> that is not listed in the ACLs specified in Config). It also includes a search tool to locate clients by IP address or identify domains by name, as well as the options <b>Show Blocked Only</b> and <b>Show Allowed Only</b> to display only blocked or allowed traffic. To return to the default view, you can use the <b>Clean Filters</b> button.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Squidmon ofrece potentes capacidades de filtrado, permitiendo clasificar el tráfico mediante ACLs (Access Control Lists) como <b>Blocked TLD</b>, <b>Blocked Sites</b>, <b>Blocked Patterns</b>, <b>Block IPv4</b>, o <b>Unknown ACL</b> (cualquier regla definida en <code>squid.conf</code> que no esté incluida en las ACLs especificadas en Config). También incluye una herramienta de búsqueda para localizar clientes por dirección IP o identificar dominios por nombre, así como las opciones <b>Show Blocked Only</b> y <b>Show Allowed Only</b> para visualizar únicamente el tráfico bloqueado o permitido. Para volver a la vista inicial, puede usar el botón <b>Clean Filters</b>.
    </td>
  </tr>
</table>

#### Report Generation

[![squidmon pdf](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-pdf.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Generate detailed PDF reports for traffic analysis and auditing purposes. Reports can be generated for specific time ranges including Last 24 Hours, Last 7 Days, or Last 30 Days. Each client or domain can have an individual PDF report created, making it easy to share traffic statistics with other administrators or stakeholders. The <b>Generate PDF Report</b> button is available throughout the interface.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Genere reportes PDF detallados para propósitos de análisis de tráfico y auditoría. Los reportes se pueden generar para rangos de tiempo específicos incluyendo Últimas 24 Horas, Últimos 7 Días o Últimos 30 Días. Se puede crear un reporte PDF individual para cada cliente o dominio, facilitando compartir estadísticas de tráfico con otros administradores o partes interesadas. El botón <b>Generate PDF Report</b> está disponible en toda la interfaz.
    </td>
  </tr>
</table>

#### Blocked URLs Analysis

[![squidmon filter](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-traffic-clients-filter.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     When expanding a specific client IP, you can view detailed information about blocked URLs including the specific URLs that were blocked, the ACL rule that matched (e.g., <b>Blocked Sites</b>), and the number of times each URL was attempted. This granular level of detail helps identify problematic browsing patterns and allows for fine-tuning of access control policies.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Al expandir una IP de cliente específica, puede ver información detallada sobre URLs bloqueadas incluyendo las URLs específicas que fueron bloqueadas, la regla de ACL que coincidió (por ejemplo, <b>Blocked Sites</b>), y el número de veces que se intentó acceder a cada URL. Este nivel de detalle granular ayuda a identificar patrones de navegación problemáticos y permite afinar las políticas de control de acceso.
    </td>
  </tr>
</table>

#### Patterns

[![squidmon patterns](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-patterns.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     If you have an ACL in Squid-Cache that uses <code>url_regex</code>, you cannot declare its file path in the Squid Monitor configuration module; You must declare your content directly in the <a href="#config">module settings</a>. Example:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Si tiene una ACL en Squid-Cache que utiliza <code>url_regex</code>, no puede declarar su ruta de archivo en el módulo de configuración de Squid Monitor; debe declarar directamente su contenido en la <a href="#config">configuración del módulo</a>. Ejemplo:
    </td>
  </tr>
</table>

```bash
regex:(announce|announce_peer|announce.php?passkey=|Azureus|BitComet|BitLord|bittorrent|BitTorrent|BitTorrent protocol|bittorrent-announce|blockports|d1:ad2:id20:|find_node|get_peers|info_hash|iptv|IPTV|jndi|Jndi|JNDI|magnet:|MIICdzCCAV|netcut|nopor|onion|owari|peer_id|peer_id=|porn|psiphon|Shareaza|torrent|Torrent|tracker|Transmission|ultrasurf|utorrent|web3|XBT|xxx)=Blocked Patterns
regex:^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+=Blocked IPv4
```

<h4 id="squidmon_search">Squidmon Search</h4>

![squidmon search](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidmon-search.png)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      <b>Result:</b> 6 clients found in <b>0.08 seconds</b>. Client IP-based filtering with domain resolution.<br>
      <b>Data Source:</b> Squid access logs <code>/var/log/squid/access.log</code><br>
      <b>Search Method:</b> Real-time log parsing with ACL filtering<br>
      <b>Use Case:</b> Real-time client activity, immediate threat detection<br>
    </td>
    <td style="width: 50%; white-space: nowrap;">
      <b>Resultado:</b> 6 clientes encontrados en <b>0.08 s</b>. Filtrado basado en IP del cliente con resolución de dominio.<br>
      <b>Fuente de Datos:</b> Registros de acceso de Squid <code>/var/log/squid/access.log</code><br>
      <b>Método de Búsqueda:</b> Análisis de registros en tiempo real con filtrado ACL<br>
      <b>Caso de Uso:</b> Actividad de cliente en tiempo real, detección inmediata de amenazas<br>
    </td>
  </tr>
</table>

#### Logrotate

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Squidmon reads only the current <code>access.log</code> file, not rotated files (<code>access.log.0</code>, <code>access.log.1</code>, <code>access.log.gz</code>, etc.). It's recommended to disable Squid's internal rotation with <code>logfile_rotate 0</code> in <code>squid.conf</code> and let <code>logrotate</code> handle it exclusively. Configure <code>/etc/logrotate.d/squid</code> to use minimum <code>weekly</code> (7 days) or maximum <code>monthly</code> (1 month) rotation and keep <code>rotate 7</code> for history. This prevents conflicts between both rotation systems.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Squidmon solo lee el archivo <code>access.log</code> actual, no archivos rotados (<code>access.log.0</code>, <code>access.log.1</code>, <code>access.log.gz</code>, etc.). Se recomienda desactivar la rotación interna de Squid con <code>logfile_rotate 0</code> en <code>squid.conf</code> y dejar que <code>logrotate</code> la maneje exclusivamente. Configure <code>/etc/logrotate.d/squid</code> para usar como mínimo rotación <code>weekly</code> (7 días) o como máximo <code>monthly</code> (1 mes) y mantener <code>rotate 7</code> para el historial. Esto evita conflictos entre ambos sistemas de rotación.
    </td>
  </tr>
</table>

```bash
# Disable Squid internal rotation
sudo nano /etc/squid/squid.conf
#  TAG: logfile_rotate
logfile_rotate 0

# Logrotate
sudo sed -i 's/^	daily$/	weekly/' /etc/logrotate.d/squid
# or
sudo sed -i 's/^	daily$/	monthly/' /etc/logrotate.d/squid
# Optional:
sudo sed -i 's/rotate 2/rotate 7/' /etc/logrotate.d/squid
```

### TRAFFIC (Lightsquid)

[![lightsquid report](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/lightsquid-tab.png)](https://www.maravento.com/)

#### Error

[![lightsquid error](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/lightsquid-report.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The first time you open Squid Report in your browser, you may receive an error message. This is because you haven't run the script for the first time, or your LAN traffic hasn't passed through Squid, so there's no data in the <code>/var/www/proxymon/lightsquid/report</code> folder. The installation script runs the command that generates the reports, but if they still don't appear, open the terminal and run it manually:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     La primera vez que abra Squid Report en su navegador, puede salir un mensaje de error. Esto se debe a que no ha ejecutado por primera vez el script o el tráfico de su LAN no ha pasado por Squid y, por tanto, no hay datos en la carpeta <code>/var/www/proxymon/lightsquid/report</code>. El script de instalación ejecuta el comando que genera los reportes, pero si continúan sin aparecer, abra el terminal y ejecute manualmente:
    </td>
  </tr>
</table>

```bash
sudo /var/www/proxymon/lightsquid/lightparser.pl today
```

#### Search Bar

[![lightsquid bar](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/lightsquid-searchbar.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      In the General Statistics module, the search bar allows you to quickly filter and find specific data within the report table. Simply enter a keyword or value in the search field and click the SEARCH button to display matching results. This feature helps you locate information efficiently without scrolling through the entire dataset.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      En el módulo General Statistics, la barra de búsqueda te permite filtrar y encontrar datos específicos rápidamente dentro de la tabla de reportes. Simplemente ingresa una palabra clave o valor en el campo de búsqueda y haz clic en el botón SEARCH para mostrar los resultados coincidentes. Esta función te ayuda a localizar información de manera eficiente sin necesidad de desplazarte por todo el conjunto de datos.
    </td>
  </tr>
</table>

[![lightsquid bar output](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/lightsquid-searchbar-output.png)](https://www.maravento.com/)

<h4 id="traffic_search">Traffic Search</h4>

![lightsquid search](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/lightsquid-search.png)

<table width="100%">
  <tr>
    <td style="width: 50%;">
      <b>Result:</b> 1,323 entries found in <b>5.4 seconds</b>. Full-text search across all indexed domains and sites.<br><br>
      <b>Data Source:</b> LightSquid reports<br>
      <code>/var/www/proxymon/lightsquid/report/YYYYMMDD/</code><br><br>
      <b>Search Method:</b> Grep-optimized index with Perl regex fallback<br><br>
      <b>Use Case:</b> Historical analysis, domain trends, bandwidth reports
    </td>
    <td style="width: 50%;">
      <b>Resultado:</b> 1,323 registros encontrados en <b>5.4 s</b>. Búsqueda de texto completo en todos los dominios y sitios indexados.<br><br>
      <b>Fuente de Datos:</b> Reportes de LightSquid<br>
      <code>/var/www/proxymon/lightsquid/report/YYYYMMDD/</code><br><br>
      <b>Método de Búsqueda:</b> Índice optimizado con grep y alternativa de regex Perl<br><br>
      <b>Caso de Uso:</b> Análisis histórico, tendencias de dominios, reportes de ancho de banda
    </td>
  </tr>
</table>

#### Traffic Cron Job

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The installation script adds a task to the crontab to run every 10 minutes. You can change it according to your preferences.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script de instalación agrega una tarea al crontab para que se ejecute cada 10 minutos. Puedes cambiarla según tus preferencias.
    </td>
  </tr>
</table>

```bash
sudo -u www-data crontab -e
*/10 * * * * /var/www/proxymon/lightsquid/lightparser.pl today
```

#### Add Users

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     To add users manually:<br><br>
     <em>Note: <a href="#bandata">Bandata</a> does this automatically.</em>
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para agregar usuarios manualmente:<br><br>
     <em>Nota: <a href="#bandata">Bandata</a> lo hace automáticamente.</em>
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/proxymon/lightsquid/realname.cfg
# example:
192.168.X.2 Client1
192.168.X.3 CEO
```

#### Exclude Users

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
sudo nano /var/www/proxymon/lightsquid/skipuser.cfg
# example
192.168.X.1
```

#### Netscan

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
sudo nbtscan 192.168.X.0/24
# 2. Using nmap
sudo nmap -sn 192.168.X.0/24
# 3. Using arp-scan
sudo arp-scan --localnet
# 4. Using nast
sudo nast -m
# 5. Using netdiscover
sudo netdiscover
```

#### Theme

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     There are only two themes available: "base" (very outdated) and "metro" (default).
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Solo hay dos temas disponibles. "base" (muy anticuado) y "metro" (por defecto).
    </td>
  </tr>
</table>

```bash
sudo nano /var/www/proxymon/lightsquid/lightsquid.cfg
#$templatename        ="base";
$templatename        ="metro_tpl";
```

#### Data Statistics

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
sudo nano /var/www/proxymon/lightsquid/lightsquid.cfg

# Nomenclature: 10 = 10 MBytes, 512 = 512 Mbytes, 1000 = 1 Gbytes...
# By default it comes in 1000. Do not modify the value 1024.

#user maximum size per day limit (oversize)
$perusertrafficlimit = 1000*1024*1024;
```

#### Export Tools

[![lightsquid menu](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/lightsquid-menu.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      In the <b>General Statistics</b> module, the <b>Tools</b> button located on the right side of the header provides multiple export options. You can Copy the table data to your clipboard, Print the report directly, or export it in various formats including PDF, Excel (XLSX), and CSV for further analysis and sharing.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      En el módulo <b>General Statistics</b>, el botón <b>Tools</b> ubicado en el lado derecho del encabezado ofrece múltiples opciones de exportación. Puedes Copiar los datos de la tabla al portapapeles, Imprimir el reporte directamente, o exportarlo en diversos formatos incluyendo PDF, Excel (XLSX) y CSV para análisis posterior y compartirlo.
    </td>
  </tr>
</table>

#### Reports

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Squid Report can generate reports in PDF, CSV, and other formats, but it will only display the top domains. If you want to retrieve all the domains visited on your local network in a single ACL suitable for Squid, run the following command:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Squid Report puede generar reportes en PDF, CSV, etc., pero solo mostrará los dominios principales (TOP). Si desea obtener todos los dominios visitados en su red local en una sola ACL apta para Squid, ejecute el siguiente comando:
    </td>
  </tr>
</table>

```bash
find /var/www/proxymon/lightsquid/report -type f -name '[0-9]*.[0-9]*.[0-9]*.[0-9]*' -exec grep -oE '[[:alnum:]_.-]+\.([[:alnum:]_.-]+)+' {} \; | sed 's/^\.//' | sed -r 's/^(www|ftp|ftps|ftpes|sftp|pop|pop3|smtp|imap|http|https)\.//g' | sed -r '/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/d' | tr -d ' ' | awk '{print "." $1}' | sort -u > sites.txt
```

<h4 id="bandata">BanData</h4>

[![bandata](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/bandata.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      Bandata is a script that sets data usage limits —daily, weekly, and monthly— for IP addresses on a LAN monitored with Squid, and automatically blocks those that exceed the established quotas.
      <br><br>
      <strong>Notes:</strong>
      <ul>
        <li>Weekends are excluded from the calculation.</li>
        <li>The limits must match those configured in Squid Report.</li>
        <li>The script updates <em>realname.cfg</em> from Lightsquid.</li>
      </ul>
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Bandata es un script que establece límites de consumo de datos —diario, semanal y mensual— para direcciones IP de una LAN monitorizada con Squid, y bloquea automáticamente aquellas que superan las cuotas establecidas.
      <br><br>
      <strong>Notas:</strong>
      <ul>
        <li>Los fines de semana quedan excluidos del cálculo.</li>
        <li>Los límites deben coincidir con los configurados en Squid Report.</li>
        <li>El script se encarga de actualizar <em>realname.cfg</em> de Lightsquid.</li>
      </ul>
    </td>
  </tr>
</table>

```bash
# Bandata - Monitor bandwidth usage and enforce data limits (every 12 minutes)
sudo crontab -e
*/12 * * * * /var/www/proxymon/tools/bandata.sh
```

[![bandata terminal](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/bandata-terminal.png)](https://www.maravento.com/)

##### Warning Portal

[![warning](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/warning.png)](https://www.maravento.com/)

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

```bash
http://localhost:18081 or http://192.168.X.X:18081
```

##### Banned IPs

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

##### Data Limit

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

##### By Day

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The script checks the current day's Squid Report and blocks any users on the local network who exceed the set consumption limit. The block will be lifted the following day. To change the daily data limit in <code>/var/www/proxymon/tools/bandata.sh</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script verifica el informe del día actual de Squid Report y bloquea a cualquier usuario de la red local que supere el consumo establecido. El bloqueo se levantará al día siguiente. Para cambiar el límite de datos diario en <code>/var/www/proxymon/tools/bandata.sh</code>:
    </td>
  </tr>
</table>

```bash
max_bandwidth_day="1G"
```

##### By Week

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Every Monday, the script analyzes the bandwidth usage from the weekdays (Monday to Friday) of the previous week. If any local network user exceeds the weekly limit (default: 5G), they will be blocked. To change the weekly data limit in <code>/var/www/proxymon/tools/bandata.sh</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Cada lunes, el script analiza el consumo de los días hábiles (lunes a viernes) de la semana anterior. Si un usuario de la red local supera el límite semanal (por defecto 5G), será bloqueado. Para cambiar el límite de datos semanal en <code>/var/www/proxymon/tools/bandata.sh</code>:
    </td>
  </tr>
</table>

```bash
max_bandwidth_week="5G"
```

##### By Month

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     At any time, the script can analyze the accumulated traffic during the weekdays of the current month (excluding weekends). If any user exceeds the monthly limit (default: 20G), they will be blocked immediately. To change the monthly data limit in <code>/var/www/proxymon/tools/bandata.sh</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     En cualquier momento, el script puede analizar el tráfico acumulado durante los días hábiles del mes actual (excluyendo fines de semana). Si detecta que un usuario ha superado el límite mensual (por defecto 20G), lo bloqueará de inmediato. Para cambiar el límite de datos mensual en <code>/var/www/proxymon/tools/bandata.sh</code>:
    </td>
  </tr>
</table>

```bash
max_bandwidth_month="20G"
```

### REPORTS (SARG)

[![sarg](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/sarg-tab.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      SARG (Squid Analysis Report Generator) provides detailed analysis of proxy traffic, generating comprehensive reports of user activity, bandwidth consumption, and accessed websites. It tracks connection statistics, data transfer volumes, cache efficiency, and elapsed time for each user or IP address on the network.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      SARG (Generador de Reportes de Análisis de Squid) proporciona análisis detallado del tráfico del proxy, generando reportes exhaustivos de la actividad de usuarios, consumo de ancho de banda y sitios web accedidos. Realiza un seguimiento de estadísticas de conexión, volúmenes de transferencia de datos, eficiencia de caché y tiempo transcurrido para cada usuario o dirección IP en la red.
    </td>
  </tr>
</table>

#### Global Report

[![sarg global](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/sarg-global.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      The Global Report displays aggregated traffic statistics across all users and IP addresses. It shows the top visited websites, total bandwidth usage, connection counts, cache hit rates, and data transfer patterns. This overview helps administrators identify traffic trends, peak usage periods, and overall network behavior patterns.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      El Reporte Global muestra estadísticas de tráfico agregadas en todos los usuarios y direcciones IP. Presenta los sitios web más visitados, uso total de ancho de banda, conteos de conexión, tasas de acierto de caché y patrones de transferencia de datos. Esta visión general ayuda a los administradores a identificar tendencias de tráfico, períodos de uso máximo y patrones generales de comportamiento de la red.
    </td>
  </tr>
</table>

#### Report by IP

[![sarg ip](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/sarg-ip.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      The IP Report provides granular analysis for individual users or machines. It details specific browsing activity, showing accessed URLs, bandwidth consumption per user, connection frequency, cache efficiency, and time spent online. This enables administrators to monitor individual user behavior and enforce bandwidth policies on specific network devices.
    </td>
    <td style="width: 50%; white-space: nowrap;">
      El Reporte por IP proporciona análisis detallado para usuarios o máquinas individuales. Detalla la actividad de navegación específica, mostrando URLs accedidas, consumo de ancho de banda por usuario, frecuencia de conexión, eficiencia de caché y tiempo dedicado en línea. Esto permite a los administradores monitorear el comportamiento de usuarios individuales e implementar políticas de ancho de banda en dispositivos de red específicos.
    </td>
  </tr>
</table>

#### Report Rotation and Cleanup

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      SARG only keeps the last 7 days of logs as configured in <code>/etc/sarg/sarg.conf</code> with the parameter <code>lastlog 7</code>. Additionally, a weekly cron job automatically deletes report directories older than 30 days. If you want to change this behavior and extend the retention period (not recommended), modify both the configuration file and the crontab line according to your needs:
    </td>
    <td style="width: 50%; white-space: nowrap;">
      SARG solo conserva los últimos 7 días de registros según la configuración en <code>/etc/sarg/sarg.conf</code> con el parámetro <code>lastlog 7</code>. Además, una tarea cron semanal elimina automáticamente los directorios de reportes con más de 30 días de antigüedad. Si quiere cambiar este comportamiento y extender el período de retención (no recomendado), modifique tanto el archivo de configuración como la línea de crontab según sus necesidades:
    </td>
  </tr>
</table>

```bash
# Edit Sarg Config
sudo nano /etc/sarg/sarg.conf
# Change 7 to the desired number of days
lastlog 7 
# Edit crontab
sudo -u www-data crontab -l
# Replace: -mtime +30 with the desired number of days
@weekly find /var/www/proxymon/sarg/squid-reports -name "2*" -mtime +30 -type d -exec rm -rf "{}" \; &> /dev/null
# Restart cron
sudo systemctl restart cron
```

### REALTIME (SQSTAT)

[![sqstat](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/sqstat-tab.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>SqStat</b> is a script that allows you to verify the active connections of users. Use the cachemgr protocol to obtain information about the Squid.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>SqStat</b> es un script que permite verificar las conexiones activas de los usuarios. Utiliza el protocolo cachemgr para obtener información de Squid.
    </td>
  </tr>
</table>

#### Auto refresh

[![sqstat auto](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/sqstat-auto.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Select at least 5 seconds:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Seleccione al menos 5 segundos:
    </td>
  </tr>
</table>

#### Reload

[![sqstat f5](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/sqstat-f5.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     If you have a very large ACL defined in your <code>squid.conf</code>, it is normal for sqstat to temporarily lose its connection and display an error when Squid is restarted or reloaded, because Squid has not yet finished its startup or reload process; just wait a minute or two for the service to stabilize and then press F5 to refresh the page.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Si tienes una ACL muy extensa definida en tu <code>squid.conf</code>, es normal que al reiniciar o recargar Squid la interfaz de sqstat pierda temporalmente la conexión y muestre un error, ya que Squid todavía no ha terminado su proceso de arranque o recarga; simplemente espera uno o dos minutos a que el servicio se estabilice y luego presiona F5 para actualizar la página..
    </td>
  </tr>
</table>

### ANALYZER (SquidAnalyzer)

[![squidanalyzer](https://raw.githubusercontent.com/maravento/vault/master/proxymon/img/squidanalyzer-tab.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Analyzer is a web-based monitoring tool for real-time analysis of connections and network traffic on the Squid proxy server.
      <h4>Features</h4>
      <ul>
        <li>Real-time Squid proxy connection monitoring</li>
        <li>Active connections and users display</li>
        <li>Grouping by host or username</li>
        <li>Current and average bandwidth speed calculation</li>
        <li>IP to hostname resolution</li>
        <li>Connection duration tracking</li>
        <li>Data transfer size monitoring</li>
        <li>Auto-refresh capability</li>
        <li>Web-based interface</li>
        <li>Multiple server configuration support</li>
        <li>Detailed connection information display</li>
        <li>Session-based speed analytics</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      Analyzer es una herramienta web de monitoreo para análisis en tiempo real de conexiones y tráfico de red del servidor proxy Squid.
      <h4>Características</h4>
      <ul>
        <li>Monitoreo en tiempo real de conexiones Squid</li>
        <li>Visualización de conexiones activas y usuarios</li>
        <li>Agrupamiento por host o nombre de usuario</li>
        <li>Cálculo de velocidad de ancho de banda actual y promedio</li>
        <li>Resolución de IP a nombre de host</li>
        <li>Seguimiento de duración de conexiones</li>
        <li>Monitoreo del tamaño de transferencia de datos</li>
        <li>Capacidad de auto-actualización</li>
        <li>Interfaz basada en web</li>
        <li>Soporte para múltiples configuraciones de servidor</li>
        <li>Visualización detallada de información de conexión</li>
        <li>Análisis de velocidad basado en sesiones</li>
      </ul>
    </td>
  </tr>
</table>

#### Analyzer Task

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The installation script adds a task to the crontab to run every 10 minutes. You can change it according to your preferences.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script de instalación agrega una tarea al crontab para que se ejecute todos los días a las 2:00 AM. Puedes cambiarla según tus preferencias.
    </td>
  </tr>
</table>

```bash
sudo -u www-data crontab -e
0 2 * * * cd /var/www/proxymon/squidanalyzer && perl -I. ./squid-analyzer -d > /dev/null 2>&1
```

### PROXYMON LOGS

```bash
/var/log/apache2/proxymon_access.log
/var/log/apache2/proxymon_error.log
```

## ORIGINAL PROJECTS

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     This project incorporates and enhances components from multiple sources, building upon their legacies after discontinuation or stagnation. The details of the original projects are described below:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Este proyecto incorpora y mejora componentes de múltiples fuentes, continuando su legado tras su descontinuación o estancamiento. Los detalles de los proyectos originales se describen a continuación:
    </td>
  </tr>
</table>

| Project / Developer | Last Official Version | Unofficial Update | Additional |
| :-----------------: | :-------------------: | :---------------: | :--------: |
| **LightSquid** | [v1.8-7 (2009)](https://lightsquid.sourceforge.net/) | [v1.8.1 (2021)](https://github.com/finisky/lightsquid-1.8.1) | [Metro_tpl (2020)](https://www.sysadminsdecuba.com/2020/09/lightsquid/) |
| **SARG** | [v2.4.0 (2020-01-16)](https://sourceforge.net/projects/sarg/) | N/A | N/A |
| [Sqstat - Alex Samorukov](https://samm.kiev.ua/sqstat/) | [v1.20 (2006)](https://sourceforge.net/projects/sqstat/files/) | N/A | N/A |
| [SquidAnalyzer](https://squidanalyzer.darold.net/download.html) [github](https://github.com/darold/squidanalyzer) | [v6.6 (2017)](https://sourceforge.net/projects/squid-report/files/squid-report/6.6/) | N/A | N/A |

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
