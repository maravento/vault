# [Tracking & Telemetry](https://www.maravento.com)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

**Tracking & Telemetry** is a list of URLs related to Telemetry & Tracking for Linux

**Tracking & Telemetry** es una lista de URLs relacionadas con telemetría y seguimiento para Linux.

## GIT CLONE

---

```bash
sudo apt install -y git subversion
svn export "https://github.com/maravento/vault/trunk/telemetry"
```

## IMPORTANT

---

This project is only for test purposes and may contain false positives. / Este proyecto es solo para fines de prueba y puede contener falsos positivos.

## DATA SHEET

---

|file|Lines|
|----|-----|
|[telemetry.txt](https://raw.githubusercontent.com/maravento/vault/master/telemetry/telemetry.txt)|260149|

## HOW TO USE

---

### Download

```bash
wget -q -N https://raw.githubusercontent.com/maravento/vault/master/telemetry/telemetry.txt
```

### Update & Debug

```bash
wget -q -N https://raw.githubusercontent.com/maravento/vault/master/telemetry/debug.sh && chmod +x debug.sh && ./debug.sh
```

### Convert To

For DNSmasq:

```bash
sed -r "s:^\.(.*):address=\1/0.0.0.0:g" telemetry.txt > telemetry_dnsmasq.txt
```

For Hosts File for Windows (choose between 127.0.0.1 or 0.0.0.0):

```bash
sed -r "s:^\.(.*):127.0.0.1 \1:g" telemetry.txt > telemetry_hosts.txt

# or

sed "s:^\.\(.*\):127.0.0.0 \1:g" telemetry.txt > telemetry_hosts.txt
```

## SOURCES

---

- [changeme/Mikrotik/Microsoft telemetry block](https://gist.githubusercontent.com/changeme/a2e6aa686303eb47f3dc9f830fdae703/raw/24af43dd0fa9f920f10cdd5d2b3e74060596bf21/Mikrotik%2520-%2520Microsoft%2520telemetry%2520block)
- [JustinLloyd/hosts](https://gist.githubusercontent.com/JustinLloyd/f3609460e6ee14ca6a8a/raw/28bbbdb2a2810369da8c112e23e351c8300e1e78/hosts)
- [quidsup/notrack-blocklists](https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-blocklist.txt)
- [quidsup/notrack-malware](https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt)
- [AlexanderOnischuk/DeleteTelemetryWin10](https://raw.githubusercontent.com/AlexanderOnischuk/DeleteTelemetryWin10/master/DeleteTelemetryWin10.bat)
- [cedws/apple-telemetry](https://raw.githubusercontent.com/cedws/apple-telemetry/master/blacklist)
- [crazy-max/WindowsSpyBlocker](https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt)
- [crazy-max/WindowsSpyBlocker/v6](https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy_v6.txt)
- [Forsaked/hosts](https://raw.githubusercontent.com/Forsaked/hosts/master/hosts)
- [Hurkamurka/Xiaomi-Telemetry-Blocklist-2](https://raw.githubusercontent.com/Hurkamurka/Xiaomi-Telemetry-Blocklist-2/master/Xiaomi_Telemetry_paste.txt)
- [j-42/hosts](https://raw.githubusercontent.com/j-42/hosts/master/hosts)
- [kaabir/AdBlock_Hosts](https://raw.githubusercontent.com/kaabir/AdBlock_Hosts/master/hosts)
- [kevle1/Windows-Telemetry-Blocklist/windowsblock](https://raw.githubusercontent.com/kevle1/Windows-Telemetry-Blocklist/master/windowsblock.txt)
- [kevle1/Windows-Telemetry-Blocklist/xiaomiblock](https://raw.githubusercontent.com/kevle1/Xiaomi-Telemetry-Blocklist/master/xiaomiblock.txt)
- [mboutolleau/block-samsung-tv-telemetry](https://raw.githubusercontent.com/mboutolleau/block-samsung-tv-telemetry/master/samsung_tv_telemetry_urls.txt)
- [root-host/Windows-Telemetry](https://raw.githubusercontent.com/root-host/Windows-Telemetry/master/domains3)
- [simeononsecurity/System-Wide-Windows-Ad-Blocker](https://raw.githubusercontent.com/simeononsecurity/System-Wide-Windows-Ad-Blocker/main/Files/hosts.txt)
- [StevenBlack/hosts](https://raw.githubusercontent.com/StevenBlack/hosts/master/data/add.2o7Net/hosts)
- [szotsaki/windows-telemetry-removal](https://raw.githubusercontent.com/szotsaki/windows-telemetry-removal/master/WindowsTelemetryRemoval.bat)
- [W4RH4WK/Debloat-Windows-10](https://raw.githubusercontent.com/W4RH4WK/Debloat-Windows-10/master/scripts/block-telemetry.ps1)
- [firebog.net/hosts/Easyprivacy](https://v.firebog.net/hosts/Easyprivacy.txt)
- [firebog.net/hosts/Prigent-Ads](https://v.firebog.net/hosts/Prigent-Ads.txt)

## LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

© 2023 [Maravento Studio](https://www.maravento.com)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
