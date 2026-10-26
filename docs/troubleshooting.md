# Troubleshooting and recovery

Start with the symptom below. Keep a Frame terminal or independent SSH session available for early testing. Release held keys/buttons before changing ownership.

## Green Frame-Input server, but no receiver underneath

**Check that the dongle is physically plugged into the Frame.** This exact symptom occurred during setup because the receiver was unplugged. A green server entry only establishes a server connection.

Check Frame detection:

```sh
lsusb -t
```

If the external device is absent, check its OTG connection and verify that it works locally. If it is present, compare its vendor/product ID with the installed allowlist. Read only the relevant settings rather than posting the full config (which may contain a vendor license):

```sh
sudo sed -n '/^ServerName=/p; /^AllowedDevices=/p; /^IgnoredDevices=/p; /^IgnoredBuses=/p' /var/lib/frame-input/state/config.ini
sudo journalctl -b -u frame-input.service -n 50 --no-pager
```

Do not widen the allowlist to all devices. Once the receiver appears under the server in the stock VirtualHere client, click **Find receiver** again in Frame Input setup.

## Find receiver reports nothing, but the vendor client shows it

- Dismiss any trial/driver dialog. Leave the existing VirtualHere client running and retry Find receiver.
- Check the server name is **Frame-Input** or **Frame-Input-Test**. The helper deliberately filters to those names.
- Make sure the address includes `:7575` and points at the Frame's home-network interface.
- If you changed a USB port, device name, server name, or address, rerun setup and explicitly select the receiver.

To inspect what the vendor API reports, run this in **Windows PowerShell**, replacing the first path with your client path:

```powershell
$vhClient = 'C:\Path\To\vhui64.exe'
$vhOutput = [System.IO.Path]::GetTempFileName()
try {
    Start-Process -FilePath $vhClient -ArgumentList ('-t LIST -r "{0}"' -f $vhOutput) -Wait
    Get-Content -LiteralPath $vhOutput
} finally {
    Remove-Item -LiteralPath $vhOutput -ErrorAction SilentlyContinue
}
```

The helper uses VirtualHere's [documented API](https://www.virtualhere.com/client_api). It refuses unfamiliar device rows rather than selecting another device. Redact addresses and names before posting output.

## Server absent or stuck connecting

Start Sharing on Frame, then inspect:

```sh
systemctl status --no-pager frame-input.service
sudo journalctl -b -u frame-input.service -n 50 --no-pager
```

If port 7575 is already in use, release the device and stop the old foreground server with Ctrl+C in its original terminal. Do not run both servers. If the service is active, check the Frame's current home-network IP and whether the PCs are separated by guest-network/client isolation. Do not disable all firewall protection or expose the server to the internet.

If you chose a session timer, expiry stops the service and can show a failed unit. Start another session when ready. There is no timer in the default installation.

## Start Sharing says a sudo password is required

Through the Frame terminal/SSH, inspect:

```sh
sudo -l
sudo visudo -c
```

The exact NOPASSWD Start/Stop rule must take effect after any matching general password rule. [Sudo applies matching rules in order](https://man.archlinux.org/man/sudoers.5.en); checking a fragment's syntax alone does not verify the effective permission.

Versions 0.1.0/0.1.1 used `/etc/sudoers.d/frame-input`, which preceded the tested SteamOS wheel rule. If that old file exists, the new filename does not, and `sudo -l` shows our specific rule followed by `(ALL) ALL`, rename **only our fragment**:

```sh
sudo mv -n -- /etc/sudoers.d/frame-input /etc/sudoers.d/zz-frame-input
sudo -l
```

Check the order again. While sharing is stopped, verify without cached credentials:

```sh
sudo -n -k /usr/bin/systemctl stop frame-input.service
```

Then retry desktop Start. Versions 0.1.2 and newer install the corrected filename and check passwordless Stop automatically. Use a current installer for future uninstall after renaming; old installers only know the old filename. Do not change unrelated sudo fragments or grant general passwordless sudo to fix this.

## Installer refuses an existing path or readonly filesystem

The installer deliberately refuses to overwrite a previous installation and does not change SteamOS readonly protection. Inspect the reported path. For an existing Frame Input installation, follow [maintenance](maintenance.md). If the filesystem is readonly on your build, retain the working manual setup and report the build/error; do not remount the OS writable as an automatic workaround.

## Windows shortcut points at an old folder

Setup saves settings before creating shortcuts. If an existing shortcut points at another package folder, it refuses to overwrite it and says **Settings saved, but an unrelated/older shortcut exists**.

Prefer keeping the original package folder. If you deliberately moved it, inspect and move aside only the two old Frame Input Desktop shortcuts, then rerun setup from the new permanent folder. Do not delete unrelated shortcuts or reinstall the vendor driver.

## API timeout, receiver already in use, or Auto-Use conflict

Open the vendor client and inspect the receiver before retrying. A timed-out request may already have completed. The helper does not retry an uncertain claim/release automatically. Stop Using from the client that owns it if appropriate.

Turn off Auto-Use for the receiver/server and Auto-Use All for this manual workflow. The helper does not clear those settings for you. If it detects conflicting Auto-Use, it refuses the claim.

## Return fails or Windows becomes unavailable

1. Try VirtualHere's **Stop Using** for the receiver if Windows remains accessible.
2. Use the Frame controllers to launch **Frame Input - Stop Sharing**.
3. Or run `sudo /usr/bin/systemctl stop frame-input.service` through a Frame terminal/independent SSH session.
4. After the service is stopped, unplug/replug only the external receiver if needed.

Video streaming and USB sharing are separate connections. Losing the video stream is not a request to release the receiver. Fault recovery, sleep/wake and held-key cleanup need testing on each setup. Avoid testing those failures with unsaved work.

## Report a problem

Use a [GitHub issue](https://github.com/uxandy/frame-input/issues) with the package version, SteamOS/Steam build, Windows/PowerShell version, VirtualHere server/client versions, expected behavior and exact error. Say whether the stock VirtualHere client can see/use the receiver and whether it works locally on Frame. Remove usernames, IP addresses, hostnames, serials and license data from logs/screenshots. Never post the full runtime config or credentials.
