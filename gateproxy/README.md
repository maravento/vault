# [Gateproxy](https://www.maravento.com)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

**Gateproxy** is a simple proxy/firewall server for managing Pyme's [LAN](https://en.wikipedia.org/wiki/Local_area_network) networks. The installation and configuration script is fully automated and customizable according to the needs of the administrator or organization, with minimal interaction during the process. It can be implemented in physical servers or VMs, for greater flexibility and portability.

**Gateproxy** es un sencillo servidor proxy/firewall para administrar redes Pyme's [LAN](https://es.wikipedia.org/wiki/Red_de_%C3%A1rea_local). El script de instalación y configuración es totalmente automatizado y personalizable, de acuerdo a las necesidades del administrador u organización, con una interacción mínima durante proceso. Puede ser implementado en servidores físicos o VMs, para mayor flexibilidad y portabilidad.

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/gateproxy"
```

## DATA SHEET

---

|OS|CPU|Net Interfaces|RAM for [Squid](http://www.squid-cache.org/)|HDD/SSD for [Squid](http://www.squid-cache.org/)|HowTO|
| :---: | :---: | :---: | :---: | :---: | :---: |
|Ubuntu 22.04 x64|Intel(R) Compatible Up to 1.30GHz|Public and Local|4 GB|100 GB|[PDF](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/howto/gateproxy.pdf)|

## HOW TO USE

---

Open the terminal and run: / Abra el terminal y ejecute:

```bash
wget -q -N https://raw.githubusercontent.com/maravento/vault/master/gateproxy/gateproxy.sh && sudo chmod +x gateproxy.sh && sudo ./gateproxy.sh
```

![Gateproxy](https://raw.githubusercontent.com/maravento/vault/master/gateproxy/img/gateproxy.png)

## IMPORTANT

---

Gateproxy is an experimental script and may contain bugs, which will be documented or fixed where possible and contain some programs for testing purposes. Therefore, it is not recommended for use in networks or high productivity environments. / Gateproxy es un script experimental y puede contener fallos, los cuales serán documentados o corregidos en lo posible y contener algunos programas para propósitos de pruebas. Por tanto, no se recomienda su uso en redes o entornos de alta productividad.

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
