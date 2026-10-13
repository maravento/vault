import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { testDependency } from './dependencies.mjs';
const { indexedDB, IDBKeyRange } = await testDependency('fake-indexeddb');
globalThis.indexedDB = indexedDB; globalThis.IDBKeyRange = IDBKeyRange;
const source = await readFile(new URL('../extension/storage.js', import.meta.url), 'utf8');
const { RecordingStore } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
test('chunks survive reopening and download in exact order', async () => {
  const store = new RecordingStore('persistence'); const id = await store.create();
  await store.append(id, 0, new Blob(['one'])); await store.append(id, 1, new Blob(['two']));
  await store.finish(id, { status:'complete', durationMs:1200 });
  store.db.close(); const reopened = new RecordingStore('persistence');
  assert.equal(await (await reopened.getBlob(id)).text(), 'onetwo');
  const row = await reopened.get(id); assert.equal(row.bytes, 6); assert.equal(row.durationMs, 1200);
});
test('sequence errors roll back metadata and chunk writes', async () => {
  const store = new RecordingStore('atomic'); const id = await store.create();
  await assert.rejects(store.append(id, 1, new Blob(['wrong'])), /sequence/);
  const row = await store.get(id); assert.equal(row.chunks, 0); assert.equal(row.bytes, 0);
  await store.append(id, 0, new Blob(['valid']));
  assert.equal(await (await store.getBlob(id)).text(), 'valid');
});
test('interrupted recovery preserves saved chunks and completed recordings', async () => {
  const store = new RecordingStore('recovery'); const partial = await store.create();
  await store.append(partial, 0, new Blob(['partial'])); const complete = await store.create();
  await store.finish(complete, { status:'complete' });
  assert.equal(await store.recoverInterrupted(), 1);
  assert.equal((await store.get(partial)).status, 'interrupted');
  assert.equal((await store.get(complete)).status, 'complete');
  assert.equal(await (await store.getBlob(partial)).text(), 'partial');
});
test('deleting one recording preserves the others', async () => {
  const store = new RecordingStore('delete'); const first = await store.create(); const second = await store.create();
  await store.append(first, 0, new Blob(['first'])); await store.append(second, 0, new Blob(['second']));
  await store.remove(first); assert.equal(await store.get(first), undefined);
  assert.equal(await (await store.getBlob(second)).text(), 'second'); assert.equal((await store.list()).length, 1);
});
test('finished recordings reject additional chunks', async () => {
  const store = new RecordingStore('closed'); const id = await store.create();
  await store.finish(id, { status:'complete' });
  await assert.rejects(store.append(id, 0, new Blob(['extra'])), /closed/);
});
