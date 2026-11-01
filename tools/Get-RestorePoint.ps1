<#
.SYNOPSIS
  Lists restore points under a destination, optionally verifying their integrity.
.EXAMPLE
  .\Get-RestorePoint.ps1 -Destination D:\ -Verify
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Destination,
    [switch]$Verify,
    [switch]$Json,
    [string]$WimlibPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')

$full = [IO.Path]::GetFullPath($Destination)
$root = if ($full.TrimEnd('\').Length -le 2) { Join-Path $full 'RestoreNest' } else { $full.TrimEnd('\') }
$rows = @(foreach ($point in @(Get-RnRestorePoints -Root $root)) {
    $status = 'unchecked'
    if ($Verify) {
        try { [void](Test-RnRestorePoint -Directory $point.Path -WimlibPath $WimlibPath); $status = 'ok' }
        catch { $status = 'FAILED: ' + $_.Exception.Message }
    }
    [pscustomobject]@{ Id = $point.Id; Name = $point.Meta.name; CreatedUtc = [string]$point.Meta.createdUtc; SizeGiB = [math]::Round($point.Meta.wim.sizeBytes / 1GB, 2); Status = $status; Path = $point.Path }
})
if ($Json) { ConvertTo-Json -InputObject $rows -Compress } else { $rows }
