param([Parameter(Mandatory=$true)][string]$TaskPath)
$ErrorActionPreference = 'Stop'
# Read-only preflight; this script never invokes a recovery or changes disk state.
$file = Get-Item -LiteralPath $TaskPath
if ($file.Length -gt 16384) { throw 'Recovery task exceeds the size limit.' }
$task = Get-Content -LiteralPath $TaskPath -Raw | ConvertFrom-Json
if ($task.Schema -ne 1) { throw 'Unsupported task schema.' }
$versionTime = [datetime]::MinValue
if (-not [datetime]::TryParseExact($task.Version, 'MM/dd/yyyy-HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$versionTime)) { throw 'Invalid backup version.' }
if ($task.Machine -notmatch '\A[A-Za-z0-9][A-Za-z0-9-]{0,62}\z') { throw 'Invalid computer name.' }
function Find-Volume($identity) {
    $diskGuid = [guid]$identity.Disk
    $partitionGuid = [guid]$identity.Partition
    if ($diskGuid -eq [guid]::Empty -or $partitionGuid -eq [guid]::Empty) { throw 'Empty disk identity.' }
    $disks = @(Get-Disk | Where-Object { $_.PartitionStyle -eq 'GPT' -and [guid]$_.Guid -eq $diskGuid })
    if ($disks.Count -ne 1) { throw 'Disk identity is missing or ambiguous.' }
    $partitions = @($disks[0] | Get-Partition | Where-Object { [guid]$_.Guid -eq $partitionGuid })
    if ($partitions.Count -ne 1) { throw 'Partition identity is missing or ambiguous.' }
    return $partitions[0]
}
$backup = Find-Volume $task.Backup
$windows = Find-Volume $task.Windows
if ($backup.DiskNumber -eq $windows.DiskNumber) { throw 'Separate backup and system disks are required.' }
if (-not $backup.DriveLetter) { throw 'Backup volume has no drive letter; automatic assignment is not supported.' }
$backupFolder = Join-Path ($backup.DriveLetter.ToString() + ':\') ('WindowsImageBackup\' + $task.Machine)
if (-not (Test-Path -LiteralPath $backupFolder -PathType Container)) { throw 'Machine backup directory not found.' }
[pscustomobject]@{
    Version = $task.Version
    Machine = $task.Machine
    BackupDisk = $backup.DiskNumber
    BackupPartition = $backup.PartitionNumber
    BackupDrive = $backup.DriveLetter
    WindowsDisk = $windows.DiskNumber
    WindowsPartition = $windows.PartitionNumber
    Status = 'Identity checks passed; backup contents, recovery layout and bootability are NOT verified. No recovery was executed.'
}
