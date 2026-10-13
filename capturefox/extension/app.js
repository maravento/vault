import { RecordingStore } from './storage.js';
import { CaptureSession } from './recorder.js';
import { makeSeekable } from './webm.js';
const $ = id => document.getElementById(id);
const store = new RecordingStore();
const session = new CaptureSession({ store, preview: $('preview'), canvas: $('composition') });
const fields = ['audioMode','micSelect','cameraSelect','systemSelect','quality','frameRate',
  'cameraPosition','cameraShape','cameraSize','micGain','systemGain'];
let owner = false, playerURL;
const notice = message => { $('notice').textContent = message; $('notice').hidden = !message; };
const duration = ms => new Date(Math.max(0, ms)).toISOString().slice(11, 19);
const size = bytes => `${(bytes / 1024 / 1024).toFixed(1)} MB`;
function controls() {
  const busy = session.state !== 'idle';
  $('startBtn').disabled = busy || !owner;
  $('pauseBtn').disabled = !['recording','paused'].includes(session.state);
  $('pauseBtn').textContent = session.state === 'paused' ? 'Resume' : 'Pause';
  $('stopBtn').disabled = !['recording','paused'].includes(session.state);
  for (const id of fields.filter(id => !id.endsWith('Gain'))) $(id).disabled = busy;
  document.querySelectorAll('[name=captureMode]').forEach(input => input.disabled = busy);
  $('refreshDevices').disabled = busy || !owner;
  $('status').textContent = ({ idle: 'Ready to record', starting: 'Preparing capture…',
    recording: 'Recording', paused: 'Paused', stopping: 'Saving…' })[session.state];
}
function settings() {
  return { mode: document.querySelector('[name=captureMode]:checked').value,
    audio: $('audioMode').value, micId: $('micSelect').value, cameraId: $('cameraSelect').value,
    systemId: $('systemSelect').value, quality: $('quality').value, fps: Number($('frameRate').value),
    cameraPosition: $('cameraPosition').value, cameraShape: $('cameraShape').value,
    cameraSize: $('cameraSize').value, micGain: Number($('micGain').value),
    systemGain: Number($('systemGain').value) };
}
async function devices(requestPermission = false) {
  if (requestPermission) {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach(track => track.stop());
  }
  const list = await navigator.mediaDevices.enumerateDevices();
  for (const [id, kind] of [['micSelect','audioinput'],['systemSelect','audioinput'],['cameraSelect','videoinput']]) {
    const previous = $(id).value;
    $(id).replaceChildren();
    const candidates = list.filter(device => device.kind === kind);
    for (const [index, device] of candidates.entries()) {
      const option = document.createElement('option');
      option.value = device.deviceId;
      option.textContent = device.label || `${kind === 'videoinput' ? 'Camera' : 'Input'} ${index + 1}`;
      $(id).append(option);
    }
    if (candidates.some(device => device.deviceId === previous)) $(id).value = previous;
    if (id === 'systemSelect') {
      const virtual = candidates.find(device => device.label.includes('CaptureFox_System_Audio'));
      if (virtual) $(id).value = virtual.deviceId;
      else if (!previous) $(id).value = '';
    }
    if (id === 'micSelect' && candidates.find(device => device.deviceId === $(id).value)?.label.includes('CaptureFox_System_Audio')) {
      const mic = candidates.find(device => !device.label.includes('CaptureFox_System_Audio'));
      $(id).value = mic?.deviceId || '';
    }
  }
}
async function library() {
  const rows = await store.list();
  $('library-grid').replaceChildren(); $('empty-state').hidden = rows.length !== 0;
  for (const row of rows) {
    const card = document.createElement('article'); card.className = 'recording-card';
    const title = document.createElement('h3'); title.textContent = row.title;
    const info = document.createElement('p');
    const state = { complete: 'Saved', failed: 'Partial', interrupted: 'Interrupted', recording: 'In progress' }[row.status];
    info.textContent = `${duration(row.durationMs)} · ${size(row.bytes)} · ${state}`;
    card.append(title, info);
    for (const [label, action] of [
      ['Play', async () => {
        closePlayer(); playerURL = URL.createObjectURL(await store.getBlob(row.id));
        $('playback').src = playerURL; $('playback-title').textContent = row.title;
        $('player-dialog').showModal();
      }],
      ['Download', async () => {
        const original = await store.getBlob(row.id);
        const result = await makeSeekable(original, row.durationMs);
        const url = URL.createObjectURL(result.blob);
        const anchor = document.createElement('a'); anchor.href = url;
        anchor.download = `CaptureFox-${new Date(row.createdAt).toISOString().replace(/[:.]/g,'-')}.webm`;
        document.body.append(anchor); anchor.click(); anchor.remove();
        setTimeout(() => URL.revokeObjectURL(url), 300000);
      }],
      ['Delete', async () => {
        if (confirm('Permanently delete this recording?')) {
          await store.remove(row.id); await library();
        }
      }]
    ]) {
      const button = document.createElement('button'); button.textContent = label;
      button.disabled = row.status === 'recording' || (!row.bytes && label !== 'Delete');
      button.addEventListener('click', () => action().catch(error => notice(error.message)));
      card.append(button);
    }
    $('library-grid').append(card);
  }
  const estimate = await store.estimate();
  $('storage-state').textContent = `${size(estimate.usage || 0)} used of ${size(estimate.quota || 0)} available`;
}
function closePlayer() {
  $('playback').pause(); $('playback').removeAttribute('src'); $('playback').load();
  if (playerURL) URL.revokeObjectURL(playerURL); playerURL = null;
}
$('closePlayer').addEventListener('click', () => $('player-dialog').close());
$('player-dialog').addEventListener('close', closePlayer);
$('refreshDevices').addEventListener('click', () => devices(true).catch(error => notice(error.message)));
$('refreshLibrary').addEventListener('click', () => library().catch(error => notice(error.message)));
$('startBtn').addEventListener('click', () => {
  notice('');
  session.start(settings()).then(() => { session.done.catch(() => {}); }).catch(error => notice(error.message));
});
$('pauseBtn').addEventListener('click', () => session.state === 'paused' ? session.resume() : session.pause());
$('stopBtn').addEventListener('click', () => session.stop().catch(error => notice(error.message)));
for (const [id, name] of [['micGain','microphone'],['systemGain','system']])
  $(id).addEventListener('input', () => session.setGain(name, Number($(id).value)));
