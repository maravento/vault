/* CaptureFox WebM tests
   FILE: capturefox/tests/webm.test.mjs */
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../extension/webm.js', import.meta.url), 'utf8');
const { makeSeekable } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const file = data => new Blob([Uint8Array.from(data)], { type: 'video/webm' });
const prefix = [0x1a, 0x45, 0xdf, 0xa3, 0x80, 0x18, 0x53, 0x80, 0x67];
const info = [0x15, 0x49, 0xa9, 0x66, 0x80];
const original = file([...prefix, 0xff, ...info]);
const inserted = await makeSeekable(original, 1000);
assert.equal(inserted.optimized, true);
assert.equal(inserted.blob.size, original.size + 11);
const bytes = new Uint8Array(await inserted.blob.arrayBuffer());
assert.equal(bytes[14], 0x8b);
assert.equal(new DataView(bytes.buffer).getFloat64(18), 1000);
const updated = await makeSeekable(inserted.blob, 2000);
assert.equal(updated.optimized, true);
assert.equal(updated.blob.size, inserted.blob.size);
assert.equal(new DataView(await updated.blob.arrayBuffer()).getFloat64(18), 2000);
const known = await makeSeekable(file([...prefix, 0x85, ...info]), 500);
assert.equal(known.optimized, true);
assert.equal(new Uint8Array(await known.blob.arrayBuffer())[9], 0x90);
const indexed = file([...prefix, 0xff, ...info, 0x11, 0x4d, 0x9b, 0x74, 0x80]);
assert.equal((await makeSeekable(indexed, 1000)).blob, indexed);
const unknownCluster = file([...prefix, 0xff, ...info, 0x1f, 0x43, 0xb6, 0x75, 0xff]);
assert.equal((await makeSeekable(unknownCluster, 1000)).blob, unknownCluster);
for (const malformed of [file([]), file([0]), file([...prefix, 0x85])]) {
  const result = await makeSeekable(malformed, 1000);
  assert.equal(result.optimized, false); assert.equal(result.blob, malformed);
}
assert.equal((await makeSeekable(original, NaN)).blob, original);
console.log('WebM: insert/update, known/unknown segment, indexes, unknown cluster, malformed and invalid duration passed.');
