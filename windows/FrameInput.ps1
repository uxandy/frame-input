#Requires -Version 5.1
# SPDX-License-Identifier: MIT
param([ValidateSet('Setup','Use','Return')][string]$Action = 'Setup')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'VirtualHere.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$settingsDirectory = Join-Path $env:LOCALAPPDATA 'FrameInput'
$settingsFile = Join-Path $settingsDirectory 'config.json'

function Show-FrameMessage([string]$Message, [bool]$Failed = $false) {
    $icon = [Windows.Forms.MessageBoxIcon]::Information
    if ($Failed) { $icon = [Windows.Forms.MessageBoxIcon]::Error }
    [Windows.Forms.MessageBox]::Show($Message, 'Frame Input', [Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

function New-FrameShortcuts {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $PSScriptRoot 'FrameInput.ps1'
    foreach ($item in @(@('Use Frame Keyboard & Mouse','Use'), @('Return to Frame','Return'))) {
        $path = Join-Path $desktop ($item[0] + '.lnk')
        $arguments = '-NoProfile -STA -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Action ' + $item[1]
        if (Test-Path -LiteralPath $path) {
            $existing = $shell.CreateShortcut($path)
            if ($existing.TargetPath -ine $powershell -or $existing.Arguments -cne $arguments) {
                throw "Settings saved, but an unrelated/older shortcut exists: $path. Move or remove that shortcut before running setup again."
            }
            continue
        }
        $shortcut = $shell.CreateShortcut($path)
        $shortcut.TargetPath = $powershell
        $shortcut.Arguments = $arguments
        $shortcut.WorkingDirectory = $PSScriptRoot
        $shortcut.Description = $item[0]
        $shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',44'
        $shortcut.Save()
    }
}

function Show-FrameSetup {
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Frame Input - Setup'
    $form.ClientSize = New-Object Drawing.Size(740, 460)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font('Segoe UI', 11)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false

    $label = New-Object Windows.Forms.Label
    $label.Text = 'Start Sharing on the Frame first. Then choose your Windows VirtualHere client.'
    $label.SetBounds(20, 15, 700, 42)
    $form.Controls.Add($label)
    $client = New-Object Windows.Forms.TextBox
    $client.SetBounds(20, 62, 570, 30)
    $form.Controls.Add($client)
    $browse = New-Object Windows.Forms.Button
    $browse.Text = 'Browse...'
    $browse.SetBounds(600, 60, 120, 36)
    $form.Controls.Add($browse)
    $browse.Add_Click({
        $picker = New-Object Windows.Forms.OpenFileDialog
        $picker.Title = 'Choose your existing VirtualHere Windows client'
        $picker.Filter = 'VirtualHere client (vhui64.exe)|vhui64.exe'
        if ($picker.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $client.Text = $picker.FileName }
        $picker.Dispose()
    })

    $addressLabel = New-Object Windows.Forms.Label
    $addressLabel.Text = 'Frame Wi-Fi address or hostname, followed by :7575'
    $addressLabel.SetBounds(20, 110, 690, 28)
    $form.Controls.Add($addressLabel)
    $address = New-Object Windows.Forms.TextBox
    $address.SetBounds(20, 142, 570, 30)
    $form.Controls.Add($address)
    $find = New-Object Windows.Forms.Button
    $find.Text = 'Find receiver'
    $find.SetBounds(600, 140, 120, 36)
    $form.Controls.Add($find)
    $receiverLabel = New-Object Windows.Forms.Label
    $receiverLabel.Text = 'Select your receiver under Frame-Input. Only this device will be used.'
    $receiverLabel.SetBounds(20, 190, 700, 30)
    $form.Controls.Add($receiverLabel)
    $receivers = New-Object Windows.Forms.ListBox
    $receivers.SetBounds(20, 224, 700, 150)
    $receivers.DisplayMember = 'Label'
    $form.Controls.Add($receivers)
    $save = New-Object Windows.Forms.Button
    $save.Text = 'Save and create shortcuts'
    $save.SetBounds(350, 394, 370, 46)
    $save.Enabled = $false
    $form.Controls.Add($save)
    $receivers.Add_SelectedIndexChanged({ $save.Enabled = $null -ne $receivers.SelectedItem })
    # Edits invalidate the discovered identity: don't save a new endpoint with old rows.
    $invalidate = { $receivers.Items.Clear(); $save.Enabled = $false }
    $address.Add_TextChanged($invalidate)
    $client.Add_TextChanged($invalidate)

    if (Test-Path -LiteralPath $settingsFile) {
        $previous = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
        $client.Text = $previous.ClientPath
        $address.Text = $previous.ServerEndpoint
    }
    $find.Add_Click({
        $find.Enabled = $false
        $form.UseWaitCursor = $true
        $receivers.Items.Clear()
        try {
            if ($address.Text -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*:7575$') { throw 'Enter a hostname or IPv4 address followed by :7575.' }
            Start-FrameClient $client.Text | Out-Null
            Invoke-VHOK $client.Text ('MANUAL HUB ADD,' + $address.Text)
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            do {
                $list = Invoke-VHCommand $client.Text 'LIST'
                $found = @(ConvertFrom-VHList $list | Where-Object { $_.HubName -eq 'Frame-Input' -or $_.HubName -eq 'Frame-Input-Test' })
                if ($found.Count -gt 0) { break }
                Start-Sleep -Milliseconds 400
            } while ([DateTime]::UtcNow -lt $deadline)
            if ($found.Count -eq 0) { throw 'No Frame-Input receiver found. Check Start Sharing, the address and any VirtualHere trial dialog.' }
            foreach ($device in $found) { $receivers.Items.Add($device) | Out-Null }
            # Deliberate selection: never choose the first connected USB device automatically.
            $receivers.SelectedIndex = -1
        } catch { Show-FrameMessage $_.Exception.Message $true }
        finally { $find.Enabled = $true; $form.UseWaitCursor = $false }
    })
    $save.Add_Click({
        try {
            $device = $receivers.SelectedItem
            if ($null -eq $device) { throw 'Select the intended receiver.' }
            $config = [pscustomobject]@{
                FormatVersion = 1; ClientPath = $client.Text; ServerEndpoint = $address.Text
                HubName = $device.HubName; HubEndpoint = $device.HubEndpoint
                DeviceName = $device.DeviceName; DeviceAddress = $device.DeviceAddress
            }
            Assert-FrameConfig $config
            [IO.Directory]::CreateDirectory($settingsDirectory) | Out-Null
            [IO.File]::WriteAllText($settingsFile, ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
            New-FrameShortcuts
            Show-FrameMessage 'Saved. Use the two new Desktop shortcuts: Use Frame Keyboard & Mouse and Return to Frame. Keep this package in its current folder.'
            $form.Close()
        } catch { Show-FrameMessage $_.Exception.Message $true }
    })
    $form.ShowDialog() | Out-Null
    $form.Dispose()
}

$mutex = New-Object Threading.Mutex($false, 'Local\FrameInputActions')
$held = $false
try {
    try { $held = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw 'Another Frame Input action is already running.' }
    if ($Action -eq 'Setup') {
        Show-FrameSetup
    } else {
        if (-not (Test-Path -LiteralPath $settingsFile)) { throw 'Run Set up Frame Input.cmd once first.' }
        $config = Get-Content -LiteralPath $settingsFile -Raw | ConvertFrom-Json
        Invoke-FrameAction $config $Action
        if ($Action -eq 'Use') {
            Show-FrameMessage 'Windows accepted the request to use your receiver. Test the keyboard and mouse. Open Return to Frame when finished.'
        } else {
            Show-FrameMessage 'Windows accepted the release request. Check that input works on the Frame again. Use Frame Stop Sharing to end the server session.'
        }
    }
} catch {
    Show-FrameMessage $_.Exception.Message $true
    exit 1
} finally {
    if ($held) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
