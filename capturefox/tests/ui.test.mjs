import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { testDependency } from './dependencies.mjs';
const { JSDOM } = await testDependency('jsdom');
const { indexedDB, IDBKeyRange } = await testDependency('fake-indexeddb');
const root = new URL('../extension/', import.meta.url);
const dom = new JSDOM(await readFile(new URL('index.html', root), 'utf8'), { url:'https://capturefox.invalid/' });
Object.assign(globalThis, { document:dom.window.document, window:dom.window, indexedDB, IDBKeyRange });
Object.defineProperty(globalThis, 'navigator', { value: {
  mediaDevices: { enumerateDevices:async () => [
    { kind:'audioinput', deviceId:'mic', label:'Microphone' },
    { kind:'audioinput', deviceId:'system', label:'CaptureFox_System_Audio' }
  ] },
  storage: { estimate:async () => ({ usage:0, quota:1e9 }) },
  locks: { request:async (name, options, callback) => callback({ name }) }
}, configurable:true });
const intervals = []; const originalInterval = globalThis.setInterval;
globalThis.setInterval = (...args) => { const id = originalInterval(...args); intervals.push(id); return id; };
globalThis.MediaRecorder = class { static isTypeSupported() { return true; } };
let app = await readFile(new URL('app.js',root), 'utf8');
for (const name of ['storage','recorder','webm']) {
  const source = await readFile(new URL(`${name}.js`,root),'utf8');
  app = app.replace(`'./${name}.js'`, `'data:text/javascript;base64,${Buffer.from(source).toString('base64')}'`);
}
try {
  await import('data:text/javascript;base64,'+Buffer.from(app).toString('base64'));
  await new Promise(resolve => setTimeout(resolve,50));
  const get = id => document.getElementById(id);
  assert.equal(get('notice').hidden,true,get('notice').textContent);
  assert.equal(get('startBtn').disabled,false); assert.equal(get('stopBtn').disabled,true);
  assert.equal(get('systemSelect').value,'system'); assert.equal(get('micSelect').value,'mic');
  assert.match(get('storage-state').textContent,/0.0 MB/);
  document.querySelector('[data-view=library]').click();
  assert.equal(document.querySelector('[data-panel=library]').hidden,false);
  assert.equal(document.querySelector('[data-panel=recorder]').hidden,true);
  assert.equal(get('empty-state').hidden,false);
  console.log('UI startup, local storage, audio device selection and navigation passed.');
} finally {
  intervals.forEach(clearInterval); window.dispatchEvent(new dom.window.Event('pagehide')); dom.window.close();
}
