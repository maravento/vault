# [Sqstat](https://www.maravento.com)

[![status-deprecated](https://img.shields.io/badge/status-deprecated-red.svg)](https://lightsquid.sourceforge.net/)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     <b>SqStat</b> is a script that allows you to verify the active connections of users. Use the cachemgr protocol to obtain information about the <a href="https://www.squid-cache.org/" target="_blank">Squid Proxy Server</a>.
    </td>
    <td width="50%">
     <b>SqStat</b> es un script que permite verificar las conexiones activas de los usuarios. Utiliza el protocolo cachemgr para obtener información de <a href="https://www.squid-cache.org/" target="_blank">Squid Proxy Server</a>.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/sqstat
```

## DATA SHEET

---

| Developer | Last Version | HowTo | Tested On |
| :---: | :---: | :---: | :---: |
| [Alex Samorukov](https://samm.kiev.ua/sqstat/) | [v1.20 (2006)](https://sourceforge.net/projects/sqstat/files/) | [Post (ESP)](https://www.maravento.com/2014/03/network-monitor.html) | Ubuntu 22.04 LTS x64, Squid v5.2|

### Important before using

<table width="100%">
  <tr>
    <td width="50%">
     If any IP addresses on your local network do not go through the Squid proxy, then they will not appear in the reports.
    </td>
    <td width="50%">
     Si alguna dirección IP de su red local no pasan por el proxy Squid, entonces no aparecerá en los reportes.
    </td>
  </tr>
</table>

## HOW TO INSTALL

---

```bash
wget -c https://raw.githubusercontent.com/maravento/vault/master/sqstat/sqstatsetup.sh && sudo chmod +x sqstatsetup.sh && sudo ./sqstatsetup.sh
```

## HOW TO USE

---

### Access

[http://localhost/sqstat/sqstat.php](http://localhost/sqstat/sqstat.php)

[![Image](https://raw.githubusercontent.com/maravento/vault/master/sqstat/img/sqstat.png)](https://www.maravento.com/)

### Auto refresh

Select at least 5 seconds: / Seleccione al menos 5 segundos:

[![Image](https://raw.githubusercontent.com/maravento/vault/master/sqstat/img/sqstat-auto.png)](https://www.maravento.com/)

<table width="100%">
  <tr>
    <td width="50%">
     When you restart/reload Squid, sqstat will lose the connection. Wait a minute and press the F5 key to reload the page.
    </td>
    <td width="50%">
     Al reiniciar/recargar Squid, sqstat perderá la conexión. Espere un minuto y pulsar la tecla F5 para recargar la página.
    </td>
  </tr>
</table>

[![Image](https://raw.githubusercontent.com/maravento/vault/master/sqstat/img/sqstat-f5.png)](https://www.maravento.com/)

### Squid conf

**Add: | Añadir:**

```bash
sudo nano /etc/squid/squid.conf

# Only allow cachemgr access from localhost
http_access deny manager !localhost
```

### Password

<table width="100%">
  <tr>
    <td width="50%">
     If you are going to use password, you must modify the following files:
    </td>
    <td width="50%">
     Si va a usar password, debe modificar los siguientes archivos:
    </td>
  </tr>
</table>

```bash
sudo nano /etc/squid/squid.conf
#  TAG: cachemgr_passwd
cachemgr_passwd my_password all

sudo nano /var/www/sqstat/config.inc.php
/* cachemgr_passwd in squid.conf. Leave blank to disable authorisation */
$cachemgr_passwd[0]="my_password";

sudo systemctl restart squid
sudo systemctl restart apache2
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
