"""Package only original extension files; never include reference artifacts."""
import hashlib
import json
import zipfile
from pathlib import Path
root = Path(__file__).resolve().parent.parent
source = root / 'extension'
manifest = json.loads((source / 'manifest.json').read_text())
target = root / f"capturefox-{manifest['version']}.xpi"
files = sorted(path for path in source.rglob('*') if path.is_file())
if any(path.is_symlink() for path in source.rglob('*')):
    raise SystemExit('Symlinks are not allowed in the extension package.')
with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        entry = zipfile.ZipInfo(path.relative_to(source).as_posix(),
                                date_time=(1980, 1, 1, 0, 0, 0))
        entry.create_system = 3
        entry.external_attr = 0o100644 << 16
        entry.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(entry, path.read_bytes())
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert 'manifest.json' in archive.namelist()
print(json.dumps({'path': str(target), 'files': len(files), 'bytes': target.stat().st_size,
                  'sha256': hashlib.sha256(target.read_bytes()).hexdigest()}))
