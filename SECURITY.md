# Security and installed files

This alpha is intended for a trusted home LAN. Its standard TCP connection on port 7575 has no authentication or encryption, and the server listens on available network interfaces. The receiver model allowlist limits which USB devices are exported; it does not restrict who can connect. Do not port-forward this service. Frame Input does not configure firewall rules, remote tunnels, credentials, or VirtualHere's optional paid access-control features.

## Changes made by the installer

| Location | Purpose |
| --- | --- |
| `/var/lib/frame-input` | Root-owned server copy, launchers, manifest and private runtime state |
| `/etc/systemd/system/frame-input.service` | On-demand system service; no boot enablement or restart policy |
| `/etc/sudoers.d/zz-frame-input` | Only exact Start/Stop commands for the chosen normal account |
| `~/.local/share/applications/frame-input-*.desktop` | Two application-menu entries created separately as the normal user |
| `%LOCALAPPDATA%\FrameInput\config.json` | Windows-local selected client/server/receiver settings |
| Windows Desktop | Two shortcuts pointing at the extracted package |

The server runs as root for USB access. Its files are not writable by the normal account. The service has `NoNewPrivileges`, home-directory protection and a private temporary directory. These restrictions do not make an unauthenticated USB server safe on an untrusted network. The installer validates executable format but does not authenticate vendor downloads.

The Windows launchers use a process-only PowerShell execution-policy argument. They do not change machine/user policy or install a Windows service. Obtain the helper and vendor software from their respective official sources, and review scripts before running them with elevated permissions.

## Reporting

Use the repository's [private vulnerability reporting](https://github.com/uxandy/frame-input/security/advisories/new) for security problems. Do not include passwords, license keys, full configuration files or identifying device logs in public issues. Ordinary bugs can use the public issue template with sanitized output.
