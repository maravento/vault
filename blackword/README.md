# [BlackWord](https://www.maravento.com/)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     <b>BlackWord</b> is an experimental project designed to block malicious patterns, including file extensions associated with ransomware, malware, and other cyber threats. It aims to prevent the spread of these patterns using access control lists and custom rules.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     <b>BlackWord</b> es un proyecto experimental diseñado para bloquear patrones maliciosos, incluyendo extensiones de archivo asociadas a ransomware, malware y otras amenazas cibernéticas. Su objetivo es prevenir la propagación de estos patrones mediante listas de control de acceso y reglas personalizadas.
    </td>
  </tr>
</table>

## DEPENDENCIES

---

```bash
bash samba squid
```

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/blackword
```

## ⚠️ WARNING: BEFORE YOU CONTINUE

---

***RESULT IS NOT GUARANTEED. USE IT AT YOUR OWN RISK | NO SE GARANTIZA EL RESULTADO. USELO BAJO SU PROPIO RIESGO***

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     This project contains files that may generate false positives.
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Este proyecto contiene archivos que pueden generar falsos positivos.
    </td>
  </tr>
</table>

## HOW TO USE

---

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Open the terminal and run:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Abra el terminal y ejecute:
    </td>
  </tr>
</table>

```bash
cd blackword
chmod +x blackword.sh
./blackword.sh
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     The script will generate two files: <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackword/bw_squid.txt" target="_blank">bw_squid.txt</a> and <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackword/bw_smb.txt" target="_blank">bw_smb.txt</a>. </br>
     Both contain the malicious patterns and extensions to block in Samba and Squid. </br>
    </td>
    <td style="width: 50%; white-space: nowrap;">
     El script generará dos archivos: <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackword/bw_squid.txt" target="_blank">bw_squid.txt</a> y <a href="https://raw.githubusercontent.com/maravento/vault/refs/heads/master/blackword/bw_smb.txt" target="_blank">bw_smb.txt</a>. </br>
     Ambos contienen los patrones y extensiones maliciosas para bloquear en Samba y Squid.</br>
    </td>
  </tr>
</table>

### Squid Rule (ACL for Blocking Extensions/Patterns)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Modify your <code>/etc/squid/squid.conf</code> file and add the ACL <code>bw_squid.txt</code>:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Modifique su archivo <code>/etc/squid/squid.conf</code> y agregue la ACL <code>bw_squid.txt</code>:
    </td>
  </tr>
</table>

Tested on: Squid Cache v5x, 6x

```bash
acl blackword urlpath_regex -i "/etc/acl/bw_squid.txt"
http_access deny blackword
deny_info ERR_ACCESS_DENIED blackword
```

#### Squid Optional Rules

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     For better protection, we suggest you consider adding the following rules:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Para una mejor protección, sugerimos que considere agregar las siguientes reglas:
    </td>
  </tr>
</table>

Path (Change it with yours): /etc/acl

```bash
# Block: mime_type
acl blockmime rep_mime_type -i "/etc/acl/blockmime.txt"
http_reply_access deny workdays blockmime
deny_info ERR_ACCESS_DENIED blockmime

# Block: ext
acl blockext urlpath_regex -i "/etc/acl/blockext.txt"
http_access deny workdays blockext
deny_info ERR_ACCESS_DENIED blockext

# Block: punycode
acl punycode dstdom_regex -i \.xn--.*
http_access deny punycode
deny_info ERR_ACCESS_DENIED punycode

# Block: Invalid file extensions 
acl invalid_ext urlpath_regex -i \.[a-zA-Z0-9]+(\.[a-zA-Z0-9]+)*$
http_access deny invalid_ext
deny_info ERR_ACCESS_DENIED invalid_ext

# Block: IP/CIDR
acl no_ip url_regex -i [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}
http_access deny workdays no_ip
deny_info ERR_ACCESS_DENIED no_ip
```

### Samba Rule (ACL for Veto Files)

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
     Modify your <code>/etc/samba/smb.conf</code> file and add <code>bw_smb.txt</code>. It can be added to the <code>[global]</code> section or to a specific shared folder. This file will add the <code>veto files =</code> directive to block patterns and extensions in Samba. Example:
    </td>
    <td style="width: 50%; white-space: nowrap;">
     Modifique su archivo <code>/etc/samba/smb.conf</code> y agregue <code>bw_smb.txt</code>. Puede ser agregado a la sección <code>[global]</code> o a una carpeta compartida específica. Este archivo agregará la directiva <code>veto files =</code> para bloquear los patrones y extensiones en Samba. Ejemplo:
    </td>
  </tr>
</table>

```bash
   include = /path_to/bw_smb.txt
```

## SOURCES

---

- [dannyroemhild - ransomware-fileext-list](https://github.com/dannyroemhild/ransomware-fileext-list/blob/master/fileextlist.txt)
- [eshlomo1 - Ransomware-NOTE](https://github.com/eshlomo1/Ransomware-NOTE/blob/main/ransomware-extension-list.txt)
- [giacomoarru - ransomware-extensions-2024](https://github.com/giacomoarru/ransomware-extensions-2024/blob/main/ransomware-extensions.txt)
- [kinomakino - ransomware_file_extensions](https://github.com/kinomakino/ransomware_file_extensions/blob/master/extensions.csv)
- [nspoab - malicious_extensions](https://github.com/nspoab/malicious_extensions/blob/main/list1)

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
