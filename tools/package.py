#!/usr/bin/env python3
"""Build a deterministic, source-only MoonLoader distribution. No saved pet data."""
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist'
REQUIRED = ['moonloader/petarz.lua', 'moonloader/lib/petarz/engine.lua',
            'moonloader/lib/petarz/catalog.lua', 'moonloader/lib/petarz/games.lua',
            'moonloader/lib/petarz/store.lua', 'moonloader/lib/petarz/ui.lua',
            'moonloader/resource/petarz/pet_atlas.png',
            'moonloader/resource/petarz/pet_scarf.png',
            'moonloader/resource/petarz/pet_raincoat.png',
            'moonloader/resource/petarz/NotoSans-Regular.ttf',
            'moonloader/resource/petarz/FONT-LICENSE.txt', 'README.md', 'LICENSE']
for name in REQUIRED:
    if not (ROOT / name).is_file():
        raise SystemExit('Missing distribution file: ' + name)
files = sorted(p for p in (ROOT / 'moonloader').rglob('*') if p.is_file())
# Never distribute user data, temporary files, or DLLs from the development client.
files = [p for p in files if p.suffix in {'.lua', '.png', '.ttf', '.txt'} and 'config' not in p.relative_to(ROOT).parts]
files += [ROOT / 'README.md', ROOT / 'CHANGELOG.md', ROOT / 'LICENSE', ROOT / 'docs' / 'DESIGN.md']
OUT.mkdir(exist_ok=True)
archive = OUT / 'Petarz-1.0.0.zip'
manifest = {}
with ZipFile(archive, 'w', ZIP_DEFLATED, compresslevel=9) as z:
    for p in sorted(files):
        rel = p.relative_to(ROOT).as_posix()
        data = p.read_bytes()
        manifest[rel] = hashlib.sha256(data).hexdigest()
        entry = ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))
        entry.compress_type = ZIP_DEFLATED
        entry.external_attr = 0o100644 << 16
        z.writestr(entry, data)
    entry = ZipInfo('MANIFEST.sha256.json', date_time=(2026, 1, 1, 0, 0, 0))
    entry.compress_type = ZIP_DEFLATED
    z.writestr(entry, json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
(OUT / 'SHA256SUMS.txt').write_text(sha + '  ' + archive.name + '\n', encoding='utf-8')
print(f'{archive.name}: {archive.stat().st_size:,} bytes; {len(files)} files')
print('SHA256: ' + sha)
