#!/usr/bin/env python3
"""Build a portable app ZIP from an explicit list; never include local lab layouts."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root=Path(__file__).resolve().parent.parent
if not (root/'dist/editor.min.js').exists():
    raise SystemExit('Run node scripts/build.mjs first.')
files=[root/name for name in ('index.html','Editor.html','LICENSE','SETUP.md','Start Plate Setup.command','scripts/launch.py','scripts/serve.py')]
files.extend(p for p in (root/'dist').iterdir() if p.is_file() and p.suffix in ('.js','.css'))
for folder in ('dependencies','images','src/setup'):
    files.extend(p for p in (root/folder).rglob('*') if p.is_file() and p.suffix.lower() not in ('.zip','.ini') and not p.name.startswith('.'))
archive=root/'dist/PlateSetup.zip'
with ZipFile(archive,'w',ZIP_DEFLATED) as z:
    for p in sorted(files): z.write(p,Path('PlateSetup')/p.relative_to(root))
print(archive)
