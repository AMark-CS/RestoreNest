<#
.SYNOPSIS
  Run by the scheduled task: creates a restore point from the saved schedule settings and keeps only the newest ones.
.DESCRIPTION
  Never deletes the last remaining restore point to make room: if the drive is too full even after removing every older point,
  it stops with the status 'no-space' and the newest point stays. Records the outcome in schedule-status.json (read by the app).
  A missing destination drive (for example an unplugged USB disk) or a capture already in progress is a skipped run, not a failure.
#>
[CmdletBinding()]
param(
    [string]$WimlibPath,
    [string]$SystemDrive,
    [switch]$SkipAdminCheck,        # tests only
    [long]$RequiredBytesOverride = 0   # tests only
)
$ErrorActionPreference = 'Stop'
# This runs unattended as SYSTEM. There $PSScriptRoot was empty in the parameter defaults ("Cannot bind argument to parameter
# 'Path' because it is an empty string") and the script died before it could write anything, so the folder is taken from the
# invocation instead and nothing is computed in the parameter block.
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $WimlibPath) { $WimlibPath = Join-Path $scriptDir 'bin\wimlib-imagex.exe' }
if (-not $SystemDrive) { $SystemDrive = $env:SystemDrive.TrimEnd(':') }
. (Join-Path $scriptDir 'RestorePoint.Common.ps1')
. (Join-Path $scriptDir 'RestoreSchedule.Common.ps1')

# Everything this run prints goes to schedule-last-run.log next to the settings; nobody watches a scheduled task.
$logPath = Join-Path (Get-RnDataDirectory) 'schedule-last-run.log'
New-Item -ItemType Directory -Force -Path (Split-Path $logPath) | Out-Null
try { Start-Transcript -LiteralPath $logPath -Force | Out-Null } catch { }
try {
    $settings = Read-RnScheduleSettings
    if (-not $settings.enabled) { Write-RnScheduleStatus -Code 'disabled'; return }

    try { $root = Resolve-RnDestination -Destination $settings.destination -SystemDrive $SystemDrive }
    catch { Write-RnScheduleStatus -Code 'destination-unavailable' -Detail $_.Exception.Message; return }
    $letter = $root.Substring(0, 1)

    if (Test-RnCaptureRunning -Root $root) { Write-RnScheduleStatus -Code 'busy' -Detail 'a capture is already running'; return }

    $required = if ($RequiredBytesOverride -gt 0) { $RequiredBytesOverride } else { Get-RnRequiredBytes -SystemDrive $SystemDrive }
    $removed = @()
    $points = @(Get-RnRestorePoints -Root $root)
    # Make room by deleting the oldest points, but always leave the newest one.
    while ((Get-Volume -DriveLetter $letter).SizeRemaining -lt $required -and $points.Count -gt 1) {
        $oldest = @($points | Sort-Object Id)[0]
        Remove-RnRestorePoint -Point $oldest -Root $root
        $removed += $oldest.Id
        $points = @(Get-RnRestorePoints -Root $root)
    }
    $free = (Get-Volume -DriveLetter $letter).SizeRemaining
    if ($free -lt $required) {
        Write-RnScheduleStatus -Code 'no-space' -Detail ('need about {0:N1} GiB, have {1:N1} GiB' -f ($required / 1GB), ($free / 1GB)) -PointCount $points.Count -Removed $removed
        exit 1
    }

    $newPoint = $null
    try {
        $arguments = @{ Destination = $root; Name = ('Auto ' + (Get-Date -Format 'yyyy-MM-dd')); WimlibPath = $WimlibPath; SystemDrive = $SystemDrive }
        if ($SkipAdminCheck) { $arguments.SkipAdminCheck = $true }
        $newPoint = & (Join-Path $scriptDir 'New-RestorePoint.ps1') @arguments
    }
    catch {
        Write-RnScheduleStatus -Code 'capture-failed' -Detail $_.Exception.Message -PointCount @(Get-RnRestorePoints -Root $root).Count -Removed $removed
        exit 1
    }

    # Retention only after the new point exists, so a failed capture never costs an old one.
    $points = @(Get-RnRestorePoints -Root $root)
    foreach ($old in @(Get-RnPointsToPrune -Points $points -Keep $settings.keep)) { Remove-RnRestorePoint -Point $old -Root $root; $removed += $old.Id }
    Write-RnScheduleStatus -Code 'ok' -Detail $(if ($newPoint) { [string]$newPoint.Id } else { '' }) -PointCount @(Get-RnRestorePoints -Root $root).Count -Removed $removed
}
catch {
    Write-RnScheduleStatus -Code 'error' -Detail $_.Exception.Message
    exit 1
}
finally { try { Stop-Transcript | Out-Null } catch { } }
