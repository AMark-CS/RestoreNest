<#
.SYNOPSIS
  Restarts the PC straight into the RestoreNest recovery environment (one time), without touching the boot menu order.
.DESCRIPTION
  Uses `bcdedit /bootsequence <entry>`: the recovery entry is booted once, at the next start only; afterwards the normal default
  applies again. Needs the entry installed by Prepare-Recovery.ps1 / Install-BootEntry.ps1 (recorded in <Root>\boot\bootentry.json).
  -NoRestart only sets the one-time boot target (tests).
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root, [switch]$NoRestart, [int]$DelaySeconds = 10)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required.' }
if ($Root.TrimEnd('\').Length -le 2) { $Root = Join-Path $Root 'RestoreNest' }
$stateFile = Join-Path $Root 'boot\bootentry.json'
if (-not (Test-Path -LiteralPath $stateFile)) { throw 'The recovery environment is not set up yet (no boot entry is recorded). Run Prepare-Recovery.ps1 first.' }
$entry = [string](Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).entry
if ($entry -notmatch '\A\{[0-9a-fA-F-]{36}\}\z') { throw 'The recorded boot entry id is invalid.' }
if (-not (Test-Path -LiteralPath (Join-Path $Root 'boot\boot.wim'))) { throw 'boot.wim is missing from the recovery folder.' }
$present = (& bcdedit.exe /enum all 2>&1 | Out-String) -match [regex]::Escape($entry)
if (-not $present) { throw 'The recovery entry is no longer in the boot configuration. Set up the recovery environment again.' }

& bcdedit.exe /bootsequence $entry | Out-Host
if ($LASTEXITCODE -ne 0) { throw "bcdedit /bootsequence failed ($LASTEXITCODE)." }
Write-Host "The next start will open the recovery environment ($entry)."
if (-not $NoRestart) { & shutdown.exe /r /t $DelaySeconds /c 'RestoreNest: restarting into the recovery environment' | Out-Host }
