# SPDX-License-Identifier: MIT
# Core logic is separated from Windows UI so selection and failure paths can be tested.
Set-StrictMode -Version 2.0

function ConvertFrom-VHList {
    param([Parameter(Mandatory=$true)][string]$Text)
    $hubName = $null
    $hubEndpoint = $null
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*-->\s*(?<name>.+?)\s+\((?<address>[A-Za-z0-9_.:-]+\.[0-9]+)(?<star>\*?)\)(?<tail>.*)$') {
            if (-not $hubEndpoint) { throw 'Device row without a server identity. Inspect the VirtualHere LIST format.' }
            $deviceName = $Matches.name.Trim()
            $automatic = $deviceName.StartsWith('*') -or $Matches.star -eq '*' -or $Matches.tail.Contains('*')
            $deviceName = $deviceName.TrimStart('*').Trim()
            [pscustomobject]@{
                HubName = $hubName; HubEndpoint = $hubEndpoint
                DeviceName = $deviceName; DeviceAddress = $Matches.address
                AutoUse = [bool]$automatic; Detail = $Matches.tail.Trim()
                Label = "$hubName [$hubEndpoint] - $deviceName ($($Matches.address))"
            }
        } elseif ($line -match '^\s*(?<name>.+?)\s+\((?<endpoint>[A-Za-z0-9_.-]+:[0-9]+)\)\s*$') {
            $hubName = $Matches.name.Trim()
            $hubEndpoint = $Matches.endpoint
        } elseif ($line -match '-->') {
            throw 'Unrecognized VirtualHere device row. No device will be selected automatically.'
        }
    }
}

function Assert-FrameConfig {
    param($Config)
    foreach ($name in @('FormatVersion','ClientPath','ServerEndpoint','HubName','HubEndpoint','DeviceName','DeviceAddress')) {
        if (-not $Config.PSObject.Properties[$name]) { throw "Missing setting: $name. Run setup again." }
    }
    if ($Config.FormatVersion -ne 1) { throw 'Unsupported configuration version.' }
    if ($Config.ServerEndpoint -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*:7575$') { throw 'Use a hostname or IPv4 address followed by :7575.' }
    if ($Config.HubEndpoint -notmatch '^[A-Za-z0-9_.-]+:[0-9]+$' -or
        $Config.DeviceAddress -notmatch '^[A-Za-z0-9_.:-]+\.[0-9]+$') { throw 'Invalid VirtualHere device identity. Run setup again.' }
    if ([string]::IsNullOrWhiteSpace($Config.HubName) -or [string]::IsNullOrWhiteSpace($Config.DeviceName)) { throw 'A selected server and receiver are required.' }
    if ([string]::IsNullOrWhiteSpace($Config.ClientPath) -or $Config.ClientPath.Contains('"')) { throw 'Invalid client executable path.' }
}

function Find-FrameReceiver {
    param($Config, [string]$List)
    Assert-FrameConfig $Config
    $devices = @(ConvertFrom-VHList $List)
    $selected = @($devices | Where-Object {
        $_.HubName -ceq $Config.HubName -and $_.HubEndpoint -ieq $Config.HubEndpoint -and
        $_.DeviceAddress -ieq $Config.DeviceAddress -and $_.DeviceName -ceq $Config.DeviceName
    })
    if ($selected.Count -gt 1) { throw 'Ambiguous receiver identity. Nothing claimed; run setup again.' }
    if ($selected.Count -eq 1) { return $selected[0] }
    return $null
}

function Invoke-VHCommand {
    param([string]$ClientPath, [string]$Command)
    if (-not (Test-Path -LiteralPath $ClientPath -PathType Leaf)) { throw 'VirtualHere client executable not found. Run setup again.' }
    if ($Command -match '["\r\n]' -or $ClientPath.Contains('"')) { throw 'Invalid API argument.' }
    $outputFile = [IO.Path]::GetTempFileName()
    $process = $null
    try {
        # Windows GUI executables need -r; do not infer success from stdout or exit code.
        $arguments = '-t "' + $Command + '" -r "' + $outputFile + '"'
        $process = Start-Process -FilePath $ClientPath -ArgumentList $arguments -PassThru
        if (-not $process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit(1000) | Out-Null
            throw 'VirtualHere API timed out. A request may have completed; inspect the client before retrying.'
        }
        $response = [IO.File]::ReadAllText($outputFile).Trim()
        if (-not $response -or $response -match '^(FAILED|ERROR|IPC ERROR)') {
            throw "VirtualHere API did not confirm the request: $response"
        }
        return $response
    } finally {
        if ($null -ne $process) { $process.Dispose() }
        Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-VHOK {
    param([string]$ClientPath, [string]$Command)
    $response = Invoke-VHCommand $ClientPath $Command
    if ($response -cne 'OK') { throw "VirtualHere did not acknowledge $Command. Response: $response" }
}

function Start-FrameClient {
    param([string]$ClientPath)
    try { return (Invoke-VHCommand $ClientPath 'LIST') } catch { }
    if (-not (Test-Path -LiteralPath $ClientPath -PathType Leaf)) { throw 'Choose the installed vhui64.exe first.' }
    Start-Process -FilePath $ClientPath | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        Start-Sleep -Milliseconds 500
        try { return (Invoke-VHCommand $ClientPath 'LIST') } catch { $lastError = $_ }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Client is not ready. Dismiss any first-run or driver prompts in VirtualHere. $lastError"
}

function Invoke-FrameAction {
    param($Config, [ValidateSet('Use','Return')][string]$Action, [int]$WaitSeconds = 20)
    Assert-FrameConfig $Config
    Start-FrameClient $Config.ClientPath | Out-Null
    if ($Action -eq 'Use') {
        Invoke-VHOK $Config.ClientPath ('MANUAL HUB ADD,' + $Config.ServerEndpoint)
    }
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    do {
        $list = Invoke-VHCommand $Config.ClientPath 'LIST'
        $target = Find-FrameReceiver $Config $list
        if ($null -ne $target) { break }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 400
    } while ($true)
    if ($null -eq $target) {
        throw 'The configured receiver is not visible. Start Sharing on the Frame. If its port, name or server identity changed, run setup again. To recover locally, use Frame Stop Sharing.'
    }
    if ($Action -eq 'Use') {
        if ($target.AutoUse -or $list -match '(?im)^\s*Auto-Use All currently on\s*$') {
            throw 'Disable Auto-Use for this receiver/server in VirtualHere before using these manual shortcuts. Existing settings were not changed.'
        }
        Invoke-VHOK $Config.ClientPath ('USE,' + $target.DeviceAddress)
    } else {
        Invoke-VHOK $Config.ClientPath ('STOP USING,' + $target.DeviceAddress)
    }
    # An OK confirms the API request, not successful HID behavior or local return.
}
