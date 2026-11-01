# Shared helpers for RestoreNest restore points (VSS snapshot + WIM). Dot-source from the other scripts.
# A restore point is a directory <root>\<id>\ holding system.wim and meta.json; <root> defaults to <drive>:\RestoreNest.
Set-StrictMode -Version 2.0

$script:RnEngineVersion = '1'
$script:RnIdPattern = '\A\d{8}-\d{6}\z'

function Get-RnVolumeIdentity {
    param([Parameter(Mandatory)][ValidatePattern('\A[A-Za-z]\z')][string]$DriveLetter)
    $partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
    $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
    if ($disk.PartitionStyle -ne 'GPT') { throw 'Only GPT disks are supported.' }
    [pscustomobject]@{
        DriveLetter     = $DriveLetter.ToUpperInvariant()
        DiskNumber      = [int]$partition.DiskNumber
        DiskGuid        = [string]$disk.Guid
        PartitionNumber = [int]$partition.PartitionNumber
        PartitionGuid   = [string]$partition.Guid
    }
}

# Returns the backup root directory, or throws. Same physical disk as C: is allowed; the same partition is not.
function Resolve-RnDestination {
    param([Parameter(Mandatory)][string]$Destination, [Parameter(Mandatory)][string]$SystemDrive, [long]$RequiredBytes = 0)
    # Not IsPathFullyQualified: Windows PowerShell 5.1 (WinPE and the lab guest) runs on .NET Framework, which lacks it.
    if ($Destination -notmatch '\A[A-Za-z]:[\\/]') { throw 'Destination must be a local absolute path on a lettered drive.' }
    $full = [IO.Path]::GetFullPath($Destination)
    $letter = $full.Substring(0, 1)
    if ($full.Substring(1, 2) -ne ':\') { throw 'Destination must be on a lettered local drive.' }
    if ($letter -ieq $SystemDrive) { throw 'The backup cannot be stored on the Windows partition.' }
    $volume = Get-Volume -DriveLetter $letter -ErrorAction Stop
    if ($volume.DriveType -notin 'Fixed', 'Removable') { throw "Unsupported drive type: $($volume.DriveType)." }
    if ($volume.FileSystem -ne 'NTFS') { throw 'The destination must be an NTFS volume.' }
    if ($RequiredBytes -gt 0 -and $volume.SizeRemaining -lt $RequiredBytes) {
        throw ('Not enough free space: need about {0:N1} GiB, have {1:N1} GiB.' -f ($RequiredBytes / 1GB), ($volume.SizeRemaining / 1GB))
    }
    # A bare drive root gets the product folder; an explicit folder is used as given.
    if ($full.TrimEnd('\').Length -le 2) { return (Join-Path ($letter + ':\') 'RestoreNest') }
    return $full.TrimEnd('\')
}

function Get-RnCaptureConfig {
    # Volatile or regenerated files that must not be in an image.
    @'
[ExclusionList]
\$ntfs.log
\hiberfil.sys
\pagefile.sys
\swapfile.sys
\System Volume Information
\$Recycle.Bin
\RECYCLER
\Windows\CSC
'@
}

function Get-RnWimlibCaptureArguments {
    param([Parameter(Mandatory)][string]$SourceDrive, [Parameter(Mandatory)][string]$WimPath, [Parameter(Mandatory)][string]$ImageName, [Parameter(Mandatory)][string]$ConfigPath,
        [ValidateSet('LZX', 'XPRESS', 'LZMS', 'None')][string]$Compression = 'LZX', [switch]$NoSnapshot)
    $arguments = @('capture', ($SourceDrive.TrimEnd('\', ':') + ':\'), $WimPath, $ImageName)
    if (-not $NoSnapshot) { $arguments += '--snapshot' }
    $arguments + @("--compress=$Compression", '--check', "--config=$ConfigPath")
}

function New-RnRestorePointId { param([datetime]$Now = (Get-Date)) $Now.ToString('yyyyMMdd-HHmmss') }

function Test-RnRestorePointId { param([string]$Id) [bool]($Id -match $script:RnIdPattern) }

function Write-RnMeta {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Id, [string]$Name, [Parameter(Mandatory)]$Source, [Parameter(Mandatory)][string]$WimSha256, [Parameter(Mandatory)][long]$WimBytes)
    # The captured system's version, read from its kernel: the running OS may be WinPE.
    $kernel = Join-Path ($Source.DriveLetter + ':\') 'Windows\System32\ntoskrnl.exe'
    $windowsVersion = if (Test-Path -LiteralPath $kernel) { (Get-Item -LiteralPath $kernel).VersionInfo.ProductVersion } else { '' }
    $meta = [ordered]@{
        schema         = 1
        id             = $Id
        name           = $(if ($Name) { $Name } else { "RestoreNest $Id" })
        createdUtc     = (Get-Date).ToUniversalTime().ToString('o')
        machine        = $env:COMPUTERNAME
        windowsVersion = $windowsVersion
        source         = [ordered]@{ driveLetter = $Source.DriveLetter; diskGuid = $Source.DiskGuid; partitionGuid = $Source.PartitionGuid; partitionNumber = $Source.PartitionNumber }
        wim            = [ordered]@{ file = 'system.wim'; sha256 = $WimSha256; sizeBytes = $WimBytes }
        engine         = [ordered]@{ tool = 'wimlib'; version = $script:RnEngineVersion }
    }
    $path = Join-Path $Directory 'meta.json'
    ($meta | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $path -Encoding UTF8
    $path
}

function Read-RnMeta {
    param([Parameter(Mandatory)][string]$Directory)
    $path = Join-Path $Directory 'meta.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "meta.json missing in $Directory" }
    $meta = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($meta.schema -ne 1) { throw "Unsupported meta schema in $Directory" }
    if (-not (Test-RnRestorePointId $meta.id) -or $meta.id -ne (Split-Path $Directory -Leaf)) { throw "meta id does not match its folder in $Directory" }
    if ($meta.wim.file -ne 'system.wim' -or $meta.wim.sha256 -notmatch '\A[0-9A-Fa-f]{64}\z') { throw "Invalid wim entry in $Directory" }
    $meta
}

# Lists complete restore points; folders ending in .partial (interrupted captures) are never returned.
function Get-RnRestorePoints {
    param([Parameter(Mandatory)][string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return @() }
    $points = @()
    foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory | Where-Object { Test-RnRestorePointId $_.Name } | Sort-Object Name) {
        try { $points += [pscustomobject]@{ Id = $dir.Name; Path = $dir.FullName; Meta = (Read-RnMeta -Directory $dir.FullName) } }
        catch { Write-Warning "Skipping $($dir.FullName): $($_.Exception.Message)" }
    }
    @($points)
}

function Test-RnRestorePoint {
    param([Parameter(Mandatory)][string]$Directory, [string]$WimlibPath)
    $meta = Read-RnMeta -Directory $Directory
    $wim = Join-Path $Directory 'system.wim'
    if (-not (Test-Path -LiteralPath $wim -PathType Leaf)) { throw 'system.wim missing.' }
    $item = Get-Item -LiteralPath $wim
    if ($item.Length -ne [long]$meta.wim.sizeBytes) { throw 'system.wim size differs from meta.json.' }
    $hash = (Get-FileHash -LiteralPath $wim -Algorithm SHA256).Hash
    if ($hash -ne $meta.wim.sha256) { throw 'system.wim SHA-256 differs from meta.json.' }
    if ($WimlibPath) {
        & $WimlibPath verify $wim | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "wimlib verify failed (exit $LASTEXITCODE)." }
    }
    $true
}
