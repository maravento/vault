# [Gateproxy](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> is a simple proxy/firewall server for managing Pyme's LAN networks. The installation and configuration script is fully automated and customizable according to the needs of the administrator or organization, with minimal interaction during the process. It can be implemented in physical servers or VMs, for greater flexibility and portability.
    </td>
    <td style="width: 50%; vertical-align: top;">
     <b>Gateproxy</b> es un sencillo servidor proxy/firewall para administrar redes Pyme's LAN. El script de instalación y configuración es totalmente automatizado y personalizable, de acuerdo a las necesidades del administrador u organización, con una interacción mínima durante proceso. Puede ser implementado en servidores físicos o VMs, para mayor flexibilidad y portabilidad.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python gitfolder.py https://github.com/maravento/vault/gateproxy
```

## DATA SHEET

---

| OS | CPU | NIC | RAM | Storage | HowTO |
| :---: | :---: | :---: | :---: | :---: | :---: |
| Ubuntu 24.04.x | 4+ cores (≥ 3.0 GHz) | 2 (WAN & LAN) | 16-32 GB (4 GB cache_mem) | 100 GB SSD (cache_dir rock) | [PDF](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/howto/gateproxy.pdf) |

## HOW TO USE

---

**Open the terminal and run: | Abra el terminal y ejecute:**

```bash
wget -q -N https://raw.githubusercontent.com/maravento/vault/master/gateproxy/gateproxy.sh && sudo chmod +x gateproxy.sh && sudo ./gateproxy.sh
```

![Gateproxy](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/img/gateproxy.png)

## IMPORTANT

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy is a script under development and may contain bugs, which will be fixed as soon as possible. It may also contain some programs for testing purposes. Therefore, its use in high-volume networks or environments is not recommended.
    </td>
    <td style="width: 50%; vertical-align: top;">
     Gateproxy es un script en desarrollo y puede contener fallos, los cuales serán corregidos a la brevedad posible y contener algunos programas para propósitos de pruebas. Por tanto, no se recomienda su uso en redes o entornos de alta productividad.
    </td>
  </tr>
</table>

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
