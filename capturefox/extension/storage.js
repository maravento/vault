const request = req => new Promise((resolve, reject) => {
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});
const completed = tx => new Promise((resolve, reject) => {
  tx.oncomplete = () => resolve();
  tx.onabort = () => reject(tx.error || new Error('The transaction was canceled.'));
  tx.onerror = () => {}; // onabort preserves transaction atomicity and reports failure.
});
function identifier() {
  if (crypto.randomUUID) return crypto.randomUUID();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, n => n.toString(16).padStart(2, '0')).join('');
}
export class RecordingStore {
  constructor(name = 'screio-firefox-recordings') { this.name = name; this.db = null; }
  async open() {
    if (this.db) return this;
    const req = indexedDB.open(this.name, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      db.createObjectStore('recordings', { keyPath: 'id' });
      db.createObjectStore('chunks', { keyPath: ['id', 'sequence'] })
        .createIndex('recordingId', 'id', { unique: false });
    };
    this.db = await request(req);
    this.db.onversionchange = () => { this.db.close(); this.db = null; };
    return this;
  }
  async create(metadata = {}) {
    await this.open();
    const record = { ...metadata, id: identifier(), title: metadata.title || 'Recording',
      createdAt: Date.now(), endedAt: null, status: 'recording',
      mimeType: metadata.mimeType || 'video/webm', durationMs: 0, bytes: 0, chunks: 0,
      mode: metadata.mode || 'screen', audio: metadata.audio ?? {} };
    const tx = this.db.transaction('recordings', 'readwrite');
    const done = completed(tx);
    tx.objectStore('recordings').add(record);
    await done;
    return record.id;
  }
  async append(id, sequence, blob) {
    if (!Number.isSafeInteger(sequence) || sequence < 0 || !(blob instanceof Blob))
      throw new Error('Invalid recording chunk.');
    await this.open();
    const tx = this.db.transaction(['recordings', 'chunks'], 'readwrite');
    const done = completed(tx);
    const records = tx.objectStore('recordings');
    const req = records.get(id);
    let failure;
    req.onsuccess = () => {
      const row = req.result;
      if (!row || row.status !== 'recording' || row.chunks !== sequence) {
        failure = new Error('Recording missing, closed, or chunk sequence invalid.');
        tx.abort(); return;
      }
      tx.objectStore('chunks').add({ id, sequence, blob });
      row.bytes += blob.size; row.chunks++;
      records.put(row);
    };
    try { await done; } catch (error) { throw failure || error; }
  }
  async finish(id, patch = {}) {
    if (!['complete', 'failed', 'interrupted'].includes(patch.status))
      throw new Error('Invalid final status.');
    await this.open();
    const tx = this.db.transaction('recordings', 'readwrite');
    const done = completed(tx);
    const records = tx.objectStore('recordings');
    let failure;
    const req = records.get(id);
    req.onsuccess = () => {
      if (!req.result) { failure = new Error('Recording not found.'); tx.abort(); return; }
      const { status, durationMs, endedAt } = patch;
      records.put({ ...req.result, status,
        durationMs: Number.isFinite(durationMs) && durationMs >= 0 ? durationMs : req.result.durationMs,
        endedAt: endedAt ?? Date.now() });
    };
    try { await done; } catch (error) { throw failure || error; }
  }
  async list() {
    await this.open();
    const tx = this.db.transaction('recordings'); const done = completed(tx);
    const rows = await request(tx.objectStore('recordings').getAll()); await done;
    return rows.sort((a, b) => b.createdAt - a.createdAt || a.id.localeCompare(b.id));
  }
  async get(id) {
    await this.open();
    const tx = this.db.transaction('recordings'); const done = completed(tx);
    const row = await request(tx.objectStore('recordings').get(id)); await done;
    return row;
  }
  async getBlob(id) {
    await this.open();
    const tx = this.db.transaction(['recordings', 'chunks']); const done = completed(tx);
    const [row, chunks] = await Promise.all([
      request(tx.objectStore('recordings').get(id)),
      request(tx.objectStore('chunks').index('recordingId').getAll(IDBKeyRange.only(id)))
    ]);
    await done;
    if (!row) throw new Error('Recording not found.');
    chunks.sort((a, b) => a.sequence - b.sequence);
    if (chunks.length !== row.chunks || chunks.some((chunk, i) => chunk.sequence !== i) ||
      chunks.reduce((n, chunk) => n + chunk.blob.size, 0) !== row.bytes)
      throw new Error('The recording chunks are incomplete.');
    return new Blob(chunks.map(chunk => chunk.blob), { type: row.mimeType });
  }
  async remove(id) {
    await this.open();
    const tx = this.db.transaction(['recordings', 'chunks'], 'readwrite'); const done = completed(tx);
    tx.objectStore('recordings').delete(id);
    const req = tx.objectStore('chunks').index('recordingId').openCursor(IDBKeyRange.only(id));
    req.onsuccess = () => { const cursor = req.result; if (cursor) { cursor.delete(); cursor.continue(); } };
    await done;
  }
  async recoverInterrupted() {
    await this.open();
    const tx = this.db.transaction('recordings', 'readwrite'); const done = completed(tx);
    const req = tx.objectStore('recordings').openCursor(); let count = 0;
    req.onsuccess = () => {
      const cursor = req.result;
      if (!cursor) return;
      if (cursor.value.status === 'recording') {
        cursor.update({ ...cursor.value, status: 'interrupted', endedAt: Date.now() }); count++;
      }
      cursor.continue();
    };
    await done; return count;
  }
  async estimate() { return navigator.storage.estimate(); }
}
