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

# BitLocker recovery passwords are 8 groups of 6 digits. Anything else is rejected before it reaches manage-bde.
function Test-RnRecoveryPassword { param([string]$Value) [bool]($Value -match '\A\d{6}(-\d{6}){7}\z') }

# True when `manage-bde -status <drive>:` output says the volume is locked (WinPE ships the English tool).
function Test-RnBitLockerLocked { param([string]$StatusText) [bool]($StatusText -match 'Lock Status:\s+Locked') }

# The partition a restore point was taken from, when it shows no file system because BitLocker has it locked (as it does in
# WinPE). Returns an object with its DriveLetter (assigned if it had none) or $null when it is readable or cannot be found.
function Find-RnLockedTarget {
    param([Parameter(Mandatory)]$Meta, [Parameter(Mandatory)]$Partitions)
    $want = ConvertTo-RnGuid $Meta.source.partitionGuid
    $candidate = @($Partitions | Where-Object { (ConvertTo-RnGuid $_.Guid) -eq $want -and $_.FileSystem -ne 'NTFS' })
    if ($candidate.Count -ne 1) { return $null }
    $lp = Get-Partition -DiskNumber $candidate[0].DiskNumber -PartitionNumber $candidate[0].PartitionNumber
    if (-not $lp.DriveLetter) { $lp | Add-PartitionAccessPath -AssignDriveLetter; $lp = Get-Partition -DiskNumber $candidate[0].DiskNumber -PartitionNumber $candidate[0].PartitionNumber }
    $text = ''
    try { $text = (& manage-bde.exe -status "$($lp.DriveLetter):" 2>$null | Out-String) } catch { Write-Warning 'manage-bde is not available; the partition cannot be unlocked here.' }
    if (Test-RnBitLockerLocked $text) { return [pscustomobject]@{ DriveLetter = [string]$lp.DriveLetter } }
    $null
}

# 48-digit recovery passwords in `manage-bde -protectors -get` output; the format is the same in every display language.
function Get-RnRecoveryPasswords {
    param([string]$Text)
    @([regex]::Matches($Text, '(?<!\d)\d{6}(?:-\d{6}){7}(?!\d)') | ForEach-Object Value | Select-Object -Unique)
}

# Whether BitLocker protects the drive (read from WMI, so it does not depend on the display language) and its recovery passwords.
function Get-RnBitLockerInfo {
    param([string]$Drive = $env:SystemDrive)
    $letter = $Drive.TrimEnd('\').TrimEnd(':') + ':'
    $on = $false
    try {
        $volume = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftVolumeEncryption' -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$letter'" -ErrorAction Stop
        $on = ($null -ne $volume -and [int]$volume.ProtectionStatus -eq 1)
    }
    catch { $on = $false }
    $keys = @()
    if ($on) { $keys = @(Get-RnRecoveryPasswords -Text ((& manage-bde.exe -protectors -get $letter -Type RecoveryPassword 2>$null) | Out-String)) }
    [pscustomobject]@{ protectionOn = $on; recoveryPasswords = $keys }
}

# Unlocks a BitLocker volume with its 48-digit recovery password; throws (nothing has been written yet) when it does not work.
function Unlock-RnVolume {
    param([Parameter(Mandatory)][ValidatePattern('\A[A-Za-z]\z')][string]$DriveLetter, [string]$RecoveryPassword)
    if (-not (Test-RnRecoveryPassword $RecoveryPassword)) { throw 'No valid BitLocker recovery password was provided; nothing was written.' }
    & manage-bde.exe -unlock "$($DriveLetter):" -RecoveryPassword $RecoveryPassword | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'The BitLocker recovery password did not unlock the partition; nothing was written.' }
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

# Command line for a restore run started from the graphical recovery screen. Start-Process joins an argument array with spaces and
# adds no quotes, so "RESTORE 2026..." would reach Restore.ps1 as two words (the phrase "RESTORE" plus a stray argument) and the
# confirmation could never match. Every value that can contain a space is wrapped in double quotes here.
function Get-RnRestoreProcessArguments {
    param([Parameter(Mandatory)][string]$ScriptPath, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Id,
        [string]$WimlibPath, [string]$RecoveryPassword)
    $quote = { param($text) '"' + ($text -replace '"', '') + '"' }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (& $quote $ScriptPath), '-Root', (& $quote $Root), '-Id', (& $quote $Id),
        '-Execute', '-ConfirmText', (& $quote "RESTORE $Id"))
    if ($WimlibPath) { $arguments += @('-WimlibPath', (& $quote $WimlibPath)) }
    if ($RecoveryPassword) { $arguments += @('-RecoveryPassword', (& $quote $RecoveryPassword)) }
    $arguments
}

# Start-Process -PassThru without -Wait returns a Process whose ExitCode is $null after it exited, unless its handle was touched
# while it ran. The recovery screen judged the finished restore by ExitCode, saw $null and showed "restore did not complete" for a
# restore that had worked. Starting through this wrapper caches the handle, so ExitCode is real.
function Start-RnProcess {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @(), [string]$StdOut, [string]$StdErr)
    $splat = @{ FilePath = $FilePath; PassThru = $true; WindowStyle = 'Hidden' }
    if ($ArgumentList.Count -gt 0) { $splat.ArgumentList = $ArgumentList }
    if ($StdOut) { $splat.RedirectStandardOutput = $StdOut }
    if ($StdErr) { $splat.RedirectStandardError = $StdErr }
    $process = Start-Process @splat
    $null = $process.Handle
    $process
}
