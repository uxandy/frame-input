#!/usr/bin/env python3
"""Build a source-only zip from an explicit allowlist; never include local settings."""
# SPDX-License-Identifier: MIT
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent
FILES = (
    '.gitignore', 'VERSION', 'LICENSE', 'README.md', 'ACCEPTANCE.md', 'package.py',
    '.gitattributes', 'CHANGELOG.md', 'CONTRIBUTING.md', 'SECURITY.md',
    'docs/setup.md', 'docs/troubleshooting.md', 'docs/maintenance.md',
    'assets/frame-input.png', 'assets/frame-input.svg',
    '.github/workflows/checks.yml', '.github/ISSUE_TEMPLATE/bug_report.yml',
    'frame/install.py', 'frame/control.sh', 'frame/install-shortcuts.sh',
    'windows/FrameInput.ps1', 'windows/VirtualHere.ps1',
    'windows/Set up Frame Input.cmd', 'windows/Use Frame Keyboard & Mouse.cmd',
    'windows/Return to Frame.cmd', 'tests/test_frame.py', 'tests/test_windows.ps1',
)


def build():
    version = (ROOT / 'VERSION').read_text().strip()
    prefix = f'frame-input-{version}'
    destination = ROOT / 'dist' / f'{prefix}.zip'
    destination.parent.mkdir(exist_ok=True)
    manifest = {}
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in FILES:
            source = ROOT / name
            if source.is_symlink():
                raise ValueError(f'Refusing to package a symlink: {name}')
            data = source.read_bytes()
            if name.endswith('.cmd'):
                data = data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            manifest[name] = hashlib.sha256(data).hexdigest()
            archive.writestr(f'{prefix}/{name}', data)
        archive.writestr(f'{prefix}/MANIFEST.json', json.dumps({'version': version, 'sha256': manifest}, indent=2))
    print(destination)
    print('SHA256 ' + hashlib.sha256(destination.read_bytes()).hexdigest())
    return destination


if __name__ == '__main__':
    build()
