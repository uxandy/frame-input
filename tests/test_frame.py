"""No root, system service, network or real USB operations are performed."""
import importlib.util
import contextlib
import io
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

PACKAGE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('frame_install', PACKAGE / 'frame/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_normalizes_receiver_without_broadening_scope(self):
        self.assertEqual(installer.usb_pair('0123:0045'), '123/45')
        for bad in ('', '*', '1234/*', '1234:5678,ffff:ffff', '1234:5678\nUser=root', '0000:0001'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                installer.usb_pair(bad)

    def test_disallows_invalid_duration_or_policy_injection(self):
        for user in ('root', 'steamos ALL=(ALL) ALL', 'bob\nroot', 'ALL'):
            with self.subTest(user=user), self.assertRaises(ValueError):
                installer.render(user, '1234:5678', 30)
        for minutes in (-1, 481):
            with self.subTest(minutes=minutes), self.assertRaises(ValueError):
                installer.render('player', '1234:5678', minutes)

    def test_manual_lifetime_keeps_stop_permissions_and_receiver_scope(self):
        unit, policy, config = installer.render('player', '1234:5678', 0)
        timed_unit, timed_policy, timed_config = installer.render('player', '1234:5678', 30)
        self.assertEqual(unit, timed_unit.replace('RuntimeMaxSec=1800\n', 'RuntimeMaxSec=infinity\n'))
        self.assertEqual(policy, timed_policy)
        self.assertEqual(config, timed_config)
        self.assertIn('TimeoutStopSec=5s\n', unit)
        self.assertIn('/usr/bin/systemctl stop frame-input.service', policy)
        self.assertNotIn('[Install]', unit)
        self.assertIn('Restart=no\n', unit)

    def test_service_limits_survive_steam_process_exit(self):
        unit, policy, config = installer.render('player', '1234:5678', 30)
        self.assertIn('RuntimeMaxSec=1800\n', unit)
        self.assertIn('TimeoutStopSec=5s\n', unit)
        self.assertIn('Restart=no\n', unit)
        self.assertNotIn('[Install]', unit)
        self.assertNotIn('/home/', unit)
        self.assertNotIn(' -b', unit)
        self.assertNotIn('*', policy)
        self.assertIn('NOPASSWD: /usr/bin/systemctl start frame-input.service, /usr/bin/systemctl stop frame-input.service', policy)
        self.assertIn('AllowedDevices=1234/5678\n', config)
        self.assertIn('AutoAttachToKernel=1\n', config)

    def test_wrong_architecture_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'server'
            for machine in (62, 183):
                data = bytearray(20)
                data[:6] = b'\x7fELF\x02\x01'
                data[18:20] = machine.to_bytes(2, 'little')
                binary.write_bytes(data)
                if machine == 183:
                    installer.check_elf(binary)
                else:
                    with self.assertRaises(ValueError):
                        installer.check_elf(binary)

    def test_existing_file_or_symlink_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            original = Path(directory) / 'original'
            original.write_text('keep me')
            link = Path(directory) / 'link'
            link.symlink_to(original)
            for destination in (original, link):
                with self.assertRaises(FileExistsError):
                    installer.write_new(destination, 'replacement', 0o644)
            self.assertEqual(original.read_text(), 'keep me')

    def test_private_config_permissions(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'config'
            installer.write_new(destination, 'data', 0o600)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)

    def test_partial_write_is_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'partial'
            with self.assertRaises(UnicodeError):
                installer.write_new(destination, '\ud800', 0o644)
            self.assertFalse(destination.exists())

    def test_install_transaction_and_rollback(self):
        real_temporary_directory = tempfile.TemporaryDirectory
        for minutes, fail_at in ((0, None), (1, None), (1, 'visudo'), (1, 'systemd-analyze'), (1, 'daemon-reload'), (0, 'passwordless')):
            with self.subTest(minutes=minutes, fail_at=fail_at), real_temporary_directory() as directory:
                root = Path(directory)
                server = root / 'downloaded-server'
                header = bytearray(20)
                header[:6] = b'\x7fELF\x02\x01'
                header[18:20] = (183).to_bytes(2, 'little')
                server.write_bytes(header)
                base, unit, policy = root / 'installed', root / 'unit', root / 'policy'
                calls = []

                def command(*args):
                    calls.append(args)
                    if (fail_at == 'passwordless' and args[0] == '/usr/bin/sudo') or (fail_at and any(fail_at in value for value in args)):
                        raise OSError('simulated installation failure')

                def staging(*args, **kwargs):
                    return real_temporary_directory(prefix='stage-', dir=root)

                args = SimpleNamespace(user='player', usb_id='1234:5678', minutes=minutes, server=server)
                with patch.object(installer, 'BASE', base), patch.object(installer, 'UNIT', unit), \
                     patch.object(installer, 'SUDOERS', policy), patch.object(installer, 'LEGACY_SUDOERS', root / 'old-policy'), \
                     patch.object(installer, 'require_platform'), \
                     patch.object(installer.pwd, 'getpwnam', return_value=SimpleNamespace(pw_uid=1000)), \
                     patch.object(installer.tempfile, 'TemporaryDirectory', side_effect=staging), \
                     patch.object(installer, 'run', side_effect=command), \
                     patch.object(installer.subprocess, 'run'), contextlib.redirect_stdout(io.StringIO()):
                    if fail_at:
                        with self.assertRaises(OSError):
                            installer.install(args)
                        self.assertFalse(base.exists())
                        self.assertFalse(unit.exists())
                        self.assertFalse(policy.exists())
                    else:
                        installer.install(args)
                        self.assertTrue(unit.exists() and policy.exists())
                        self.assertEqual((base / 'state/config.ini').stat().st_mode & 0o777, 0o600)
                        self.assertEqual(policy.stat().st_mode & 0o777, 0o440)
                        self.assertEqual((base / 'vhusbdarm64').stat().st_mode & 0o777, 0o755)
                        expected_runtime = 'infinity' if minutes == 0 else '60'
                        self.assertIn(f'RuntimeMaxSec={expected_runtime}\n', unit.read_text())
                        self.assertIn(('/usr/bin/sudo', '-u', 'player', '--', '/usr/bin/sudo', '-n', '-k',
                                       '/usr/bin/systemctl', 'stop', 'frame-input.service'), calls)
                self.assertFalse(any('start' in call or 'enable' in call for call in calls))
                self.assertEqual(server.read_bytes(), header)

    def test_uninstall_refuses_modified_unit_before_stopping(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / 'manifest.json').write_text('{"format":"frame-input-v1","unit_sha256":"wrong"}')
            unit = base / 'service'
            unit.write_text('changed by someone else')
            # Exercise the validation after the platform/owner preconditions separately.
            with patch.object(installer, 'require_platform'), patch.object(installer, 'BASE', base), \
                 patch.object(installer, 'UNIT', unit), patch.object(installer, 'run') as run, \
                 patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=0, st_mode=0o40755)):
                with self.assertRaisesRegex(ValueError, 'was changed'):
                    installer.uninstall()
                run.assert_not_called()
            self.assertEqual(unit.read_text(), 'changed by someone else')

    def test_install_refuses_legacy_permission_file(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            legacy = root / 'frame-input'
            legacy.write_text('existing policy')
            args = SimpleNamespace(user='player', usb_id='1234:5678', minutes=0, server=root / 'server')
            with patch.object(installer, 'BASE', root / 'base'), patch.object(installer, 'UNIT', root / 'unit'), \
                 patch.object(installer, 'SUDOERS', root / 'zz-frame-input'), patch.object(installer, 'LEGACY_SUDOERS', legacy), \
                 patch.object(installer, 'require_platform'), patch.object(installer, 'check_elf'), \
                 patch.object(installer.pwd, 'getpwnam', return_value=SimpleNamespace(pw_uid=1000)), \
                 patch.object(installer, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'already exists'):
                    installer.install(args)
                run.assert_not_called()
            self.assertEqual(legacy.read_text(), 'existing policy')
            self.assertFalse((root / 'zz-frame-input').exists())

    @contextlib.contextmanager
    def installed_tree(self, policy_names):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            base = root / 'base'
            base.mkdir()
            unit = root / 'unit'
            unit.write_text('test unit')
            policy = 'player ALL=(root) NOPASSWD: /usr/bin/systemctl stop frame-input.service\n'
            for name in policy_names:
                (root / name).write_text(policy)
            (base / 'manifest.json').write_text(json.dumps({
                'format': 'frame-input-v1', 'user': 'player',
                'unit_sha256': hashlib.sha256(unit.read_bytes()).hexdigest(),
                'sudoers_sha256': hashlib.sha256(policy.encode()).hexdigest(),
            }))
            (base / 'retained').write_text('keep server and state')
            (root / 'wheel').write_text('unrelated rule')
            real_stat = Path.stat

            def owned_stat(path, *args, **kwargs):
                result = real_stat(path, *args, **kwargs)
                if path == base:
                    fields = list(result)
                    fields[4] = 0  # Simulate only the installation directory's owner.
                    return os.stat_result(fields)
                return result

            with patch.object(installer, 'BASE', base), patch.object(installer, 'UNIT', unit), \
                 patch.object(installer, 'SUDOERS', root / 'zz-frame-input'), \
                 patch.object(installer, 'LEGACY_SUDOERS', root / 'frame-input'), \
                 patch.object(installer, 'require_platform'), patch.object(Path, 'stat', owned_stat), \
                 patch.object(installer, 'run') as run, contextlib.redirect_stdout(io.StringIO()):
                yield root, base, unit, run

    def test_uninstall_handles_legacy_and_renamed_policy(self):
        for name in ('frame-input', 'zz-frame-input'):
            with self.subTest(name=name), self.installed_tree([name]) as (root, base, unit, run):
                installer.uninstall()
                self.assertFalse((root / name).exists())
                self.assertFalse(unit.exists())
                self.assertEqual((base / 'retained').read_text(), 'keep server and state')
                self.assertEqual((root / 'wheel').read_text(), 'unrelated rule')
                self.assertEqual(run.call_args_list[0].args, ('/usr/bin/systemctl', 'stop', 'frame-input.service'))
                self.assertEqual(run.call_args_list[1].args, ('/usr/bin/systemctl', 'daemon-reload'))

    def test_uninstall_refuses_missing_duplicate_modified_or_linked_policy(self):
        for case in ('missing', 'duplicate', 'modified', 'symlink'):
            names = [] if case == 'missing' else ['zz-frame-input']
            if case == 'duplicate':
                names.append('frame-input')
            with self.subTest(case=case), self.installed_tree(names) as (root, base, unit, run):
                if case == 'modified':
                    (root / 'zz-frame-input').write_text('changed')
                elif case == 'symlink':
                    (root / 'zz-frame-input').rename(root / 'target')
                    (root / 'zz-frame-input').symlink_to(root / 'target')
                with self.assertRaises(ValueError):
                    installer.uninstall()
                run.assert_not_called()
                self.assertTrue(unit.exists())
                self.assertEqual((root / 'wheel').read_text(), 'unrelated rule')


if __name__ == '__main__':
    unittest.main()
