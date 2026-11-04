<#
.SYNOPSIS
  Restores a RestoreNest restore point onto the Windows partition it was taken from. Intended to run inside WinPE.
.DESCRIPTION
  Default is a DRY RUN: it locates restore points, verifies the WIM hash, resolves the target partition by GPT GUID,
  refuses to touch the partition holding the backup, and prints exactly which partitions would be written.
  With -Execute it formats ONLY the target Windows partition, applies the image, runs bcdboot against the existing
  EFI partition (which is not reformatted) and re-registers the recovery boot entry. Other partitions are not written.
  EXPERIMENTAL: not yet validated end to end in a VM. Never run -Execute on a machine you cannot afford to rebuild.
.EXAMPLE
  .\Restore.ps1                                  # list points, dry run on the chosen one
  .\Restore.ps1 -Id 20261031-153005 -Execute -ConfirmText "RESTORE 20261031-153005"
  .\Restore.ps1 -Id 20261031-153005 -RecoveryPassword 123456-123456-123456-123456-123456-123456-123456-123456
#>
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Id,
    [string]$WimlibPath,
    [switch]$Execute,
    [string]$ConfirmText,
    [string]$RecoveryPassword   # 48-digit BitLocker recovery password, used only when the Windows partition is locked
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')
. (Join-Path $PSScriptRoot 'RestorePlan.Common.ps1')
if (-not $WimlibPath) {
    $WimlibPath = @((Join-Path $PSScriptRoot 'wimlib-imagex.exe'), (Join-Path $PSScriptRoot 'bin\wimlib-imagex.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $WimlibPath) { throw 'wimlib-imagex.exe not found next to the script or in bin\.' }

# 1. Find backup roots on all NTFS volumes with a drive letter.
$roots = if ($Root) { @($Root) } else {
    @(Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -eq 'NTFS' } | ForEach-Object { "$($_.DriveLetter):\RestoreNest" } | Where-Object { Test-Path -LiteralPath $_ })
}
$points = @()
foreach ($r in $roots) { foreach ($p in @(Get-RnRestorePoints -Root $r)) { $points += [pscustomobject]@{ Root = $r; Point = $p } } }
if ($points.Count -eq 0) { throw 'No restore points found.' }

# 2. Choose.
if (-not $Id) {
    $i = 0
    foreach ($e in $points) { $i++; '{0}) {1}  {2}  [{3}]' -f $i, $e.Point.Id, $e.Point.Meta.name, $e.Root }
    $choice = Read-Host 'Number of the restore point'
    if ($choice -notmatch '\A\d+\z' -or [int]$choice -lt 1 -or [int]$choice -gt $points.Count) { throw 'Invalid choice.' }
    $selected = $points[[int]$choice - 1]
}
else {
    if (-not (Test-RnRestorePointId $Id)) { throw 'Invalid restore point id.' }
    $selected = @($points | Where-Object { $_.Point.Id -eq $Id })
    if ($selected.Count -ne 1) { throw "Restore point $Id not found (or ambiguous across volumes)." }
    $selected = $selected[0]
}
$point = $selected.Point
$meta = $point.Meta

# 3. Preflight. Nothing is written until every check passes.
Write-Host "Verifying image $($point.Id) ..."
[void](Test-RnRestorePoint -Directory $point.Path)
$partitions = Get-RnPartitionList
$backupLetter = $selected.Root.Substring(0, 1)
$backupPartition = @($partitions | Where-Object { $_.DriveLetter -ieq $backupLetter })
if ($backupPartition.Count -ne 1) { throw "Cannot identify the partition holding the backup ($backupLetter`:)." }
# A BitLocker-locked Windows partition shows no file system in WinPE. Unlock it with the recovery password first (nothing is written yet).
$locked = Find-RnLockedTarget -Meta $meta -Partitions $partitions
if ($locked) {
    Write-Host "The Windows partition ($($locked.DriveLetter):) is locked by BitLocker. It must be unlocked before it can be restored."
    $key = $RecoveryPassword
    if (-not $key) { $key = Read-Host 'BitLocker recovery password (48 digits; empty to cancel)' }
    Unlock-RnVolume -DriveLetter $locked.DriveLetter -RecoveryPassword $key
    $partitions = Get-RnPartitionList
}
$resolved = Resolve-RnRestoreTarget -Meta $meta -Partitions $partitions -BackupPartitionGuid $backupPartition[0].Guid
$target = $resolved.Target; $esp = $resolved.Esp
$bl = ''
try { $bl = (& manage-bde.exe -status 2>$null | Out-String) } catch { Write-Warning 'manage-bde is not available; BitLocker state could not be checked.' }
if ($bl -match 'Conversion Status:\s+(Fully|Used Space Only) Encrypted') { Write-Warning 'An encrypted volume is present; formatting the target removes its encryption.' }

Write-Host ''
Write-Host 'PLAN'
Write-Host ("  WRITE (format + apply): disk {0} partition {1}  GUID {2}  ({3:N1} GiB)" -f $target.DiskNumber, $target.PartitionNumber, $target.Guid, ($target.Size / 1GB))
Write-Host ("  WRITE (boot files only, not formatted): disk {0} partition {1}  EFI system partition" -f $esp.DiskNumber, $esp.PartitionNumber)
Write-Host ("  NOT TOUCHED: backup partition {0}  GUID {1}, and every other partition" -f $backupPartition[0].PartitionNumber, $backupPartition[0].Guid)
if (-not $Execute) { Write-Host 'Dry run only. Re-run with -Execute -ConfirmText "RESTORE <id>" to write.'; return }

$expected = "RESTORE $($point.Id)"
if (-not $ConfirmText) { $ConfirmText = Read-Host "Type '$expected' to confirm" }
if ($ConfirmText -cne $expected) { throw 'Confirmation text did not match; nothing was written.' }

# 4. Execute.
$log = Join-Path $selected.Root ("restore-$($point.Id)-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -LiteralPath $log | Out-Null
try {
    $tp = Get-Partition -DiskNumber $target.DiskNumber -PartitionNumber $target.PartitionNumber
    if ((ConvertTo-RnGuid $tp.Guid) -ne (ConvertTo-RnGuid $meta.source.partitionGuid)) { throw 'Target changed between planning and writing.' }
    if (-not $tp.DriveLetter) { $tp | Add-PartitionAccessPath -AssignDriveLetter; $tp = Get-Partition -DiskNumber $target.DiskNumber -PartitionNumber $target.PartitionNumber }
    $label = (Get-Volume -Partition $tp).FileSystemLabel
    $tl = $tp.DriveLetter
    Format-Volume -Partition $tp -FileSystem NTFS -NewFileSystemLabel $label -Force -Confirm:$false | Out-Null
    $applyExit = Invoke-RnNative -FilePath $WimlibPath -Arguments @(Get-RnWimlibApplyArguments -WimPath (Join-Path $point.Path 'system.wim') -TargetRoot "$tl`:")
    if ($applyExit -ne 0) { throw "wimlib apply failed ($applyExit). The target partition is now incomplete; boot RestoreNest Recovery again and retry." }

    $ep = Get-Partition -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber
    $espAssigned = $false
    if (-not $ep.DriveLetter) { $ep | Add-PartitionAccessPath -AssignDriveLetter; $ep = Get-Partition -DiskNumber $esp.DiskNumber -PartitionNumber $esp.PartitionNumber; $espAssigned = $true }
    $bootExit = Invoke-RnNative -FilePath 'bcdboot.exe' -Arguments @("$tl`:\Windows", '/s', "$($ep.DriveLetter):", '/f', 'UEFI')
    if ($bootExit -ne 0) { throw "bcdboot failed ($bootExit)." }

    # bcdboot normally keeps the existing store (VM test: the entry survived). Only if the recorded entry is gone, re-create it;
    # re-creating unconditionally left two identical entries.
    $stateFile = Join-Path $selected.Root 'boot\bootentry.json'
    if (Test-Path -LiteralPath $stateFile) {
        $store = "$($ep.DriveLetter):\EFI\Microsoft\Boot\BCD"
        $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        $present = (& bcdedit.exe /store $store /enum all 2>$null | Out-String) -match [regex]::Escape($state.entry)
        if ($present) { Write-Host 'Recovery boot entry is still present.' }
        else {
            Remove-Item -LiteralPath $stateFile -Force
            & (Join-Path $PSScriptRoot 'Install-BootEntry.ps1') -Root $selected.Root -BootWim (Join-Path $selected.Root 'boot\boot.wim') -BootSdi (Join-Path $selected.Root 'boot\boot.sdi') -Store $store
        }
    }
    Write-Host 'Restore finished. Restart the computer.'
}
finally { Stop-Transcript | Out-Null }
