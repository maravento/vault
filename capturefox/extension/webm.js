/* CaptureFox WebM duration metadata writer
   FILE: capturefox/extension/webm.js */
// Duration metadata only. This module does not construct Cues or guarantee seeking.
const SEGMENT = 0x18538067, INFO = 0x1549a966, DURATION = 0x4489;
const SCALE = 0x2ad7b1, SEEK_HEAD = 0x114d9b74, CUES = 0x1c53bb6b;
function vint(bytes, offset, isId = false) {
  const first = bytes[offset];
  if (!first) throw new Error('Invalid EBML header.');
  let length = 1, mask = 128;
  while (!(first & mask)) { length++; mask >>= 1; }
  if (length > (isId ? 4 : 8) || offset + length > bytes.length)
    throw new Error('Incomplete EBML header.');
  let value = BigInt(isId ? first : first & (mask - 1));
  for (let i = 1; i < length; i++) value = (value << 8n) | BigInt(bytes[offset + i]);
  const unknown = !isId && value === (1n << BigInt(length * 7)) - 1n;
  if (!unknown && value > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('EBML size exceeds the supported range.');
  return { length, value: Number(value), unknown };
}
function element(bytes, offset, limit = bytes.length) {
  const id = vint(bytes, offset, true);
  const size = vint(bytes, offset + id.length);
  const start = offset + id.length + size.length;
  const end = size.unknown ? limit : start + size.value;
  if (end > limit) throw new Error('Truncated EBML element.');
  return { id: id.value, offset, start, end, size, sizeOffset: offset + id.length };
}
function encodedSize(value, length) {
  let n = BigInt(value);
  if (n < 0n || n >= (1n << BigInt(7 * length)) - 1n)
    throw new Error('The EBML size does not fit the existing header.');
  const out = new Uint8Array(length);
  for (let i = length - 1; i >= 0; i--) { out[i] = Number(n & 255n); n >>= 8n; }
  out[0] |= 1 << (8 - length);
  return out;
}
export async function makeSeekable(blob, durationMs) {
  const unchanged = reason => ({ blob, optimized: false, reason });
  if (!(blob instanceof Blob) || !Number.isFinite(durationMs) || durationMs < 0)
    return unchanged('Invalid duration or file.');
  try {
    // Parse headers individually; keep media payloads in their original Blob slices.
    async function header(offset, limit) {
      const bytes = new Uint8Array(await blob.slice(offset, Math.min(offset + 12, limit)).arrayBuffer());
      const id = vint(bytes, 0, true), size = vint(bytes, id.length);
      const start = offset + id.length + size.length;
      const end = size.unknown ? limit : start + size.value;
      if (end > limit || end <= offset) throw new Error('Truncated EBML element.');
      return { id: id.value, offset, start, end, size, sizeOffset: offset + id.length };
    }
    let segment;
    for (let offset = 0; offset < blob.size;) {
      const entry = await header(offset, blob.size);
      if (entry.id === SEGMENT) { segment = entry; break; }
      if (entry.size.unknown) throw new Error('Unknown top-level element.');
      offset = entry.end;
    }
    if (!segment) return unchanged('WebM segment not found.');
    let info, indexed = false, unknownChild = false;
    for (let offset = segment.start; offset < segment.end;) {
      const entry = await header(offset, segment.end);
      if (entry.id === INFO) info = entry;
      if (entry.id === SEEK_HEAD || entry.id === CUES) indexed = true;
      if (entry.size.unknown) { unknownChild = true; break; }
      offset = entry.end;
    }
    if (!info || info.size.unknown || info.end - info.start > 1024 * 1024)
      return unchanged('Info is missing, unknown, or too large.');
    const bytes = new Uint8Array(await blob.slice(info.start, info.end).arrayBuffer());
    let scale = 1000000, duration;
    for (let offset = 0; offset < bytes.length;) {
      const entry = element(bytes, offset);
      if (entry.size.unknown) throw new Error('Info contains unknown sizes.');
      if (entry.id === SCALE) {
        if (entry.end - entry.start > 8) throw new Error('Invalid timestamp scale.');
        let n = 0n;
        for (const byte of bytes.slice(entry.start, entry.end)) n = (n << 8n) | BigInt(byte);
        scale = Number(n);
        if (!Number.isSafeInteger(scale) || scale <= 0) throw new Error('Invalid timestamp scale.');
      }
      if (entry.id === DURATION) {
        if (duration) throw new Error('Duplicate Duration element.');
        duration = entry;
      }
      offset = entry.end;
    }
    const value = durationMs * 1000000 / scale;
    if (!Number.isFinite(value)) throw new Error('Duration is out of range.');
    if (duration) {
      const length = duration.end - duration.start;
      const payload = new Uint8Array(length), view = new DataView(payload.buffer);
      if (length === 8) view.setFloat64(0, value);
      else if (length === 4 && value <= 3.402823466e38) view.setFloat32(0, value);
      else return unchanged('Unsupported Duration format.');
      return { blob: new Blob([blob.slice(0, info.start + duration.start), payload,
        blob.slice(info.start + duration.end)], { type: blob.type }),
        optimized: true, reason: 'Duration updated; seek indexes were not added.' };
    }
    // Insertion shifts offsets. Preserve indexed files and unknown-length child layouts.
    if (indexed || unknownChild)
      return unchanged('Original preserved: inserting Duration would change offsets or an unknown structure.');
    const addition = new Uint8Array(11);
    addition.set([0x44, 0x89, 0x88]); new DataView(addition.buffer).setFloat64(3, value);
    const patches = [
      { start: info.sizeOffset, end: info.start,
        bytes: encodedSize(info.end - info.start + addition.length, info.size.length) },
      { start: info.end, end: info.end, bytes: addition }
    ];
    if (!segment.size.unknown) patches.push({ start: segment.sizeOffset, end: segment.start,
      bytes: encodedSize(segment.end - segment.start + addition.length, segment.size.length) });
    patches.sort((a, b) => a.start - b.start);
    const parts = []; let offset = 0;
    for (const patch of patches) {
      parts.push(blob.slice(offset, patch.start), patch.bytes); offset = patch.end;
    }
    parts.push(blob.slice(offset));
    return { blob: new Blob(parts, { type: blob.type }), optimized: true,
      reason: 'Duration added; seek indexes were not added.' };
  } catch (error) { return unchanged(`Original preserved: ${error.message}`); }
}
