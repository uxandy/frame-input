# Run with pwsh or Windows PowerShell 5.1. Uses synthetic data and fake API calls.
$ErrorActionPreference = 'Stop'
$package = Split-Path $PSScriptRoot -Parent
foreach ($file in Get-ChildItem (Join-Path $package 'windows') -Filter '*.ps1') {
    $tokens = $null; $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
. (Join-Path $package 'windows/VirtualHere.ps1')
$script:checks = 0
function Assert-True($Value, [string]$Description) {
    if (-not $Value) { throw "FAIL: $Description" }
    $script:checks++
}
function Assert-Throws([scriptblock]$Block, [string]$Description) {
    $thrown = $false
    try { & $Block } catch { $thrown = $true }
    Assert-True $thrown $Description
}
$list = @'
VirtualHere IPC, below are the available devices:
(Value in brackets = address, * = Auto-Use)
Other server (other:7575)
   --> USB Receiver (other.11)
Frame-Input (frame:7575)
   --> USB Receiver (frame.12)
Auto-Use All currently off
'@
$config = [pscustomobject]@{
    FormatVersion=1; ClientPath='C:\With Spaces\vhui64.exe'; ServerEndpoint='192.0.2.10:7575'
    HubName='Frame-Input'; HubEndpoint='frame:7575'; DeviceName='USB Receiver'; DeviceAddress='frame.12'
}
Assert-True (@(ConvertFrom-VHList $list).Count -eq 2) 'parse devices under distinct servers'
Assert-True ((Find-FrameReceiver $config $list).DeviceAddress -eq 'frame.12') 'select explicit receiver, not first USB device'
Assert-True ($null -eq (Find-FrameReceiver $config ($list.Replace('frame.12','frame.13')))) 'port change requires setup'
Assert-True ($null -eq (Find-FrameReceiver $config ($list.Replace('Frame-Input (frame:', 'Other (frame:')))) 'server rename requires setup'
Assert-Throws { Find-FrameReceiver $config ($list + "`nFrame-Input (frame:7575)`n --> USB Receiver (frame.12)") } 'duplicate identity rejected'
Assert-Throws { ConvertFrom-VHList " --> USB Receiver (frame.12)" } 'orphan device row rejected'
Assert-Throws { ConvertFrom-VHList " --> unknown vendor format" } 'unsupported format rejected'
$bad = $config.PSObject.Copy(); $bad.DeviceAddress = 'frame.12,other.11'
Assert-Throws { Assert-FrameConfig $bad } 'API argument injection rejected'

# Exercise -r capture, cleanup and timeout. Never start the vendor executable.
$script:response = 'OK'; $script:finished = $true; $script:killed = $false
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$PassThru)
    if ($ArgumentList -notmatch '-r "([^"]+)"$') { throw 'Output filename must be quoted.' }
    $script:outputPath = $Matches[1]
    [IO.File]::WriteAllText($script:outputPath, $script:response)
    $process = [pscustomobject]@{}
    $process | Add-Member ScriptMethod WaitForExit { param($Milliseconds) return $script:finished }
    $process | Add-Member ScriptMethod Kill { $script:killed = $true }
    $process | Add-Member ScriptMethod Dispose { }
    return $process
}
$fakeExe = [IO.Path]::GetTempFileName()
try {
    Assert-True ((Invoke-VHCommand $fakeExe 'LIST') -eq 'OK') 'GUI API response read from file'
    Assert-True (-not (Test-Path -LiteralPath $script:outputPath)) 'temporary response cleaned up'
    foreach ($response in @('FAILED','ERROR: unavailable','IPC ERROR','')) {
        $script:response = $response
        Assert-Throws { Invoke-VHCommand $fakeExe 'LIST' } 'API error/empty response fails'
    }
    $script:response = 'OK'; $script:finished = $false
    Assert-Throws { Invoke-VHCommand $fakeExe 'USE,frame.12' } 'hung IPC command fails with unknown-outcome message'
    Assert-True $script:killed 'only spawned IPC process terminated on timeout'
} finally { Remove-Item -LiteralPath $fakeExe -Force }
Remove-Item Function:Start-Process

# Fake IPC transport for orchestration tests; mutations are collected, never sent.
$script:deviceList = $list
$script:commands = @()
$script:failClaim = $false
function Start-FrameClient { param($ClientPath) return $script:deviceList }
function Invoke-VHCommand {
    param($ClientPath, $Command)
    $script:commands += $Command
    if ($Command -eq 'LIST') { return $script:deviceList }
    if ($Command.StartsWith('USE,') -and $script:failClaim) { throw 'Simulated request timeout' }
    return 'OK'
}
Invoke-FrameAction $config Use 0
Assert-True (($script:commands -join '|') -eq 'MANUAL HUB ADD,192.0.2.10:7575|LIST|USE,frame.12') 'Use targets only configured receiver'
$script:commands = @()
Invoke-FrameAction $config Return 0
Assert-True (($script:commands -join '|') -eq 'LIST|STOP USING,frame.12') 'Return does not disconnect unrelated devices'
$script:commands = @(); $script:deviceList = $list.Replace('frame.12','frame.13')
Assert-Throws { Invoke-FrameAction $config Use 0 } 'missing selected receiver fails'
Assert-True (@($script:commands | Where-Object { $_ -like 'USE,*' }).Count -eq 0) 'missing receiver never claims another'
$script:commands = @(); $script:deviceList = $list.Replace('currently off','currently on')
Assert-Throws { Invoke-FrameAction $config Use 0 } 'global auto-use refused without resetting settings'
Assert-True (@($script:commands | Where-Object { $_ -like 'USE,*' }).Count -eq 0) 'no manual claim under conflicting auto-use'
$script:deviceList = $list.Replace('USB Receiver (frame.12)', '*USB Receiver (frame.12)')
Assert-Throws { Invoke-FrameAction $config Use 0 } 'receiver auto-use refused'
$script:commands = @(); $script:deviceList = $list; $script:failClaim = $true
Assert-Throws { Invoke-FrameAction $config Use 0 } 'claim timeout propagated'
Assert-True (@($script:commands | Where-Object { $_ -like 'USE,*' }).Count -eq 1) 'uncertain mutation is not retried'
Write-Output "PASS: $script:checks checks; PowerShell scripts parsed; all API/process operations mocked."
