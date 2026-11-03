<#
.SYNOPSIS
  Creates a restore point: a VSS-consistent WIM capture of the Windows partition plus meta.json.
.DESCRIPTION
  Output: <Destination>\RestoreNest\<yyyyMMdd-HHmmss>\{system.wim, meta.json}. Needs wimlib-imagex.exe
  (default tools\bin\wimlib-imagex.exe; check its license before redistributing). Captured to a *.partial folder
  and renamed only after the hash and metadata are written, so an interrupted run never looks like a restore point.
  Existing restore points are never modified. The backup may live on a different partition of the same physical disk.
.EXAMPLE
  .\New-RestorePoint.ps1 -Destination D:\ -Name "before driver update"
  .\New-RestorePoint.ps1 -Destination D:\ -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [string]$Name,
    [string]$WimlibPath = (Join-Path $PSScriptRoot 'bin\wimlib-imagex.exe'),
    [string]$SystemDrive = $env:SystemDrive.TrimEnd(':'),
    [switch]$DryRun,
    [switch]$SkipAdminCheck,
    # Offline capture (e.g. from WinPE, where the Windows volume is not in use and VSS does not exist).
    [switch]$NoSnapshot,
    [ValidateSet('LZX', 'XPRESS', 'LZMS', 'None')][string]$Compression = 'LZX'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')

if (-not $DryRun -and -not $SkipAdminCheck) {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required (VSS).' }
}
if (-not (Test-Path -LiteralPath $WimlibPath -PathType Leaf)) { throw "wimlib-imagex.exe not found at $WimlibPath. Pass -WimlibPath or place it in tools\bin." }

$systemVolume = Get-Volume -DriveLetter $SystemDrive
$used = [long]($systemVolume.Size - $systemVolume.SizeRemaining)
# Reclaim space from interrupted earlier captures before checking free space (skipped on a dry run: it must not delete anything).
if (-not $DryRun -and $Destination -match '\A[A-Za-z]:') {
    $guess = if ($Destination.TrimEnd('\').Length -le 2) { Join-Path $Destination 'RestoreNest' } else { $Destination.TrimEnd('\') }
    foreach ($gone in @(Remove-RnStalePartials -Root $guess)) { Write-Verbose "Removed stale partial capture: $gone" }
}
# LZX typically shrinks well, but demand 60% of used space as a conservative floor; wimlib will fail loudly if still short.
$root = Resolve-RnDestination -Destination $Destination -SystemDrive $SystemDrive -RequiredBytes ([long]($used * 0.6))
$source = Get-RnVolumeIdentity -DriveLetter $SystemDrive
$id = New-RnRestorePointId
$final = Join-Path $root $id
$partial = "$final.partial"
if ((Test-Path -LiteralPath $final) -or (Test-Path -LiteralPath $partial)) { throw "Restore point $id already exists; wait a second and retry." }

$plan = [pscustomobject]@{ Id = $id; Root = $root; Source = $source; UsedBytes = $used; Wim = (Join-Path $partial 'system.wim') }
if ($DryRun) { return $plan }

New-Item -ItemType Directory -Path $partial -Force | Out-Null
try {
    $config = Join-Path $partial 'capture.ini'
    Set-Content -LiteralPath $config -Value (Get-RnCaptureConfig) -Encoding Unicode
    $arguments = Get-RnWimlibCaptureArguments -SourceDrive $SystemDrive -WimPath $plan.Wim -ImageName "RestoreNest $id" -ConfigPath $config -Compression $Compression -NoSnapshot:$NoSnapshot
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $captureExit = Invoke-RnNative -FilePath $WimlibPath -Arguments $arguments
    if ($captureExit -ne 0) { throw "wimlib capture failed (exit $captureExit)." }
    $item = Get-Item -LiteralPath $plan.Wim
    $hash = (Get-FileHash -LiteralPath $plan.Wim -Algorithm SHA256).Hash
    Write-RnMeta -Directory $partial -Id $id -Name $Name -Source $source -WimSha256 $hash -WimBytes $item.Length | Out-Null
    Remove-Item -LiteralPath $config -Force
    Move-Item -LiteralPath $partial -Destination $final
    Write-Verbose ("Captured in {0:N0} s" -f $watch.Elapsed.TotalSeconds)
    Get-RnRestorePoints -Root $root | Where-Object Id -eq $id
}
catch {
    # Leave nothing that could be mistaken for a complete restore point.
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue }
    throw
}
