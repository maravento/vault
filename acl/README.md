<!--
ACL lists documentation
FILE: acl/README.md
-->

# [ACL](https://github.com/maravento)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento)

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Shared firewall lists, for any project to download.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Listas de firewall compartidas, para que cualquier proyecto las descargue.
    </td>
  </tr>
</table>

<!-- markdownlint-disable MD033 -->

## REQUIREMENTS

---

### Software

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The lists are plain text. They are loaded with <code>ipset</code> and applied with <code>iptables</code>.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Las listas son texto plano. Se cargan con <code>ipset</code> y se aplican con <code>iptables</code>.
    </td>
  </tr>
</table>

## HOW TO USE

---

### Download

```bash
wget -qO bogons.txt https://raw.githubusercontent.com/maravento/vault/master/acl/bogons.txt
wget -qO blockports.txt https://raw.githubusercontent.com/maravento/vault/master/acl/blockports.txt
```

## HOW IT WORKS

---

### Lists

| List | Description | Descripción |
| --- | --- | --- |
| [bogons.txt](https://raw.githubusercontent.com/maravento/vault/master/acl/bogons.txt) | Reserved and unroutable IPv4 ranges, one per line. A line starting with `#` is disabled. | Rangos IPv4 reservados y no enrutables, uno por línea. Una línea que empieza por `#` está desactivada. |
| [blockports.txt](https://raw.githubusercontent.com/maravento/vault/master/acl/blockports.txt) | Ports to block, one per line. | Puertos que se bloquean, uno por línea. |

> Each project decides how to apply these lists. Check the README of the project that downloads them.
>
> Cada proyecto decide cómo aplicar estas listas. Consulte el README del proyecto que las descarga.

## NOTICE

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <strong>This repository</strong>
      <ul>
        <li>May include third-party components.</li>
        <li>Does not accept Pull Requests. Changes must be proposed via Issues.</li>
        <li>This project does not support backward compatibility. New versions may require configuration changes or reinstallation.</li>
      </ul>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <strong>Este repositorio</strong>
      <ul>
        <li>Puede incluir componentes de terceros.</li>
        <li>No acepta Pull Requests. Los cambios deben proponerse mediante Issues.</li>
        <li>Este proyecto no soporta retrocompatibilidad. Las nuevas versiones pueden requerir cambios de configuración o una reinstalación.</li>
      </ul>
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