session.addEventListener('state', controls);
session.addEventListener('error', event => notice(event.detail.message));
session.addEventListener('finished', () => library().catch(error => notice(error.message)));
setInterval(() => { $('timer').textContent = duration(session.elapsed); }, 250);
window.addEventListener('beforeunload', event => {
  if (session.state !== 'idle') { event.preventDefault(); event.returnValue = ''; }
});
document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('[data-panel]').forEach(panel => panel.hidden = panel.dataset.panel !== button.dataset.view);
  document.querySelectorAll('[data-view]').forEach(item => {
    item.classList.toggle('active', item === button);
    item.setAttribute('aria-selected', String(item === button));
  });
}));
async function initialize() {
  await store.open();
  const recovered = await store.recoverInterrupted();
  if (recovered) notice('Interrupted recordings were recovered. Check the library.');
  await devices(); await library(); controls();
}
controls();
if (navigator.locks) {
  navigator.locks.request('captura-recorder-owner', { ifAvailable: true }, async lock => {
    if (!lock) { notice('CaptureFox is already open in another tab. Use that tab.'); return; }
    owner = true;
    await initialize();
    await new Promise(resolve => window.addEventListener('pagehide', resolve, { once: true }));
  }).catch(error => notice(error.message));
} else notice('This browser does not support the locking required to protect recordings.');
