#!/usr/bin/env python3
"""Install an on-demand, receiver-scoped service. Does not download or start it."""
# SPDX-License-Identifier: MIT
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile

BASE = Path('/var/lib/frame-input')
UNIT = Path('/etc/systemd/system/frame-input.service')
# This fragment must sort after the SteamOS wheel rule, which otherwise restores
# password authentication for all commands. Keep the old path for removal.
SUDOERS = Path('/etc/sudoers.d/zz-frame-input')
LEGACY_SUDOERS = Path('/etc/sudoers.d/frame-input')
SOURCE = Path(__file__).resolve().parent


def usb_pair(value):
    if not re.fullmatch(r'[0-9a-fA-F]{1,4}[:/][0-9a-fA-F]{1,4}', value):
        raise ValueError('Use one vendor:product USB ID, such as 1234:5678. No wildcards.')
    vendor, product = (int(part, 16) for part in re.split('[:/]', value))
    if vendor == 0:
        raise ValueError('A zero USB vendor is not a valid receiver selection.')
    return f'{vendor:x}/{product:x}'


def render(user, usb_id, minutes):
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*', user) or user == 'root':
        raise ValueError('Select a regular Linux account with a simple login name.')
    if not 0 <= minutes <= 480:
        raise ValueError('Use 0 for no session deadline, or between 1 and 480 minutes.')
    pair = usb_pair(usb_id)
    runtime = 'infinity' if minutes == 0 else str(minutes * 60)
    unit = f'''[Unit]
Description=Frame Input on-demand USB sharing
After=network.target

[Service]
Type=exec
ExecStart=/var/lib/frame-input/vhusbdarm64 -c /var/lib/frame-input/state/config.ini
WorkingDirectory=/var/lib/frame-input/state
RuntimeMaxSec={runtime}
TimeoutStopSec=5s
KillMode=control-group
Restart=no
UMask=0077
NoNewPrivileges=true
ProtectHome=true
PrivateTmp=true
'''
    # Exact commands only: no shell, arguments supplied by the user, or wildcards.
    policy = f'{user} ALL=(root) NOPASSWD: /usr/bin/systemctl start frame-input.service, /usr/bin/systemctl stop frame-input.service\n'
    config = f'ServerName=Frame-Input\nAllowedDevices={pair}\nAutoAttachToKernel=1\nUseAVAHI=0\n'
    return unit, policy, config


def desktop(action):
    label = 'Start Sharing' if action == 'start' else 'Stop Sharing'
    return f'''[Desktop Entry]
Type=Application
Name=Frame Input - {label}
Comment=Share or return your keyboard and mouse
Exec=/var/lib/frame-input/{action}-sharing
Icon=input-keyboard
Terminal=false
Categories=Utility;
'''


