# [CaptureFox](https://github.com/maravento)

[![status-beta](https://img.shields.io/badge/status-beta-magenta.svg)](https://github.com/maravento/vault)

<!-- markdownlint-disable MD033 -->

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <b>CaptureFox</b> records your screen or window, camera, microphone, and a Linux system audio input. The extension interface is entirely in English. Recordings stay in your browser until you download or delete them. No accounts, subscriptions, telemetry, or external recording servers are used.
    </td>
    <td style="width: 50%; vertical-align: top;">
      <b>CaptureFox</b> graba pantalla o ventana, cámara, micrófono y una entrada de audio interno en Linux. Toda la interfaz de la extensión está en inglés. Las grabaciones permanecen en el navegador hasta que las descargas o eliminas. No utiliza cuentas, suscripciones, telemetría ni servidores externos de grabación.
    </td>
  </tr>
</table>

![capturefox](https://raw.githubusercontent.com/maravento/vault/master/capturefox/img/capturefox.png)

## FEATURES

---

| Feature | Description | Descripción |
|---|---|---|
| Video sources | Record a screen/window, camera, or screen with a camera overlay. | Graba pantalla/ventana, cámara o pantalla con cámara superpuesta. |
| Audio sources | Select microphone, system audio, both, or no audio. | Selecciona micrófono, audio interno, ambos o sin audio. |
| Recording controls | Pause/resume and adjust microphone/system audio gain separately. | Pausa, continúa y ajusta el volumen del micrófono y del audio interno por separado. |
| Video quality | Choose original resolution, 1080p, or 720p and request 30 or 60 fps. Actual quality depends on the device and source. | Elige resolución original, 1080p o 720p y solicita 30 o 60 fps. La calidad real depende del dispositivo y la fuente. |
| Local library | Play recordings, download WebM files, and delete recordings manually. | Reproduce grabaciones, descarga archivos WebM y elimina grabaciones manualmente. |
| Interrupted sessions | Recover chunks saved before a session was interrupted. | Recupera los fragmentos guardados antes de una interrupción. |

## REQUIREMENTS

---

| Component | Description | Descripción |
|---|---|---|
| Browser | Firefox desktop 142 or later. | Firefox de escritorio 142 o posterior. |
| Camera and microphone | Corresponding devices and browser permissions are required for these modes. | Estos modos requieren los dispositivos y permisos correspondientes. |
| System audio | Linux, Python 3, `pactl`, and PulseAudio or a compatible server. Use the included helper. | Linux, Python 3, `pactl` y PulseAudio o un servidor compatible. Utiliza la herramienta incluida. |
| Development | Node.js 24 or later for tests; Python 3 for packaging and helper tests. | Node.js 24 o posterior para pruebas; Python 3 para empaquetado y pruebas de la herramienta. |

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Screen/camera recording requires neither npm nor Python. The Linux helper is only needed for the virtual system audio input. It does not require sudo or change default audio devices. Other operating systems and full browser/device combinations have not been verified.
    </td>
    <td style="width: 50%; vertical-align: top;">
      La grabación de pantalla/cámara no requiere npm ni Python. La herramienta Linux solo se necesita para la entrada virtual de audio interno. No necesita sudo ni cambia los dispositivos predeterminados. No se verificaron otros sistemas operativos ni todas las combinaciones de navegador y dispositivos.
    </td>
  </tr>
</table>

### Tested environment

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Tested on Firefox 156.0.1 (64 bits), Ubuntu 24.04.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Probado en Firefox 156.0.1 (64 bits), Ubuntu 24.04.
    </td>
  </tr>
</table>

## HOW TO USE

---


### Load temporarily in Firefox

| Step | Action | Acción |
|---|---|---|
| 1 | Open the [vault repository](https://github.com/maravento/vault) on GitHub. | Abre el [repositorio vault](https://github.com/maravento/vault) en GitHub. |
| 2 | Click **Code → Download ZIP**. | Pulsa **Code → Download ZIP**. |
| 3 | Extract the downloaded ZIP. | Extrae el ZIP descargado. |
| 4 | Choose one file: `capturefox/extension/manifest.json` or `capturefox/capturefox-0.1.1.xpi` inside the extracted folder. | Elige un archivo: `capturefox/extension/manifest.json` o `capturefox/capturefox-0.1.1.xpi` dentro de la carpeta extraída. |
| 5 | Open Firefox. | Abre Firefox. |
| 6 | Enter `about:debugging#/runtime/this-firefox` in the address bar and press **Enter**. | Escribe `about:debugging#/runtime/this-firefox` en la barra de direcciones y pulsa **Enter**. |
| 7 | Click **Load Temporary Add-on**. | Pulsa **Cargar complemento temporal**. |
| 8 | Select the file chosen in step 4 and open it. Both `manifest.json` and the XPI can be loaded temporarily. Do not extract the XPI. | Selecciona el archivo elegido en el paso 4 y ábrelo. Tanto `manifest.json` como el XPI se pueden cargar temporalmente. No extraigas el XPI. |
| 9 | Open the Firefox extensions menu and select **CaptureFox**. | Abre el menú de extensiones de Firefox y selecciona **CaptureFox**. |

> Both options are temporary. Firefox removes the add-on when it closes. Repeat steps 5–9 to load it again. The unsigned XPI cannot be installed permanently in standard Firefox.
>
> Ambas opciones son temporales. Firefox elimina el complemento al cerrarse. Repite los pasos 5–9 para cargarlo nuevamente. El XPI sin firmar no se puede instalar permanentemente en Firefox normal.

### Reload or remove the temporary add-on

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Stop recording and download important videos before changing or removing the add-on. In <code>about:debugging#/runtime/this-firefox</code>, locate CaptureFox and click <b>Reload</b> after source changes, or <b>Remove</b> to unload it. Do not rely on temporary add-on storage to retain recordings between test sessions.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Detén la grabación y descarga los videos importantes antes de cambiar o retirar el complemento. En <code>about:debugging#/runtime/this-firefox</code>, localiza CaptureFox y pulsa <b>Recargar</b> tras modificar el código, o <b>Eliminar</b> para retirarlo del navegador. No dependas del almacenamiento temporal para conservar grabaciones entre sesiones de pruebas.
    </td>
  </tr>
</table>

### Default settings

| Setting | Default | Valor inicial |
|---|---|---|
| What to record | Screen | Screen |
| Audio | Microphone | Microphone |
| Microphone | First input reported by Firefox | Primera entrada que informa Firefox |
| Camera | First camera reported by Firefox | Primera cámara que informa Firefox |
| System audio input | Empty | Vacío |
| Quality | 1080p | 1080p |
| Frames per second | 30 fps | 30 fps |

> With these values the extension records the screen and the microphone. It needs no helper, no terminal and no external package.
>
> Con estos valores la extensión graba la pantalla y el micrófono. No necesita ayudante, ni terminal, ni paquete externo.

### System audio limitation

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Firefox exposes no interface for internal audio. <code>getDisplayMedia</code> returns video only, and the <code>desktopCapture</code> and <code>tabCapture</code> extension APIs do not exist in Firefox. Chrome recorders capture internal audio because Chrome does provide those interfaces.<br><br>CaptureFox works around this on Linux. The helper <code>tools/audio-bridge.py</code> creates a virtual input named <code>CaptureFox_System_Audio</code>. Firefox reads that input as one more microphone, so the extension never calls the helper and never talks to Python.<br><br>System audio is therefore an optional extra. The other four combinations of mode and audio work without it.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Firefox no expone ninguna interfaz para el audio interno. <code>getDisplayMedia</code> devuelve solo vídeo, y las API de extensión <code>desktopCapture</code> y <code>tabCapture</code> no existen en Firefox. Los grabadores de Chrome capturan audio interno porque Chrome sí ofrece esas interfaces.<br><br>CaptureFox lo resuelve en Linux por otra vía. El ayudante <code>tools/audio-bridge.py</code> crea una entrada virtual llamada <code>CaptureFox_System_Audio</code>. Firefox lee esa entrada como un micrófono más, así que la extensión nunca llama al ayudante ni habla con Python.<br><br>El audio del sistema es por eso un extra opcional. Las otras cuatro combinaciones de modo y audio funcionan sin él.
    </td>
  </tr>
</table>

| Mode | Audio | Helper required | Ayudante necesario |
|---|---|---|---|
| Screen | No audio | No | No |
| Screen | Microphone | No | No |
| Camera | Microphone | No | No |
| Screen and camera | Microphone | No | No |
| Any | System audio | Yes | Sí |
| Any | Microphone and system audio | Yes | Sí |

### Enable system audio

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Follow these steps only to record internal audio. Open a terminal in the extracted repository’s <code>capturefox/</code> folder. Run the following command to enable the Linux virtual input. It requires <code>python3</code> and PipeWire or PulseAudio.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Sigue estos pasos solo para grabar audio interno. Abre una terminal en la carpeta <code>capturefox/</code> del repositorio extraído. Ejecuta el siguiente comando para activar la entrada virtual de Linux. Requiere <code>python3</code> y PipeWire o PulseAudio.
    </td>
  </tr>
</table>

```bash
python3 tools/audio-bridge.py --start
```

### Record microphone and system audio

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      <ol><li>Click <b>Refresh devices</b> and grant microphone permission.</li><li>Select your physical microphone and <b>CaptureFox_System_Audio</b> as the system audio input.</li><li>Choose <b>Microphone and system audio</b>, click <b>Start recording</b>, and select the screen or window to share.</li><li>Click <b>Stop</b> when finished. Open <b>Library</b> to play or download the result.</li></ol>
    </td>
    <td style="width: 50%; vertical-align: top;">
      <ol><li>Pulsa <b>Refresh devices</b> y concede permiso al micrófono.</li><li>Selecciona tu micrófono físico y <b>CaptureFox_System_Audio</b> como entrada interna.</li><li>Elige <b>Microphone and system audio</b>, pulsa <b>Start recording</b> y selecciona la pantalla o ventana.</li><li>Pulsa <b>Stop</b> al terminar. Abre <b>Library</b> para reproducir o descargar el resultado.</li></ol>
    </td>
  </tr>
</table>

### Disable system audio

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Disable the virtual input when finished.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Desactiva la entrada virtual al terminar.
    </td>
  </tr>
</table>

```bash
python3 tools/audio-bridge.py --stop
```

### Check system audio status

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Check the helper state without starting a new input.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Consulta el estado de la herramienta sin iniciar una entrada nueva.
    </td>
  </tr>
</table>

```bash
python3 tools/audio-bridge.py --status --json
```

### Output devices and runtime state

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The virtual input captures audio reaching the current default output, including other applications. If you switch output devices, run <code>start</code> again and refresh the device list before recording.<br><br>Runtime state is stored under <code>$XDG_RUNTIME_DIR/captura-audio</code>, or <code>/run/user/&lt;uid&gt;/captura-audio</code>. There is no automatic startup service.
    </td>
    <td style="width: 50%; vertical-align: top;">
      La entrada virtual captura el sonido que llega a la salida predeterminada, incluyendo otras aplicaciones. Si cambias de salida, ejecuta <code>start</code> otra vez y actualiza los dispositivos antes de grabar.<br><br>El estado se guarda en <code>$XDG_RUNTIME_DIR/captura-audio</code> o <code>/run/user/&lt;uid&gt;/captura-audio</code>. No hay servicio de inicio automático.
    </td>
  </tr>
</table>

## DATA AND LIMITATIONS

---

| Topic | Description | Descripción |
|---|---|---|
| Local storage | Chunks are saved every two seconds in the extension's IndexedDB. Keep the recorder tab open during recording. | Los fragmentos se guardan cada dos segundos en IndexedDB del complemento. Mantén abierta la pestaña durante la grabación. |
| Recovery | Preserves saved chunks but cannot guarantee the final chunk or playback of every partial file. | Conserva los fragmentos guardados, pero no garantiza recuperar el último fragmento ni reproducir todos los archivos parciales. |
| Capacity | No automatic recording count limit or deletion. Capacity depends on browser storage and disk space. | No hay límite automático por cantidad ni eliminación automática. La capacidad depende del almacenamiento del navegador y del disco. |
| Data retention | Uninstalling the extension or clearing its data may erase recordings. Download important files first. | Desinstalar la extensión o borrar sus datos puede eliminar grabaciones. Descarga primero los archivos importantes. |
| Memory | Export and playback assemble the complete recording in memory. | La descarga y reproducción ensamblan la grabación completa en memoria. |
| WebM metadata | Downloads add duration when safe. They do not add Cues or guarantee precise seeking in every player. | La descarga añade duración cuando es seguro. No añade índices Cues ni garantiza búsqueda precisa en todos los reproductores. |
| Camera overlay | Canvas and timers may be affected by background tab throttling. | Las restricciones de pestañas en segundo plano pueden reducir la frecuencia de canvas y temporizadores. |
| Tab audio | Direct Chrome-style tab audio capture is not provided. | No se ofrece captura directa de audio de pestaña equivalente a Chrome. |
| System audio | Firefox provides no interface for internal audio. On Linux it requires the virtual input created by `tools/audio-bridge.py`. | Firefox no ofrece ninguna interfaz para el audio interno. En Linux requiere la entrada virtual que crea `tools/audio-bridge.py`. |

## DEVELOPMENT

---


### Install test dependencies

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The extension runtime has no third-party dependencies. Install the test dependencies outside the project to keep the source folder clean. The <code>tests/</code> folder is for development and is not included in the XPI.
    </td>
    <td style="width: 50%; vertical-align: top;">
      La extensión no tiene dependencias externas de ejecución. Instala las dependencias de pruebas fuera del proyecto para mantener limpia la carpeta del código. La carpeta <code>tests/</code> se utiliza para desarrollo y no se incluye en el XPI.
    </td>
  </tr>
</table>

```bash
npm install --prefix ../capturefox-dev --ignore-scripts --no-bin-links --no-package-lock --no-audit --no-fund fake-indexeddb@6.2.5 jsdom@30.1.2
```

### Run tests

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Run the recording, storage, WebM, interface, and audio helper tests from the project folder.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Ejecuta las pruebas de grabación, almacenamiento, WebM, interfaz y herramienta de audio desde la carpeta del proyecto.
    </td>
  </tr>
</table>

```bash
CAPTUREFOX_TEST_DEPS=../capturefox-dev node --test tests/recorder.test.mjs tests/storage.test.mjs tests/webm.test.mjs
CAPTUREFOX_TEST_DEPS=../capturefox-dev node tests/ui.test.mjs
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_audio_bridge.py
```

### Build the extension

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      Build the XPI from the project folder.
    </td>
    <td style="width: 50%; vertical-align: top;">
      Genera el XPI desde la carpeta del proyecto.
    </td>
  </tr>
</table>

```bash
python3 tools/build.py
```

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      The build produces <code>capturefox-0.1.1.xpi</code>, containing only <code>extension/</code>. Development dependencies are excluded.
    </td>
    <td style="width: 50%; vertical-align: top;">
      La compilación genera <code>capturefox-0.1.1.xpi</code>, que contiene solamente <code>extension/</code>. No incluye dependencias de desarrollo.
    </td>
  </tr>
</table>

## DESIGN AND COMPATIBILITY

---

<table width="100%">
  <tr>
    <td style="width: 50%; vertical-align: top;">
      CaptureFox is a Firefox extension with its own code, interface, and artwork.<br><br>The extension ID, IndexedDB name, recorder lock, and PulseAudio source/state identifiers retain their original technical names for compatibility. Visible application and virtual input labels are in English. Renaming the application does not automatically migrate data between Firefox profiles or separately loaded temporary add-ons.
    </td>
    <td style="width: 50%; vertical-align: top;">
      CaptureFox es una extensión para Firefox con código, interfaz y recursos gráficos propios.<br><br>Los identificadores de extensión, IndexedDB, bloqueo y fuente/estado PulseAudio conservan sus nombres técnicos originales por compatibilidad. La aplicación y la entrada virtual muestran etiquetas en inglés. Cambiar el nombre no migra automáticamente los datos entre perfiles Firefox ni complementos temporales cargados por separado.
    </td>
  </tr>
</table>

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
