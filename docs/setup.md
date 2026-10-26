# Setup: Steam Frame and Windows

This guide is for **0.1.3-alpha**. Frame commands run in the headset's desktop terminal or an SSH session connected to it; Windows steps run on the gaming PC. Use the commands in order.

The installer does not download dependencies, disable SteamOS readonly protection, or enable boot autostart. If an expected tool/path is unavailable, stop at that error and see [troubleshooting](troubleshooting.md).

## 1. Get the package onto both devices

Download the ZIP asset from the [release page](https://github.com/uxandy/frame-input/releases/tag/v0.1.3-alpha). It contains one `frame-input-0.1.3-alpha` folder. Keep the extracted Windows copy in a permanent location, for example under Documents; its shortcuts will point there.

Copy the same ZIP into your Frame home folder using a file transfer tool. If SSH is already enabled, you can use `scp` from a Mac/Linux terminal or Windows PowerShell. Replace `FRAME_USER` and `FRAME_HOST` with your normal Frame login and reachable Wi-Fi address/hostname:

```sh
scp frame-input-0.1.3-alpha.zip FRAME_USER@FRAME_HOST:~/
ssh FRAME_USER@FRAME_HOST
```

SSH is optional; you can download/copy the ZIP and open a terminal directly on Frame. Do not run the Frame installer on your Mac or Windows PC.

In the **Frame terminal**, extract and open the folder:

```sh
python3 -m zipfile -e "$HOME/frame-input-0.1.3-alpha.zip" "$HOME"
cd "$HOME/frame-input-0.1.3-alpha"
```

For a Git checkout or GitHub's automatically generated source archive, use its actual extracted folder instead. The release ZIP has the layout used above.

## 2. Check the Frame and plug in the receiver

Plug the external keyboard/mouse receiver into the Frame through its OTG adapter. Confirm both devices work on the Frame desktop first.

```sh
uname -m
command -v python3 systemctl systemd-analyze sudo visudo curl lsusb
command -v zenity kdialog
```

Expected architecture: `aarch64`. The first tool list should resolve every command. At least one of `zenity` or `kdialog` must be present for dialogs. You need your normal account's sudo password for installation; password input is not shown. If you have not set a login password, set one with `passwd` from your normal Frame desktop account before using sudo.

### Find your receiver's USB ID

Run:

```sh
lsusb
lsusb -t
```

In ordinary `lsusb` output, `ID 1234:5678` means vendor `1234`, product `5678`. That is an example, not a receiver you should copy. If `lsusb` prints nothing, `lsusb -t` can still show connected HID interfaces, as it did on the tested headset.

To list model IDs directly from Linux sysfs without collecting serial numbers:

```sh
python3 - <<'PY'
from pathlib import Path
for device in sorted(Path('/sys/bus/usb/devices').iterdir()):
    try:
        vendor = (device / 'idVendor').read_text().strip()
        product = (device / 'idProduct').read_text().strip()
        label = (device / 'product').read_text().strip() if (device / 'product').exists() else ''
        print(f'{device.name}: {vendor}:{product} {label}')
    except OSError:
        continue
PY
```

Compare before/after unplugging **only the external receiver** if necessary. Select the device that disappears and returns; do not select a USB root hub or internal headset device. Plug it back in before continuing.

Store the ID in your current Frame terminal. Replace the placeholder:

```sh
frame_usb_id='VENDOR:PRODUCT'
```

The installer validates the format and converts it to VirtualHere's hexadecimal allowlist format. One USB model is allowed; multiple receivers with the same model ID are not distinguished by this allowlist.

## 3. Download VirtualHere separately

**Already have a working manual setup?** Keep your downloaded server and client. Skip the server download and point `frame_server` at your existing ARM64 executable, for example:

```sh
frame_server="$HOME/virtualhere-frame-test/vhusbdarm64"
```

**Fresh setup:** the [official Linux server page](https://www.virtualhere.com/usb_server_software) links the generic Linux ARM64 build, `vhusbdarm64`. In the Frame terminal:

```sh
mkdir -p "$HOME/virtualhere-frame"
curl --fail --location --proto '=https' \
  -o "$HOME/virtualhere-frame/vhusbdarm64" \
  https://www.virtualhere.com/sites/default/files/usbserver/vhusbdarm64
chmod u+x "$HOME/virtualhere-frame/vhusbdarm64"
frame_server="$HOME/virtualhere-frame/vhusbdarm64"
"$frame_server" -h
```

These commands download and show help; they do not start sharing. The hardware test used server **4.8.8**. The vendor URL can change versions, so note the version printed. The installer checks the executable's ARM64 format, not publisher authenticity; obtain it from the official source.

On **Windows**, download the x86_64 client **`vhui64.exe`** from the [official client page](https://www.virtualhere.com/usb_client_software) into a permanent folder. Run it, complete any vendor driver/trial prompts, and use its tray icon's **Show** command to open the window. Leave your existing working client running if you already have one. You do not need to install the client as a Windows service.

## 4. Install the Frame service

If an earlier manual server is running, first choose **Stop Using** on its receiver in Windows, then press **Ctrl+C** in the Frame terminal running that server. The manual server and the service cannot both listen on port 7575.

Return to the package folder in your Frame terminal. `frame_usb_id` and `frame_server` must still be set from above; set them again if you opened a new terminal.

Preview what will be installed, without changing the system:

```sh
python3 frame/install.py plan --user "$USER" --usb-id "$frame_usb_id" --minutes 0
```

Check that the allowlist contains your receiver and the sudo rule names your normal Frame account. Then install:

```sh
sudo python3 frame/install.py install --user "$USER" \
  --server "$frame_server" --usb-id "$frame_usb_id" --minutes 0
```

Expected ending: **Installed and stopped, with no session deadline; use Stop Sharing to end the session. No boot autostart.** The installer validates its unit and permission rule and verifies passwordless Stop as your account without relying on a cached password.

Create the application-menu entries **without sudo**:

```sh
/var/lib/frame-input/install-shortcuts.sh
```

The default `--minutes 0` runs until stopped. For an automatic session deadline, use an integer from 1 to 480 in both preview and install. Starting an already running service does not reset its deadline. There is no in-place settings editor in this alpha; see [maintenance](maintenance.md) before changing an installation.

## 5. Check Frame Start and Stop

From the Frame desktop application menu, open **Frame Input - Start Sharing**. It should say **Sharing is available** without asking for a password. This confirms the service is active; Windows still needs to claim the receiver.

Open **Frame Input - Stop Sharing**, then Start Sharing again. Leave it running for Windows setup.

Keep this recovery command ready in a Frame terminal or independent SSH session during the first claim:

```sh
sudo -n /usr/bin/systemctl stop frame-input.service
```

The narrow passwordless rule covers that exact stop command. `status`, logs, and other administrative commands have separate permissions.

Find the Frame's home-network address:

```sh
ip -4 -brief address show scope global
```

Use the address reachable from Windows on your home Wi-Fi, without the `/24` or other prefix suffix. On the tested Frame this was `wlan0`; an additional `wlanap` interface was not the home-LAN address. Enter the address followed by `:7575` in Windows setup. A DHCP reservation in your router can keep it stable.

## 6. Create the Windows shortcuts

On the **Windows gaming PC**:

1. Open your permanent extracted folder, then `windows`.
2. Double-click **Set up Frame Input.cmd**.
3. Browse to your existing **vhui64.exe**.
4. Enter the Frame's home-network hostname or IPv4 address followed by **`:7575`**.
5. Choose **Find receiver**. Complete any VirtualHere prompt, then retry if needed.
6. Select **USB Receiver** (or your receiver's actual name) under **Frame-Input**.
7. Choose **Save and create shortcuts**.

The Windows Desktop gets **Use Frame Keyboard & Mouse** and **Return to Frame**. Keep Auto-Use off for this receiver/server and Auto-Use All off while using this manual workflow. Other client settings/connections are preserved.

Test **Use Frame Keyboard & Mouse** in a harmless Windows editor: move the mouse and type. Release held keys, click **Return to Frame**, and check input on the Frame desktop. A successful request dialog is not a substitute for that input check. Next, while Windows owns the receiver, use your controllers to launch Frame **Stop Sharing** and verify local return.

Existing manual users: the helper also recognizes **Frame-Input-Test**. When moving to the installed **Frame-Input** server, rerun setup from your existing Windows folder, find/select the new receiver entry, and save. Matching Desktop shortcuts are reused. Do not move the Windows folder just to change server selection.

## 7. Add Start/Stop to the Frame's Steam Library

On the **Frame's desktop Steam client**, use **Games → Add a Non-Steam Game to My Library** (or **Add a Game → Add a Non-Steam Game**). Select both:

- **Frame Input - Start Sharing**
- **Frame Input - Stop Sharing**

If the application list does not show them, use **Browse**, set the file filter to all files if needed, and add these installed executables one at a time:

```text
/var/lib/frame-input/start-sharing
/var/lib/frame-input/stop-sharing
```

Rename the entries as above if Steam uses the filenames. Run them locally on the Frame as Linux programs; leave forced Proton compatibility off. These entries belong in the Frame's local library, not the Windows PC's library. [Valve's general shortcut instructions](https://help.steampowered.com/en/faqs/view/4B8B-9697-2338-40EC) describe the desktop add flow; UI labels may differ by Steam build.

Test each shortcut. For your first stream, launch Start Sharing before streaming, then use the Windows Desktop shortcut through the streamed view. Confirm how to reach the local Stop shortcut on your build before depending on it during a live stream. The tester reports working Frame shortcuts; detailed in-stream focus/interruption behavior is still uncharacterized.

You can now use the [daily workflow](../README.md#daily-use). Ending the video stream or closing a launcher dialog does **not** stop USB sharing.
