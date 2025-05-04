# [DoFi](https://www.maravento.com)

[![status-experimental](https://img.shields.io/badge/status-experimental-orange.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        Domain Filtering
    </td>
    <td style="width: 50%; white-space: nowrap;">
        Filtrado de Dominios
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
sudo apt install -y python-is-python3
wget -qO gitfolderdl.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolderdl.py
chmod +x gitfolderdl.py
python gitfolderdl.py https://github.com/maravento/vault/dofi
```

### Requirements

- Python 3.12.3
- Bash 5.2.21

### Tested on

Ubuntu 22.04/24.04 x64

### Important before use

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        Ensure the input list has no <code>http://</code>, <code>https://</code>, or <code>www.</code> prefixes.
    </td>
    <td style="width: 50%; white-space: nowrap;">
        Asegúrese de que la lista de entrada no tenga prefijos <code>http://</code>, <code>https://</code> o <code>www.</code>.
    </td>
  </tr>
</table>

## HOW TO USE

---

### Domain Filter

[Domain Filter for Removing Overlapping Domains and TLD Validation](https://raw.githubusercontent.com/maravento/vault/master/dofi/domfilter.py)

#### What Does The Python Script Do?

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        - Downloads public suffix TLDs from multiple sources.<br>
        - Removes invalid or duplicate TLDs.<br>
        - Filters domains to ensure they end with a valid TLD.<br>
        - Remove overlapping domains.<br>
        - Excludes duplicates from previously validated domains.<br>
        - Outputs results to a file.
    </td>
    <td style="width: 50%; white-space: nowrap;">
        - Descarga TLD de sufijo público de varias fuentes.<br>
        - Elimina TLD no válidos o duplicados.<br>
        - Filtra dominios para garantizar que terminen con un TLD válido.<br>
        - Elimina dominios superpuestos.<br>
        - Excluye duplicados de dominios previamente validados.<br>
        - Envía los resultados a un archivo.<br>
    </td>
  </tr>
</table>

#### Using Python Script

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        Replace <code>mylst.txt</code> with the name of your domain list:
    </td>
    <td style="width: 50%; white-space: nowrap;">
        Reemplace <code>mylst.txt</code> con el nombre de su lista de dominios:
    </td>
  </tr>
</table>

```bash
wget -qO domfilter.py https://raw.githubusercontent.com/maravento/vault/master/dofi/domfilter.py
python domfilter.py --input mylst.txt
```

#### Python Optional Parameters

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;"> 
        By default, output goes to <code>output.txt</code> and removed lines to <code>removed.txt</code>. <br> 
        You can customize your output with: <br>
    </td>
    <td style="width: 50%; white-space: nowrap;"> 
        De forma predeterminada, la salida va a <code>output.txt</code> y las líneas eliminadas a <code>removed.txt</code>. <br>
        Puede personalizar su salida con: <br>
    </td>
  </tr>
</table>

```bash
python domfilter.py --input mylst.txt --output outlst.txt --remove removelst.txt
```

#### TLD Includes

ccTLDs, gTLDs, sTLDs, eTLDs, and 4LDs (file: `tlds.txt`)

### Domains Check with Host Command

[Domains Check with Host](https://raw.githubusercontent.com/maravento/vault/master/dofi/domcheck.sh)

#### What Does The Bash Script Do?

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
      This script checks if each domain exists, using the host command, and cleans the input list, separating the output as follows:<br>
      - <code>hit.txt</code>: existing domains from your list.<br>
      - <code>fault.txt</code>: non-existent domains removed.<br>
      - <code>outdiff.txt</code>: Difference between input and output.<br>
    </td>
    <td style="width: 50%; white-space: nowrap;">
      Este script verifica si cada dominio existe, con el comando host y limpia la lista de entrada, separando la salida de la siguiente manera:<br>
      - <code>hit.txt</code>: dominios existentes de su lista.<br>
      - <code>fault.txt</code>: dominios inexistentes eliminados.<br>
      - <code>outdiff.txt</code>: diferencia entre entrada y salida.<br>
    </td>
  </tr>
</table>

#### Using Bash Script

```bash
wget -qO domcheck.sh https://raw.githubusercontent.com/maravento/vault/master/dofi/domcheck.sh
chmod +x domcheck.sh
./domcheck.sh my_domain_list.txt
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;">
        Replace <code>my_domain_list.txt</code> with your input list
    </td>
    <td style="width: 50%; white-space: nowrap;">
        Reemplace <code>my_domain_list.txt</code> con su lista de entrada
    </td>
  </tr>
</table>

#### Bash Optional Parameters

```bash
./domcheck.sh my_domain_list.txt 50
```

<table width="100%">
  <tr>
    <td style="width: 50%; white-space: nowrap;"> 
        Replace <code>50</code> with the number of parallel processes. <br>
        If you provide no argument, by default, it will process 100 in parallel. <br>
    </td>
    <td style="width: 50%; white-space: nowrap;"> 
        Reemplace <code>50</code> con el número de procesos paralelos. <br> 
        Si no proporciona argumento, por defecto, procesará 100 en paralelo. <br>
    </td>
  </tr>
</table>

## SOURCES

---

- [tlds-alpha-by-domain](https://data.iana.org/TLD/tlds-alpha-by-domain.txt)
- [tldsappx](https://github.com/maravento/blackweb/blob/master/bwupdate/lst/tldsappx.txt)
- [public_suffix_list](https://github.com/publicsuffix/list/blob/master/public_suffix_list.dat)
- [supported_gtlds](https://www.whoisxmlapi.com/support/supported_gtlds.php)

## PROJECT LICENSES

---

[![GPL-3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl.txt)
[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC_BY--SA_4.0-lightgrey.svg)](https://creativecommons.org/licenses/by-sa/4.0/)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
