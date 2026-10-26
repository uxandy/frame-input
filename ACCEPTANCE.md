# Frame Input acceptance record

Version: 0.1.3-alpha. Updated: 2026-10-26. Runtime scripts are unchanged from 0.1.2-alpha; Windows scripts are unchanged from 0.1.0-alpha. The original tester installed 0.1.1 on Frame and repaired the sudo filename; they subsequently confirmed the shortcuts work on both Windows and Frame. These are user-reported hardware results, separate from automated logic tests.

| Check | Result |
| --- | --- |
| Manual generic server 4.8.8 on ARM64 Frame | User-confirmed running |
| Manual 15-second server timer under GNU timeout 9.5 | User output: stopping, exit 124; receiver unclaimed |
| Manual receiver Use sends both mouse and keyboard to Windows | User-confirmed |
| Manual Stop Using restores Frame input | User-confirmed |
| Frame built-in systemctl, sudo, visudo, zenity, kdialog, notify-send, Python | User-supplied command output |
| Installer guardrails, rendering, failure rollback and old/new policy removal | 13 local Python tests pass, including failed passwordless-check rollback, legacy/moved policy removal and refusal of ambiguous/modified files; temporary-filesystem transactions and mocked system commands; no root/system changes |
| PowerShell parsing, selection, IPC failure/timeout and targeting | 25 assertions pass under portable PowerShell 7.6.0 on macOS; API/processes mocked |
| Bash syntax | Pass; launchers not executed |
| Windows setup UI, discovery and shortcut creation | User-confirmed; discovery succeeded on retry without a code change |
| Windows Use shortcut sends keyboard/mouse to Windows; Return restores Frame input | Both user-confirmed using the existing manual server |
| Exact Windows PowerShell and VirtualHere client versions | Not collected |
| Root installer and unit/policy validation on Frame | User output confirms successful 0.1.1 installation, stopped, without boot autostart; a warning about another unit did not block verification |
| Frame application-menu shortcut registration | User output confirms both entries created; manual foreground server subsequently stopped |
| Frame desktop Start Sharing without a password | User-confirmed after renaming the rule; dialog now says Sharing is available |
| Passwordless Stop without cached credentials on the installed Frame | User-supplied `sudo -n -k` command succeeded while service was stopped; not yet a claimed-device recovery test |
| New installer verifies passwordless Stop without cached credentials | Local command/rollback tests pass; real Frame test pending |
| Windows and Frame shortcut workflow after service installation | Tester confirms both sides work flawlessly on 2026-10-26 |
| Empty receiver list under a connected server | Tester identified the cause: the dongle was not plugged in; no software change required |
| Frame library launch and simultaneous SteamVR streaming | Frame shortcuts reported working; exact launch surface and live-stream focus/interruption behavior not separately recorded |
| Frame service stop specifically while receiver claimed; optional timer expiry | General Frame shortcut success reported; exact claimed-device recovery scenario and optional timer expiry not separately recorded |
| Local exclusivity, held modifiers, disconnect, sleep/wake and sustained RTS | Pending |
| Reboot remains off; uninstall and manual fallback | Pending |

## Further validation

Basic shortcut operation on both devices is confirmed. The ordered procedure below remains useful for other testers and for completing the specifically unverified fault/lifecycle cases. The public alpha does not claim those pending cases have passed.

1. Windows setup, receiver selection, generated shortcuts and actual Use/Return are user-confirmed against the existing manual server. Record exact client/runtime versions privately when available. If an address/name changes, rerun setup; do not broaden selection.
2. Transfer the updated package to Frame. Release the receiver and stop the manual server. Preview and install the Frame service with `--minutes 0`, matching the owner's explicit preference to stop manually, then create desktop shortcuts. Verify Desktop Start/Stop without claiming first. Keep independent SSH available for `sudo systemctl stop frame-input.service`.
3. Run Windows setup again for Frame-Input. Claim from Windows, stop from the Frame launcher using controllers, and verify local return. This service-stopped recovery is a separate check from the already confirmed Windows Return shortcut.
4. Add both shortcuts to Steam. Start sharing locally before streaming; verify Use/Return. Then test whether the local Stop Sharing shortcut is reachable without interrupting the stream. Record actual focus/lifecycle behavior; do not assume desktop results establish VR behavior.
5. Verify no receiver activity reaches a harmless local Frame editor while Windows owns it. Test modifiers, scrolling, dragging and interrupted sessions with no unsaved work. Verify no stuck input, including when video stops before USB forwarding.
6. Test sustained productivity/RTS use with explicit stopping. Optional timed-mode acceptance remains separate: a fresh installation can use `--minutes 1` to verify expiry while claimed. Changing runtime policy is an installation action in this alpha; the launcher accepts no user-supplied root arguments. Do not remove a working installation just to force a timer into the owner's normal workflow.
7. Verify restart leaves sharing off. Test removal of the unit and permission rule, including refusal to remove modified files. Confirm the original manual setup remains available when the service is off.

Record user observations distinctly from automated tests. Do not commit private addresses, receiver identifiers, logs or generated Windows settings. Replace pending rows only with actual evidence; publishing an alpha does not change those results.
