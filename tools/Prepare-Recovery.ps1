<#
.SYNOPSIS
  Sets up the whole recovery environment in one go: wimlib, the Windows ADK, the recovery WinPE and the boot menu entry.
.DESCRIPTION
  Needs administrator rights and, unless the files are supplied with -WimlibZip / -AdkSetup / -WinPeSetup, an internet connection.
  Steps (each announced as "RN_STEP n/5 <name>" so a front end can show progress):
    1 wimlib       download (pinned URL and SHA-256) and unpack wimlib-imagex.exe into <ToolsDirectory>\bin when it is missing
    2 adk          install the Windows ADK Deployment Tools and the Windows PE add-on from Microsoft when they are missing
    3 build        Build-WinPE.ps1 -> boot.wim + boot.sdi
    4 bootentry    Install-BootEntry.ps1 (replaces an entry from an earlier run); the default Windows entry is not changed
    5 done
  The ADK and wimlib are downloaded from their publishers on the user's request; nothing of them is redistributed with this tool.
.EXAMPLE
  .\Prepare-Recovery.ps1 -Root D:\RestoreNest -Language zh
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('zh', 'en')][string]$Language = 'en',
    [string]$ToolsDirectory,   # default: the folder of this script (set below; $PSScriptRoot can be empty in a parameter default)
    [string]$WimlibZip, [string]$AdkSetup, [string]$WinPeSetup   # local copies instead of downloads (offline use, tests)
)
$ErrorActionPreference = 'Stop'
if (-not $ToolsDirectory) { $ToolsDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path }
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')
. (Join-Path $PSScriptRoot 'RestorePlan.Common.ps1')
. (Join-Path $PSScriptRoot 'RestoreSetup.Common.ps1')

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required.' }
if ($Root -notmatch '\A[A-Za-z]:[\\/]') { throw 'Root must be a local folder such as D:\RestoreNest.' }
if ($Root.Substring(0, 1) -ieq $env:SystemDrive.TrimEnd(':')) { throw 'The recovery files cannot live on the Windows partition.' }
if ($Root.TrimEnd('\').Length -le 2) { $Root = Join-Path $Root 'RestoreNest' }
function Step($number, $name) { Write-Host "RN_STEP $number/5 $name" }
$work = Join-Path ([IO.Path]::GetTempPath()) 'rn-prepare-recovery'
New-Item -ItemType Directory -Force -Path $work | Out-Null

try {
    # 1. wimlib
    Step 1 'wimlib'
    $bin = Join-Path $ToolsDirectory 'bin'
    $wimlib = Join-Path $bin 'wimlib-imagex.exe'
    if ((Test-Path -LiteralPath $wimlib) -and (Test-Path -LiteralPath (Join-Path $bin 'libwim-15.dll'))) { Write-Host 'wimlib is already present.' }
    else {
        $zip = $WimlibZip
        if (-not $zip) { $zip = Join-Path $work 'wimlib.zip'; Write-Host "Downloading $script:RnWimlibUrl"; Save-RnDownload -Url $script:RnWimlibUrl -Destination $zip }
        Install-RnWimlib -ZipPath $zip -BinDirectory $bin
        Write-Host 'wimlib installed.'
    }

    # 2. Windows ADK + Windows PE add-on
    Step 2 'adk'
    if (Test-RnAdkInstalled) { Write-Host 'The Windows ADK and the Windows PE add-on are already installed.' }
    else {
        if (-not $AdkSetup) { $AdkSetup = Join-Path $work 'adksetup.exe'; Write-Host 'Downloading the Windows ADK installer'; Save-RnDownload -Url $script:RnAdkUrl -Destination $AdkSetup }
        if (-not $WinPeSetup) { $WinPeSetup = Join-Path $work 'adkwinpesetup.exe'; Write-Host 'Downloading the Windows PE add-on installer'; Save-RnDownload -Url $script:RnWinPeAddonUrl -Destination $WinPeSetup }
        Write-Host 'Installing the Windows ADK Deployment Tools (this downloads more files and takes a while) ...'
        Install-RnAdkComponent -Installer $AdkSetup -Feature 'OptionId.DeploymentTools'
        Write-Host 'Installing the Windows PE add-on ...'
        Install-RnAdkComponent -Installer $WinPeSetup -Feature 'OptionId.WindowsPreinstallationEnvironment'
        if (-not (Test-RnAdkInstalled)) { throw 'The Windows ADK installation finished but the Windows PE files are not where they are expected.' }
    }

    # 3. the recovery image
    Step 3 'build'
    $built = Join-Path $work 'winpe-out'
    Remove-Item -LiteralPath $built -Recurse -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'Build-WinPE.ps1') -WimlibPath $wimlib -OutDir $built
    foreach ($f in 'boot.wim', 'boot.sdi') { if (-not (Test-Path -LiteralPath (Join-Path $built $f))) { throw "Build-WinPE.ps1 did not produce $f." } }

    # 4. boot menu entry (an older one from a previous run is replaced)
    Step 4 'bootentry'
    $installer = Join-Path $PSScriptRoot 'Install-BootEntry.ps1'
    $stateFile = Join-Path $Root 'boot\bootentry.json'
    if (Test-Path -LiteralPath $stateFile) {
        # If the old entry was deleted by someone else, only the stale record is left to clear.
        try { & $installer -Root $Root -Remove }
        catch { Write-Warning "The earlier boot entry could not be removed ($($_.Exception.Message)); clearing its record and continuing."; Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue }
    }
    & $installer -Root $Root -BootWim (Join-Path $built 'boot.wim') -BootSdi (Join-Path $built 'boot.sdi') -Language $Language

    Step 5 'done'
    Write-Host 'The recovery environment is ready.'
}
finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