def check_elf(path):
    with open(path, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('Server must be a regular file.')
        header = stream.read(20)
    if len(header) != 20 or header[:6] != b'\x7fELF\x02\x01' or int.from_bytes(header[18:20], 'little') != 183:
        raise ValueError('Expected the official Linux ARM64 server executable. ELF checks do not authenticate its publisher.')


def write_new(path, text, mode):
    # Exclusive creation also rejects destination symlinks.
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
        os.chmod(path, mode)
    except Exception:
        Path(path).unlink()
        raise


def run(*args):
    subprocess.run(args, check=True)


def require_platform():
    if platform.system() != 'Linux' or platform.machine() != 'aarch64' or os.geteuid() != 0:
        raise ValueError('Installation/removal must run with sudo on the ARM64 Frame.')
    for tool in ('systemctl', 'sudo', 'visudo', 'systemd-analyze'):
        if not os.access('/usr/bin/' + tool, os.X_OK):
            raise ValueError(f'Missing /usr/bin/{tool}. Stop and inspect; no packages were installed.')


def install(args):
    require_platform()
    account = pwd.getpwnam(args.user)
    if account.pw_uid == 0:
        raise ValueError('Select the normal Frame account.')
    unit, policy, config = render(args.user, args.usb_id, args.minutes)
    check_elf(args.server)
    for path in (BASE, UNIT, SUDOERS, LEGACY_SUDOERS):
        if os.path.lexists(path):
            raise ValueError(f'{path} already exists. Nothing overwritten; inspect or uninstall the previous package first.')
    # No readonly-mode changes. Permission/readonly failures are reported directly.
    written = []
    try:
        with tempfile.TemporaryDirectory(prefix='.frame-input-', dir='/var/lib') as temporary:
            stage = Path(temporary)
            os.chmod(stage, 0o755)
            (stage / 'state').mkdir(mode=0o700)
            shutil.copyfile(args.server, stage / 'vhusbdarm64')
            os.chmod(stage / 'vhusbdarm64', 0o755)
            check_elf(stage / 'vhusbdarm64')
            write_new(stage / 'state/config.ini', config, 0o600)
            for script in ('control.sh', 'install-shortcuts.sh'):
                write_new(stage / script, (SOURCE / script).read_text(), 0o755)
            for action in ('start', 'stop'):
                write_new(stage / f'{action}-sharing', f'#!/bin/sh\nexec /var/lib/frame-input/control.sh {action}\n', 0o755)
                write_new(stage / f'frame-input-{action}.desktop', desktop(action), 0o644)
            write_new(stage / 'sudoers.check', policy, 0o440)
            run('/usr/bin/visudo', '-cf', str(stage / 'sudoers.check'))
            (stage / 'sudoers.check').unlink()
            manifest = {'format': 'frame-input-v1', 'user': args.user,
                        'unit_sha256': hashlib.sha256(unit.encode()).hexdigest(),
                        'sudoers_sha256': hashlib.sha256(policy.encode()).hexdigest()}
            write_new(stage / 'manifest.json', json.dumps(manifest), 0o600)
            stage.rename(BASE)
            written.append(BASE)
        write_new(UNIT, unit, 0o644)
        written.append(UNIT)
        run('/usr/bin/systemd-analyze', 'verify', str(UNIT))
        write_new(SUDOERS, policy, 0o440)
        written.append(SUDOERS)
        run('/usr/bin/systemctl', 'daemon-reload')
        # Exercise the real user's rule without relying on a cached password.
        # The fresh service has never been started; this does not claim USB.
        run('/usr/bin/sudo', '-u', args.user, '--', '/usr/bin/sudo', '-n', '-k',
            '/usr/bin/systemctl', 'stop', 'frame-input.service')
    except Exception:
        for path in reversed(written):
            if path == BASE:
                shutil.rmtree(path)
            else:
                path.unlink()
        subprocess.run(['/usr/bin/systemctl', 'daemon-reload'], check=False)
        raise
    duration = 'no session deadline; use Stop Sharing to end the session' if args.minutes == 0 else f'a {args.minutes}-minute session limit'
    print(f'Installed and stopped, with {duration}. No boot autostart.')
    print('As your normal user, run: /var/lib/frame-input/install-shortcuts.sh')


def uninstall():
    require_platform()
    if BASE.is_symlink() or not BASE.is_dir() or BASE.stat().st_uid != 0:
        raise ValueError('Expected a root-owned Frame Input installation.')
    manifest = json.loads((BASE / 'manifest.json').read_text())
    if manifest.get('format') != 'frame-input-v1':
        raise ValueError('Unknown installation; nothing removed.')
    if UNIT.is_symlink() or hashlib.sha256(UNIT.read_bytes()).hexdigest() != manifest['unit_sha256']:
        raise ValueError(f'{UNIT} was changed. Inspect it before removal; nothing removed.')
    policies = [path for path in (SUDOERS, LEGACY_SUDOERS) if os.path.lexists(path)]
    if len(policies) != 1:
        raise ValueError('Expected exactly one Frame Input permission file. Inspect before removal; nothing removed.')
    policy = policies[0]
    if policy.is_symlink() or hashlib.sha256(policy.read_bytes()).hexdigest() != manifest['sudoers_sha256']:
        raise ValueError(f'{policy} was changed. Inspect it before removal; nothing removed.')
    run('/usr/bin/systemctl', 'stop', 'frame-input.service')
    policy.unlink()
    UNIT.unlink()
    run('/usr/bin/systemctl', 'daemon-reload')
    # Preserve the root-only state folder and binary for recovery; no recursive delete.
    print('Service and passwordless rule removed. No server is running from this service.')
    print('Root-owned files remain in /var/lib/frame-input. Remove that folder explicitly after review.')
    print('Remove the two Steam Library entries and frame-input desktop shortcuts separately.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'install', 'uninstall'))
    parser.add_argument('--user', default=os.environ.get('SUDO_USER', os.environ.get('USER', 'steamos')))
    parser.add_argument('--server', type=Path)
    parser.add_argument('--usb-id')
    parser.add_argument('--minutes', type=int, default=0,
                        help='Session deadline in minutes: 0 means run until stopped (default); 1-480 enables a timer.')
    args = parser.parse_args()
    try:
        if args.action == 'uninstall':
            uninstall()
        else:
            if not args.usb_id:
                parser.error('--usb-id is required')
            if args.action == 'plan':
                unit, policy, config = render(args.user, args.usb_id, args.minutes)
                print(f'UNIT {UNIT}\n{unit}\nSUDOERS {SUDOERS}\n{policy}\nCONFIG {BASE}/state/config.ini\n{config}')
            else:
                if args.server is None:
                    parser.error('--server is required')
                install(args)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'Frame Input: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
