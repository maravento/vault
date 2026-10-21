/* CaptureFox recorder tests
   FILE: capturefox/tests/recorder.test.mjs */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
const source = await readFile(new URL('../extension/recorder.js', import.meta.url), 'utf8');
const { CaptureSession } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
class Track extends EventTarget { readyState = 'live'; stop() { this.readyState = 'ended'; } }
class Stream { constructor(tracks) { this.tracks = tracks; } getTracks() { return this.tracks; } getVideoTracks() { return this.tracks.filter(t => t.kind === 'video'); } getAudioTracks() { return this.tracks.filter(t => t.kind === 'audio'); } }
class Recorder extends EventTarget {
  static isTypeSupported() { return true; }
  state = 'inactive'; mimeType = 'video/webm';
  start() { this.state = 'recording'; }
  pause() { this.state = 'paused'; } resume() { this.state = 'recording'; }
  chunk(value) { const event = new Event('dataavailable'); event.data = new Blob([value]); this.dispatchEvent(event); }
  stop() { this.state = 'inactive'; this.chunk('last'); queueMicrotask(() => this.dispatchEvent(new Event('stop'))); }
}
function fixture({ denied = false, fail = false } = {}) {
  let now = 0, row, chunks = [];
  const video = Object.assign(new Track(), { kind: 'video' });
  const stream = new Stream([video]);
  const store = {
    async create(metadata) { row = { ...metadata, id: 'recording' }; return row.id; },
    async append(id, sequence, blob) { if (fail) throw new Error('quota'); await new Promise(resolve => setTimeout(resolve, 2)); assert.equal(sequence, chunks.length); chunks.push(await blob.text()); },
    async finish(id, patch) { Object.assign(row, patch); }, async get() { return row; }
  };
  const preview = { srcObject: null, play: async () => {} };
  const session = new CaptureSession({ store, preview, canvas: {}, Recorder,
    mediaDevices: { getDisplayMedia: async () => { if (denied) throw new Error('denied'); return stream; } },
    makeStream: tracks => new Stream(tracks), clock: () => now });
  return { session, video, preview, chunks, tick: value => { now = value; } };
}
const options = { mode: 'screen', audio: 'none', quality: 'native', fps: 30 };
test('serializes chunks, excludes pauses and releases tracks', async () => {
  const f = fixture(); await f.session.start(options);
  f.session.recorder.chunk('first'); f.session.recorder.chunk('second');
  f.tick(1200); f.session.pause(); f.tick(5000); assert.equal(f.session.elapsed, 1200);
  f.session.resume(); f.tick(5700); const row = await f.session.stop();
  assert.equal(row.durationMs, 1900); assert.equal(row.status, 'complete');
  assert.deepEqual(f.chunks, ['first','second','last']);
  assert.equal(f.video.readyState, 'ended'); assert.equal(f.preview.srcObject, null);
  assert.equal(f.session.state, 'idle');
});
test('permission denial returns to idle without creating data', async () => {
  const f = fixture({ denied: true }); await assert.rejects(f.session.start(options), /denied/);
  assert.equal(f.session.state, 'idle'); assert.deepEqual(f.chunks, []);
});
test('storage failure stops recording and marks partial data', async () => {
  const f = fixture({ fail: true }); await f.session.start(options);
  f.session.recorder.chunk('first'); const row = await f.session.done;
  assert.equal(row.status, 'failed'); assert.equal(f.video.readyState, 'ended');
});
test('screen sharing ended finalizes the recording', async () => {
  const f = fixture(); await f.session.start(options); f.tick(1000);
  f.video.dispatchEvent(new Event('ended')); const row = await f.session.done;
  assert.equal(row.status, 'complete'); assert.equal(row.durationMs, 1000);
});
test('requires distinct microphone and internal audio devices', async () => {
  const f = fixture(); await assert.rejects(f.session.start({ ...options, audio:'both', systemId:'same', micId:'same' }), /different/);
  assert.equal(f.session.state, 'idle');
});
