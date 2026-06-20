# [DoFi](https://github.com/maravento)

[![status-release-candidate](https://img.shields.io/badge/status-release_candidate-skyblue.svg)](https://github.com/maravento)

<!-- markdownlint-disable MD033 -->

<table>
  <tr>
    <td style="width: 50%; vertical-align: top;">
        Domain Filtering
    </td>
    <td style="width: 50%; vertical-align: top;">
        Filtrado de Dominios
    </td>
  </tr>
</table>

## DOWNLOAD PROJECT

---

```bash
# Download
wget -qO gitfolder.py https://raw.githubusercontent.com/maravento/vault/master/scripts/python/gitfolder.py
chmod +x gitfolder.py
python3 gitfolder.py https://github.com/maravento/vault/dofi

# Install
cd dofi
python domfilter.py
```

### Requirements

- Python 3.12.3
- Bash 5.2.21

### Tested on

Ubuntu 22.04/24.04 x64

### Important before use

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
        Ensure the input list has no <code>http://</code>, <code>https://</code>, or <code>www.</code> prefixes.
    </td>
    <td style="width: 50%; vertical-align: top;">
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
    <td style="width: 50%; vertical-align: top;">
        - Downloads public suffix TLDs from multiple sources.<br>
        - Removes invalid or duplicate TLDs.<br>
        - Filters domains to ensure they end with a valid TLD.<br>
        - Remove overlapping domains.<br>
        - Excludes duplicates from previously validated domains.<br>
        - Outputs results to a file.
    </td>
    <td style="width: 50%; vertical-align: top;">
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
    <td style="width: 50%; vertical-align: top;">
        Replace <code>mylst.txt</code> with the name of your domain list:
    </td>
    <td style="width: 50%; vertical-align: top;">
        Reemplace <code>mylst.txt</code> con el nombre de su lista de dominios:
    </td>
  </tr>
</table>

```bash
python domfilter.py --input mylst.txt
```

#### Python Optional Parameters

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;"> 
        By default, output goes to <code>output.txt</code> and removed lines to <code>removed.txt</code>. <br> 
        You can customize your output with: <br>
    </td>
    <td style="width: 50%; vertical-align: top;"> 
        De forma predeterminada, la salida va a <code>output.txt</code> y las líneas eliminadas a <code>removed.txt</code>. <br>
        Puede personalizar su salida con: <br>
    </td>
  </tr>
</table>

```bash
python domfilter.py --input mylst.txt --output outlst.txt --removed removelst.txt
```

#### TLD Includes

ccTLDs, gTLDs, sTLDs, eTLDs, and 4LDs (file: `tlds.txt`)

### Domains Check with Host Command

[Domains Check with Host](https://raw.githubusercontent.com/maravento/vault/master/dofi/domcheck.sh)

#### What Does The Bash Script Do?

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      This script checks if each domain exists, using the host command, and cleans the input list, separating the output as follows:<br>
      - <code>hit.txt</code>: existing domains from your list.<br>
      - <code>fault.txt</code>: non-existent domains removed.<br>
      - <code>outdiff.txt</code>: Difference between input and output.<br>
    </td>
    <td style="width: 50%; vertical-align: top;">
      Este script verifica si cada dominio existe, con el comando host y limpia la lista de entrada, separando la salida de la siguiente manera:<br>
      - <code>hit.txt</code>: dominios existentes de su lista.<br>
      - <code>fault.txt</code>: dominios inexistentes eliminados.<br>
      - <code>outdiff.txt</code>: diferencia entre entrada y salida.<br>
    </td>
  </tr>
</table>

#### Using Bash Script

```bash
chmod +x domcheck.sh
./domcheck.sh my_domain_list.txt
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
        Replace <code>my_domain_list.txt</code> with your input list
    </td>
    <td style="width: 50%; vertical-align: top;">
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
    <td style="width: 50%; vertical-align: top;"> 
        Replace <code>50</code> with the number of parallel processes. <br>
        If you provide no argument, by default, it will use <code>nproc × 4</code> parallel processes. <br>
    </td>
    <td style="width: 50%; vertical-align: top;"> 
        Reemplace <code>50</code> con el número de procesos paralelos. <br> 
        Si no proporciona argumento, por defecto, usará <code>nproc × 4</code> procesos paralelos. <br>
    </td>
  </tr>
</table>

### Simple DNS Domain Checker

[Simple DNS Domain Checker](https://raw.githubusercontent.com/maravento/vault/master/dofi/simplecheck.sh)

#### What Does The Bash Script Do?

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      A lightweight alternative to <code>domcheck.sh</code> for quick, one-pass DNS resolution checks. Unlike <code>domcheck.sh</code>, it does not retry failed domains, does not sanitize the input list, and does not produce a diff file. It assumes the input is already clean and is best suited for small to medium lists.<br><br>
      Output files:<br>
      - <code>exists.txt</code>: Domains that successfully resolved.<br>
      - <code>not_exists.txt</code>: Domains that did not resolve.<br>
    </td>
    <td style="width: 50%; vertical-align: top;">
      Alternativa ligera a <code>domcheck.sh</code> para verificaciones DNS rápidas en un solo paso. A diferencia de <code>domcheck.sh</code>, no reintenta dominios fallidos, no sanitiza la lista de entrada y no produce un archivo diff. Asume que la entrada ya está limpia y es ideal para listas pequeñas o medianas.<br><br>
      Archivos de salida:<br>
      - <code>exists.txt</code>: Dominios que resolvieron correctamente.<br>
      - <code>not_exists.txt</code>: Dominios que no resolvieron.<br>
    </td>
  </tr>
</table>

#### Configuration

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Edit the <code>list</code> variable inside the script to set your input file (default: <code>mylist.txt</code>). Parallel execution uses <code>nproc × 4</code> processes automatically.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Edite la variable <code>list</code> dentro del script para definir su archivo de entrada (por defecto: <code>mylist.txt</code>). La ejecución paralela usa <code>nproc × 4</code> procesos automáticamente.
    </td>
  </tr>
</table>

#### Using Bash Script

```bash
# Edit the list variable inside the script first
nano simplecheck.sh  # set list="your_domain_list.txt"

chmod +x simplecheck.sh
./simplecheck.sh
```

#### Comparison: simplecheck.sh vs domcheck.sh

| Feature / Característica | simplecheck.sh | domcheck.sh |
|---|---|---|
| DNS passes / Pasadas DNS | 1 | 2 (retries failures / reintenta fallos) |
| Input sanitization / Sanitización de entrada | No | Yes / Sí |
| Resumable on interrupt / Reanudable tras interrupción | No | Yes / Sí (`dnslookup` cache) |
| Output diff file / Archivo diff de salida | No | Yes / Sí (`outdiff.txt`) |
| Input file / Archivo de entrada | Hardcoded variable / Variable interna | CLI argument / Argumento CLI |
| Best for / Ideal para | Small/quick lists / Listas pequeñas y rápidas | Large or untrusted lists / Listas grandes o sin limpiar |

## SOURCES

---

- [tlds-alpha-by-domain](https://data.iana.org/TLD/tlds-alpha-by-domain.txt)
- [tldsappx](https://github.com/maravento/blackweb/blob/master/bwupdate/lst/tldsappx.txt)
- [public_suffix_list](https://github.com/publicsuffix/list/blob/master/public_suffix_list.dat)
- [supported_gtlds](https://www.whoisxmlapi.com/support/supported_tlds.php?ts=gp)

## DISCLAIMER

---

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
