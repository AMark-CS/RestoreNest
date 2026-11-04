<#
.SYNOPSIS
  Prints JSON: { "protectionOn": bool, "recoveryPasswords": [ "123456-..." ] } for the Windows drive. Needs administrator rights.
#>
[CmdletBinding()]
param([string]$Drive = $env:SystemDrive)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')
. (Join-Path $PSScriptRoot 'RestorePlan.Common.ps1')
$info = Get-RnBitLockerInfo -Drive $Drive
ConvertTo-Json -InputObject ([ordered]@{ protectionOn = [bool]$info.protectionOn; recoveryPasswords = @($info.recoveryPasswords) }) -Compress
