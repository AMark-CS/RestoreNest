<#
.SYNOPSIS
  Adds (or removes) a "RestoreNest Recovery" boot menu entry that boots a WinPE ramdisk stored next to the restore points.
.DESCRIPTION
  Copies boot.wim and boot.sdi to <Root>\boot, exports the current BCD to <Root>\boot\bcd-backup-<time>.bcd first, then
  creates the entry with bcdedit WITHOUT changing the default OS. -Remove deletes only the entry recorded in
  <Root>\boot\bootentry.json. -DryRun prints the bcdedit commands and changes nothing (no admin rights needed).
  Use -Store when running from WinPE against the EFI system partition's BCD.
.EXAMPLE
  .\Install-BootEntry.ps1 -Root D:\RestoreNest -BootWim E:\winpe\boot.wim -BootSdi E:\winpe\boot.sdi -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$BootWim, [string]$BootSdi,
    [string]$Store,
    [switch]$Remove, [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')
. (Join-Path $PSScriptRoot 'RestorePlan.Common.ps1')

if ($Root -notmatch '\A[A-Za-z]:\\') { throw 'Root must be an absolute local path such as D:\RestoreNest.' }
if (-not $DryRun) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required.' }
}
$letter = $Root.Substring(0, 1)
if ($letter -ieq $env:SystemDrive.TrimEnd(':') -and -not $Store) { throw 'The recovery image must not live on the Windows partition.' }
$bootDir = Join-Path $Root 'boot'
$stateFile = Join-Path $bootDir 'bootentry.json'
$plan = Get-RnBootEntryPlan -Root $Root -Letter $letter
$storeArgs = if ($Store) { @('/store', $Store) } else { @() }

function Invoke-Bcd {
    param([string[]]$Arguments)
    $line = 'bcdedit ' + (($storeArgs + $Arguments) -join ' ')
    if ($DryRun) { Write-Host "[dry-run] $line"; return '{00000000-0000-0000-0000-000000000000}' }
    $out = & bcdedit @storeArgs @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "bcdedit failed ($LASTEXITCODE): $line`n$out" }
    $out
}

if ($Remove) {
    if (-not (Test-Path -LiteralPath $stateFile)) { throw 'No RestoreNest boot entry is recorded for this location.' }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($state.entry -notmatch '\A\{[0-9a-fA-F-]{36}\}\z') { throw 'Recorded entry id is invalid.' }
    [void](Invoke-Bcd @('/delete', $state.entry, '/cleanup'))
    if ($state.PSObject.Properties['timeoutChanged'] -and $state.timeoutChanged -and $null -ne $state.originalTimeout) { [void](Invoke-Bcd @('/timeout', [string]$state.originalTimeout)) }
    if (-not $DryRun) { Remove-Item -LiteralPath $stateFile -Force }
    Write-Host 'Boot entry removed.'
    return
}

if (-not $BootWim -or -not $BootSdi) { throw 'Specify -BootWim and -BootSdi (see tools\Build-WinPE.ps1).' }
foreach ($f in $BootWim, $BootSdi) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "File not found: $f" } }
if (Test-Path -LiteralPath $stateFile) { throw 'An entry is already installed here; use -Remove first.' }
if (-not $DryRun -and -not $Store) {
    $bl = & manage-bde -status $env:SystemDrive 2>&1 | Out-String
    if ($bl -match 'Protection On') { Write-Warning 'BitLocker protection is ON. Changing the boot configuration may make Windows ask for the recovery key at the next boot; make sure you have it.' }
}

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
    # Re-registration from Restore.ps1 passes the already-installed files; copying a file onto itself would fail.
    foreach ($pair in @(@($BootWim, 'boot.wim'), @($BootSdi, 'boot.sdi'))) {
        $dest = Join-Path $bootDir $pair[1]
        if ([IO.Path]::GetFullPath($pair[0]) -ine [IO.Path]::GetFullPath($dest)) { Copy-Item -LiteralPath $pair[0] -Destination $dest -Force }
    }
    $backup = Join-Path $bootDir ('bcd-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bcd')
    # `bcdedit /store <file> /export` is rejected by bcdedit; an offline store is just a file, so copy it.
    if ($Store) { Copy-Item -LiteralPath $Store -Destination $backup -Force } else { [void](Invoke-Bcd @('/export', $backup)) }
}
$existing = if ($DryRun) { '' } else { & bcdedit @storeArgs /enum '{ramdiskoptions}' 2>&1 | Out-String }
if ($existing -notmatch 'ramdisksdipath') { [void](Invoke-Bcd @('/create', '{ramdiskoptions}', '/d', '"RestoreNest ramdisk options"')) }
[void](Invoke-Bcd @('/set', '{ramdiskoptions}', 'ramdisksdidevice', "partition=$($plan.Letter):"))
[void](Invoke-Bcd @('/set', '{ramdiskoptions}', 'ramdisksdipath', $plan.SdiPath))
$created = Invoke-Bcd @('/create', '/d', "`"$($plan.Description)`"", '/application', 'osloader')
if ($created -notmatch '(\{[0-9a-fA-F-]{36}\})') { throw "Could not read the new entry id from: $created" }
$entry = $Matches[1]
foreach ($pair in @(@('device', $plan.Device), @('osdevice', $plan.Device), @('path', '\windows\system32\boot\winload.efi'), @('systemroot', '\windows'), @('winpe', 'yes'), @('detecthal', 'yes'))) {
    [void](Invoke-Bcd @('/set', $entry, $pair[0], $pair[1]))
}
[void](Invoke-Bcd @('/displayorder', $entry, '/addlast'))
# The menu only appears with a non-zero timeout. Leave an existing timeout alone; if it is 0 (menu hidden) enable 10 s and
# remember the original so -Remove can put it back.
$timeoutChanged = $false; $originalTimeout = $null
$mgr = if ($DryRun) { '' } else { & bcdedit @storeArgs /enum '{bootmgr}' 2>&1 | Out-String }
if ($mgr -match '(?m)^timeout\s+(\d+)') { $originalTimeout = [int]$Matches[1] }
if ($DryRun -or $originalTimeout -eq 0) { [void](Invoke-Bcd @('/timeout', '10')); $timeoutChanged = $true }
if (-not $DryRun) {
    @{ entry = $entry; created = (Get-Date).ToUniversalTime().ToString('o'); timeoutChanged = $timeoutChanged; originalTimeout = $originalTimeout } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
    Write-Host "Boot entry $entry installed. Default OS unchanged."
}
