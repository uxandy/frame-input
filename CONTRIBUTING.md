# Contributing

The Frame and Windows runtime scripts have no third-party language dependencies. Keep changes small and preserve explicit ownership: Frame Start/Stop controls the server; Windows Use/Return controls one saved receiver.

## Local checks

On Linux or macOS, from the repository root:

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash -n frame/control.sh
bash -n frame/install-shortcuts.sh
python3 package.py
```

Run the PowerShell checks with either PowerShell 7 or Windows PowerShell 5.1:

```powershell
pwsh -NoProfile -File tests/test_windows.ps1
# On Windows, also test the actual launcher runtime:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_windows.ps1
```

Python installer tests require POSIX (`pwd` and filesystem ownership/modes); run them on Linux/macOS, not Windows. They use temporary files and mock system commands. PowerShell tests parse scripts and mock vendor API/process calls. Neither suite claims USB hardware or WinForms UI validation. CI runs Linux tests and both Windows PowerShell runtimes.

## Repository layout

| Path | Purpose |
| --- | --- |
| `frame/install.py` | Preview/install/uninstall the narrow system service |
| `frame/control.sh` | Graphical Start/Stop feedback |
| `frame/install-shortcuts.sh` | Register application-menu entries |
| `windows/FrameInput.ps1` | Setup UI, settings and Desktop shortcuts |
| `windows/VirtualHere.ps1` | Device selection and vendor API calls |
| `tests` | Synthetic regression cases |
| `docs` | User setup, recovery and maintenance |
| `package.py` | Explicit allowlist for the source-only ZIP |

## Changes and reports

- Preserve exact device selection and fail on ambiguous identities. Never fall back to claiming the first available device or disconnecting all devices.
- Do not broaden sudo permissions, edit Steam's shortcut database automatically, or add boot/reconnect behavior without an explicit design change.
- Add meaningful regression coverage for changed failure/recovery behavior. Hardware reports should state exact versions and distinguish observations from assumptions.
- Keep credentials, private addresses, real device identifiers, logs and generated settings out of commits. Use synthetic examples such as documentation-range IPs in tests.
- Do not bundle VirtualHere executables, drivers or licenses. The MIT license covers this wrapper and illustration only.

Before publishing a version, update `VERSION`, the changelog and versioned download/setup references. Run the checks, build `dist/frame-input-VERSION.zip`, verify its `MANIFEST.json` hashes, and publish a matching SHA256SUMS file. Include only the package allowlist in a standalone source export. Keep untested acceptance items marked pending when releasing an alpha.
