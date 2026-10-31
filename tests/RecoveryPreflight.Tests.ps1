$ErrorActionPreference = 'Stop'
$taskPath = Join-Path ([IO.Path]::GetTempPath()) ('rn-preflight-' + [guid]::NewGuid() + '.json')
$global:catalogVersion = '10/29/2026-09:53'
$global:backupDisk = [guid]'11111111-1111-1111-1111-111111111111'
$global:systemDisk = [guid]'22222222-2222-2222-2222-222222222222'
$global:backupPart = [guid]'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
$global:systemPart = [guid]'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
function Get-Disk {
    @([pscustomobject]@{ Guid=$global:backupDisk; PartitionStyle='GPT'; Number=1 }, [pscustomobject]@{ Guid=$global:systemDisk; PartitionStyle='GPT'; Number=2 })
}
function Get-Partition {
    [CmdletBinding()] param([Parameter(ValueFromPipeline=$true)]$InputObject)
    process {
        if ($InputObject.Number -eq 1) { [pscustomobject]@{ Guid=$global:backupPart; DiskNumber=1; PartitionNumber=1; DriveLetter='D' } }
        else { [pscustomobject]@{ Guid=$global:systemPart; DiskNumber=2; PartitionNumber=2; DriveLetter='C' } }
    }
}
function Test-Path { param($LiteralPath, $PathType) return $LiteralPath -eq 'D:\WindowsImageBackup\RN-VM' }
function wbadmin.exe {
    $global:LASTEXITCODE=0
    if ($args[1] -eq 'versions') { "Version identifier: $global:catalogVersion"; return }
    if ($args[1] -eq 'items' -and $args[2] -eq '-version:10/29/2026-09:53' -and $args[3] -eq '-backupTarget:D:' -and $args[4] -eq '-machine:RN-VM') {
        if ($global:failItems) { $global:LASTEXITCODE=5; return }
        'Volume C:'; return
    }
    throw 'Unexpected wbadmin arguments.'
}
try {
    @{ Schema=1; Version='10/29/2026-09:53'; Machine='RN-VM'; Backup=@{ Disk=$global:backupDisk; Partition=$global:backupPart }; Windows=@{ Disk=$global:systemDisk; Partition=$global:systemPart } } | ConvertTo-Json | Set-Content -LiteralPath $taskPath
    $check = Join-Path $PSScriptRoot '..\tools\Test-RecoveryTask.ps1'
    $result = & $check -TaskPath $taskPath
    if ($result.BackupDrive -ne 'D' -or $result.WindowsDisk -ne 2) { throw 'Did not resolve the expected partitions.' }
    if ($result.BackupItems.Count -ne 1 -or $result.BackupItems[0] -ne 'Volume C:') { throw 'Backup items were not returned.' }
    $global:failItems = $true
    try { & $check -TaskPath $taskPath; throw 'Failed items query was accepted.' }
    catch { if ($_.Exception.Message -ne 'Backup items query failed (exit code 5).') { throw } }
    $global:failItems = $false
    $global:catalogVersion = '10/30/2026-09:53'
    try { & $check -TaskPath $taskPath; throw 'Missing version was accepted.' }
    catch { if ($_.Exception.Message -ne 'Selected backup version was not found in the catalog.') { throw } }
    $global:catalogVersion = '10/29/2026-09:53'
    $global:systemDisk = $global:backupDisk
    try { & $check -TaskPath $taskPath; throw 'Ambiguous disk was accepted.' }
    catch { if ($_.Exception.Message -ne 'Disk identity is missing or ambiguous.') { throw } }
    'Recovery preflight tests passed.'
}
finally { Remove-Item -LiteralPath $taskPath -ErrorAction SilentlyContinue }
