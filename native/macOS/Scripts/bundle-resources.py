#!/usr/bin/env python3
"""Bundle an explicit public-source whitelist. Never copy local data or builds recursively."""
import plistlib
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[3]
app = Path(sys.argv[1])
web = app / 'Contents/Resources/Web'
if web.exists():
    shutil.rmtree(web)
web.mkdir(parents=True)
files = [root / name for name in ('index.html', 'Editor.html', 'LICENSE')]
files.extend(p for p in (root / 'dist').iterdir() if p.is_file() and p.suffix in ('.js', '.css'))
for folder in ('src/setup', 'dependencies', 'images'):
    files.extend(p for p in (root / folder).rglob('*') if p.is_file() and not any(part.startswith('.') for part in p.relative_to(root).parts))
for source in files:
    target = web / source.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
info = dict(CFBundleName='PlateLab', CFBundleDisplayName='PlateLab', CFBundleIdentifier='no.zertez.PlateLab',
            CFBundleVersion='23', CFBundleShortVersionString='0.1.22', CFBundleExecutable='PlateLab',
            CFBundlePackageType='APPL', LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
            NSPrincipalClass='NSApplication', LSApplicationCategoryType='public.app-category.productivity')
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
