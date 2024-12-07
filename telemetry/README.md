# [Tracking & Telemetry](https://www.maravento.com)

[![status-frozen](https://img.shields.io/badge/status-frozen-blue.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td width="50%">
     <b>Tracking & Telemetry</b> is a block list of URLs related to Telemetry & Tracking.
    </td>
    <td width="50%">
     <b>Tracking & Telemetry</b> es una lista de bloqueo de URLs relacionadas con Telemetría & Seguimiento.
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/telemetry
```

## IMPORTANT

---

<table width="100%">
  <tr>
    <td width="50%">
     This project is only for test purposes and may contain false positives. The debugging and updating process can take time and consume a lot of hardware resources and internet bandwidth. Use with discretion.
    </td>
    <td width="50%">
     Este proyecto es solo para propósitos de prueba y puede contener falsos positivos. El proceso de depuración y actualización puede tardar y consumir muchos recursos de hardware y ancho de banda de internet. Úselo con discreción.
    </td>
  </tr>
</table>

## DATA SHEET

---

|file|Lines|
|----|-----|
|[telemetry.txt](https://raw.githubusercontent.com/maravento/vault/master/telemetry/telemetry.txt)|89022|

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

### For DNSmasq

```bash
sed -r "s:^\.(.*):address=\1/0.0.0.0:g" telemetry.txt > telemetry_dnsmasq.txt
```

### For Hosts File for Windows

```bash
sed -r "s:^\.(.*):127.0.0.1 \1:g" telemetry.txt > telemetry_hosts.txt

```

## SOURCES

---

- [AlexanderOnischuk/DeleteTelemetryWin10](https://raw.githubusercontent.com/AlexanderOnischuk/DeleteTelemetryWin10/master/DeleteTelemetryWin10.bat)
- [cedws/apple-telemetry](https://raw.githubusercontent.com/cedws/apple-telemetry/master/blacklist)
- [changeme/Mikrotik/Microsoft telemetry block](https://gist.githubusercontent.com/changeme/a2e6aa686303eb47f3dc9f830fdae703/raw/24af43dd0fa9f920f10cdd5d2b3e74060596bf21/Mikrotik%2520-%2520Microsoft%2520telemetry%2520block)
- [crazy-max/WindowsSpyBlocker](https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy.txt)
- [crazy-max/WindowsSpyBlocker/v6](https://raw.githubusercontent.com/crazy-max/WindowsSpyBlocker/master/data/hosts/spy_v6.txt)
- [firebog.net/hosts/Easyprivacy](https://v.firebog.net/hosts/Easyprivacy.txt)
- [firebog.net/hosts/Prigent-Ads](https://v.firebog.net/hosts/Prigent-Ads.txt)
- [Forsaked/hosts](https://raw.githubusercontent.com/Forsaked/hosts/master/hosts)
- [Hurkamurka/Xiaomi-Telemetry-Blocklist-2](https://raw.githubusercontent.com/Hurkamurka/Xiaomi-Telemetry-Blocklist-2/master/Xiaomi_Telemetry_paste.txt)
- [j-42/hosts](https://raw.githubusercontent.com/j-42/hosts/master/hosts)
- [JustinLloyd/hosts](https://gist.githubusercontent.com/JustinLloyd/f3609460e6ee14ca6a8a/raw/28bbbdb2a2810369da8c112e23e351c8300e1e78/hosts)
- [kaabir/AdBlock_Hosts](https://raw.githubusercontent.com/kaabir/AdBlock_Hosts/master/hosts)
- [kevle1/Windows-Telemetry-Blocklist/windowsblock](https://raw.githubusercontent.com/kevle1/Windows-Telemetry-Blocklist/master/windowsblock.txt)
- [kevle1/Windows-Telemetry-Blocklist/xiaomiblock](https://raw.githubusercontent.com/kevle1/Xiaomi-Telemetry-Blocklist/master/xiaomiblock.txt)
- [mboutolleau/block-samsung-tv-telemetry](https://raw.githubusercontent.com/mboutolleau/block-samsung-tv-telemetry/master/samsung_tv_telemetry_urls.txt)
- [PiHoleBlocklist/Amazon Fire TV](https://perflyst.github.io/PiHoleBlocklist/AmazonFireTV.txt)
- [PiHoleBlocklist/Android Tracking](https://perflyst.github.io/PiHoleBlocklist/android-tracking.txt)
- [PiHoleBlocklist/Session Reply](https://perflyst.github.io/PiHoleBlocklist/SessionReplay.txt)
- [PiHoleBlocklist/Smart TV AGH](https://perflyst.github.io/PiHoleBlocklist/SmartTV-AGH.txt)
- [PiHoleBlocklist/Smart TV](https://perflyst.github.io/PiHoleBlocklist/SmartTV.txt)
- [quidsup/notrack-blocklists](https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-blocklist.txt)
- [quidsup/notrack-malware](https://gitlab.com/quidsup/notrack-blocklists/raw/master/notrack-malware.txt)
- [root-host/Windows-Telemetry](https://raw.githubusercontent.com/root-host/Windows-Telemetry/master/domains3)
- [simeononsecurity/System-Wide-Windows-Ad-Blocker](https://raw.githubusercontent.com/simeononsecurity/System-Wide-Windows-Ad-Blocker/main/Files/hosts.txt)
- [StevenBlack/hosts](https://raw.githubusercontent.com/StevenBlack/hosts/master/data/add.2o7Net/hosts)
- [szotsaki/windows-telemetry-removal](https://raw.githubusercontent.com/szotsaki/windows-telemetry-removal/master/WindowsTelemetryRemoval.bat)
- [W4RH4WK/Debloat-Windows-10](https://raw.githubusercontent.com/W4RH4WK/Debloat-Windows-10/master/scripts/block-telemetry.ps1)

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
