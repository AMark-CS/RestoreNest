# Restore planning and boot-entry helpers. Dot-source after RestorePoint.Common.ps1. Pure functions are unit-tested.
Set-StrictMode -Version 2.0

$script:EspTypeGuid = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'

function ConvertTo-RnGuid { param([string]$Value) $Value.Trim('{', '}').ToLowerInvariant() }

# Partitions: objects with DiskGuid, Guid, GptType, DriveLetter, Size, FileSystem. Throws when the restore would be unsafe.
function Resolve-RnRestoreTarget {
    param([Parameter(Mandatory)]$Meta, [Parameter(Mandatory)]$Partitions, [Parameter(Mandatory)][string]$BackupPartitionGuid)
    $wantPart = ConvertTo-RnGuid $Meta.source.partitionGuid
    $wantDisk = ConvertTo-RnGuid $Meta.source.diskGuid
    $found = @($Partitions | Where-Object { (ConvertTo-RnGuid $_.Guid) -eq $wantPart })
    if ($found.Count -ne 1) { throw "Expected exactly one partition with GUID $wantPart, found $($found.Count)." }
    $target = $found[0]
    if ((ConvertTo-RnGuid $target.DiskGuid) -ne $wantDisk) { throw 'The partition is on a different disk than the restore point was taken from.' }
    if ((ConvertTo-RnGuid $target.Guid) -eq (ConvertTo-RnGuid $BackupPartitionGuid)) { throw 'Refusing to restore onto the partition that holds the backup.' }
    if ($target.FileSystem -ne 'NTFS') { throw "Target filesystem is '$($target.FileSystem)', not NTFS (locked by BitLocker, or damaged?). Unlock it first." }
    $esp = @($Partitions | Where-Object { (ConvertTo-RnGuid $_.DiskGuid) -eq $wantDisk -and $_.GptType -eq $script:EspTypeGuid })
    if ($esp.Count -ne 1) { throw "Expected exactly one EFI system partition on the target disk, found $($esp.Count)." }
    [pscustomobject]@{ Target = $target; Esp = $esp[0] }
}

function Get-RnPartitionList {
    $list = @()
    foreach ($disk in @(Get-Disk | Where-Object PartitionStyle -eq 'GPT')) {
        foreach ($p in @(Get-Partition -DiskNumber $disk.Number)) {
            $fs = ''
            $v = $p | Get-Volume -ErrorAction SilentlyContinue
            if ($v) { $fs = [string]$v.FileSystem }
            $list += [pscustomobject]@{ DiskNumber = $disk.Number; DiskGuid = [string]$disk.Guid; PartitionNumber = $p.PartitionNumber; Guid = [string]$p.Guid; GptType = ([string]$p.GptType).ToLowerInvariant(); DriveLetter = [string]$p.DriveLetter; Size = [long]$p.Size; FileSystem = $fs }
        }
    }
    $list
}

function Get-RnWimlibApplyArguments { param([string]$WimPath, [string]$TargetRoot) @('apply', $WimPath, '1', ($TargetRoot.TrimEnd('\') + '\')) }

function Get-RnBootEntryPlan {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][ValidatePattern('\A[A-Za-z]\z')][string]$Letter, [string]$Description = 'RestoreNest Recovery')
    $dir = '\' + $Root.Substring(2).Trim('\') + '\boot'
    [pscustomobject]@{
        SdiPath     = "$dir\boot.sdi"
        Device      = "ramdisk=[$($Letter.ToUpperInvariant()):]$dir\boot.wim,{ramdiskoptions}"
        Description = $Description
        Letter      = $Letter.ToUpperInvariant()
    }
}
