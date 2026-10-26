# Updating, removal, and manual fallback

## Working installations

0.1.3-alpha adds the public documentation, source packaging and CI. Runtime files are unchanged from 0.1.2. Windows runtime files are unchanged from the original 0.1.0 tests. A working setup does not need reinstalling for this release.

For a 0.1.0/0.1.1 installation with a password prompt, use the targeted [sudo filename repair](troubleshooting.md#start-sharing-says-a-sudo-password-is-required). Keep a current installer for uninstall: it understands both the original and corrected filenames.

When only the Frame's address or selected receiver changes, rerun Windows setup from the same package folder and save. Matching Desktop shortcuts are reused; other VirtualHere settings are not reset.

## Change the Frame installation

There is no in-place upgrade or timer editor in this alpha. To change the receiver model or session deadline, first release the receiver and stop sharing. Use the uninstall procedure below, then move the retained `/var/lib/frame-input` directory to a private backup location before reinstalling. The installer refuses to overwrite it.

Do not edit a running VirtualHere config: [the vendor notes that it writes that file](https://www.virtualhere.com/configuration_faq). The uninstaller verifies the unit and policy content hashes and refuses modified or ambiguous files; inspect any such error instead of bypassing the checks. OS updates can require rechecking service files and sudo permissions.

## Uninstall on Frame

Release the receiver in Windows first. In the current extracted package folder on Frame:

```sh
sudo python3 frame/install.py uninstall
```

This stops the service, removes its systemd unit and the matching narrow sudo rule, and reloads systemd. It accepts exactly one matching rule at either `/etc/sudoers.d/frame-input` or `/etc/sudoers.d/zz-frame-input`. It refuses changed files, symlinks, or ambiguous rules.

The uninstaller deliberately **retains `/var/lib/frame-input`** with the downloaded binary and private state for review/recovery. After successful uninstall, you can preserve it under a new name before reinstalling:

```sh
frame_backup="/var/lib/frame-input-backup-$(date +%Y%m%d-%H%M%S)"
sudo mv -T -n -- /var/lib/frame-input "$frame_backup"
```

Confirm the move succeeded before another install. Keep the backup private; it can contain vendor state. Alternatively review and delete that directory yourself when you no longer need it. The original manual test/download folder in your home directory is not removed.

Remove the two non-Steam Library entries, and remove these application-menu files from your normal account:

```sh
rm -f -- "$HOME/.local/share/applications/frame-input-start.desktop" \
  "$HOME/.local/share/applications/frame-input-stop.desktop"
```

## Remove the Windows helper

Use **Return to Frame** first. Delete only the **Use Frame Keyboard & Mouse** and **Return to Frame** Desktop shortcuts, the `%LOCALAPPDATA%\FrameInput` settings folder, and the extracted Frame Input package when no longer needed.

The VirtualHere client, vendor driver and its manually added server entry are separate. This helper does not uninstall or reset them; manage those through VirtualHere if desired.

## Use the original manual setup temporarily

If you kept a previously working manual server/config, stop the installed service before starting it. Using the original test-folder names:

```sh
sudo /usr/bin/systemctl stop frame-input.service
sudo "$HOME/virtualhere-frame-test/vhusbdarm64" \
  -c "$HOME/virtualhere-frame-test/config.ini"
```

The manual server runs in the foreground until Ctrl+C. Use the stock Windows client to select its receiver, then **Stop Using** to return it. Do not start the installed service until the manual server has stopped. A different server name requires Windows helper setup again; stock client selection is useful for a temporary fallback.

This fallback assumes the original manual files exist and previously worked. A fresh installation has only the service path unless you performed a separate manual test.
