#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Builds the RestoreNest recovery WinPE (boot.wim + boot.sdi) with the Windows ADK + WinPE add-on.
.DESCRIPTION
  Uses copype, adds WMI, .NET Framework, Scripting, PowerShell, StorageWMI and DISM cmdlets, copies the restore scripts and
  wimlib into the image, and sets startnet.cmd to launch tools\Restore.ps1. Output: <OutDir>\boot.wim and boot.sdi.
  Run from an elevated "Deployment and Imaging Tools Environment" or let the script locate the ADK.
  wimlib-imagex.exe is GPLv3+; supply your own copy with -WimlibPath and review the license before distributing the image.
.EXAMPLE
  .\Build-WinPE.ps1 -WimlibPath E:\tools\wimlib\wimlib-imagex.exe -OutDir E:\winpe-out
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WimlibPath,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$AdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit",
    [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) 'rn-winpe')
)
$ErrorActionPreference = 'Stop'
$pe = Join-Path $AdkRoot 'Windows Preinstallation Environment\amd64'
$copype = Join-Path $AdkRoot 'Windows Preinstallation Environment\copype.cmd'
$packages = Join-Path $pe 'WinPE_OCs'
if (-not (Test-Path -LiteralPath $copype)) { throw "ADK WinPE add-on not found under $AdkRoot." }
foreach ($f in $WimlibPath, (Join-Path (Split-Path $WimlibPath) 'libwim-15.dll')) { if (-not (Test-Path -LiteralPath $f)) { throw "Missing: $f (wimlib-imagex.exe needs libwim-15.dll beside it)." } }
if (Test-Path -LiteralPath $WorkDir) { throw "Work directory exists: $WorkDir. Remove it first." }

# copype needs the Deployment Tools environment (dism, oscdimg).
$env:Path = "$(Join-Path $AdkRoot 'Deployment Tools\amd64\DISM');$(Join-Path $AdkRoot 'Deployment Tools\amd64\Oscdimg');$env:Path"
& cmd.exe /c "`"$copype`" amd64 `"$WorkDir`""
if ($LASTEXITCODE -ne 0) { throw "copype failed ($LASTEXITCODE)." }

$mount = Join-Path $WorkDir 'mount'
$wim = Join-Path $WorkDir 'media\sources\boot.wim'
dism.exe /Mount-Image /ImageFile:$wim /Index:1 /MountDir:$mount
if ($LASTEXITCODE -ne 0) { throw 'Mount failed.' }
$committed = $false
try {
    # Order matters: WMI before NetFx/Scripting/PowerShell; StorageWMI and DismCmdlets after PowerShell.
    foreach ($name in 'WinPE-WMI', 'WinPE-NetFx', 'WinPE-Scripting', 'WinPE-PowerShell', 'WinPE-StorageWMI', 'WinPE-DismCmdlets') {
        dism.exe /Image:$mount /Add-Package /PackagePath:(Join-Path $packages "$name.cab") /PackagePath:(Join-Path $packages "en-us\$($name)_en-us.cab")
        if ($LASTEXITCODE -ne 0) { throw "Adding $name failed ($LASTEXITCODE)." }
    }
    $dest = Join-Path $mount 'restorenest'
    New-Item -ItemType Directory -Path $dest | Out-Null
    foreach ($script in 'Restore.ps1', 'RestorePoint.Common.ps1', 'RestorePlan.Common.ps1', 'Install-BootEntry.ps1') { Copy-Item (Join-Path $PSScriptRoot $script) $dest }
    Copy-Item $WimlibPath $dest
    Copy-Item (Join-Path (Split-Path $WimlibPath) 'libwim-15.dll') $dest
    $startnet = Join-Path $mount 'Windows\System32\startnet.cmd'
    Set-Content -LiteralPath $startnet -Encoding ascii -Value @(
        'wpeinit',
        'powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command "cd X:\restorenest; Write-Host ''RestoreNest Recovery'' ; Write-Host ''Dry run: .\Restore.ps1''; Write-Host ''Restore: .\Restore.ps1 -Id <id> -Execute'' ; .\Restore.ps1"')
    dism.exe /Unmount-Image /MountDir:$mount /Commit
    if ($LASTEXITCODE -ne 0) { throw 'Commit failed.' }
    $committed = $true
}
finally {
    if (-not $committed) { dism.exe /Unmount-Image /MountDir:$mount /Discard | Out-Null }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Copy-Item $wim (Join-Path $OutDir 'boot.wim')
Copy-Item (Join-Path $WorkDir 'media\boot\boot.sdi') (Join-Path $OutDir 'boot.sdi')
Write-Host "Built $OutDir\boot.wim and boot.sdi. Verify by booting it in a VM before using Install-BootEntry.ps1."
