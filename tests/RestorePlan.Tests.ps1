# Pure-logic tests for restore planning, boot entry dry run and a real wimlib capture/apply round trip on scratch folders.
$ErrorActionPreference = 'Stop'
function Check($ok, $name) { if (-not $ok) { throw "FAILED: $name" } }
function Throws($block, $name) { try { & $block; throw 'no error' } catch { if ($_.Exception.Message -eq 'no error') { throw "FAILED (accepted): $name" } } }
$tools = Join-Path $PSScriptRoot '..\tools'
. (Join-Path $tools 'RestorePoint.Common.ps1')
. (Join-Path $tools 'RestorePlan.Common.ps1')

function P($disk, $guid, $type, $fs, $letter = '') { [pscustomobject]@{ DiskNumber = 0; PartitionNumber = 1; DiskGuid = $disk; Guid = $guid; GptType = $type; DriveLetter = $letter; Size = 40GB; FileSystem = $fs } }
$esp = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'; $basic = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'
$disk = '{11111111-1111-1111-1111-111111111111}'
$meta = [pscustomobject]@{ source = [pscustomobject]@{ diskGuid = $disk; partitionGuid = '{AAAAAAAA-0000-0000-0000-000000000001}' } }
$parts = @((P $disk '{aaaaaaaa-0000-0000-0000-000000000000}' $esp 'FAT32'), (P $disk '{aaaaaaaa-0000-0000-0000-000000000001}' $basic 'NTFS' 'C'), (P $disk '{aaaaaaaa-0000-0000-0000-000000000002}' $basic 'NTFS' 'D'))

$r = Resolve-RnRestoreTarget -Meta $meta -Partitions $parts -BackupPartitionGuid '{aaaaaaaa-0000-0000-0000-000000000002}'
Check ($r.Target.DriveLetter -eq 'C' -and $r.Esp.FileSystem -eq 'FAT32') 'same-disk D: backup resolves C: target and ESP'
Throws { Resolve-RnRestoreTarget -Meta $meta -Partitions $parts -BackupPartitionGuid '{aaaaaaaa-0000-0000-0000-000000000001}' } 'backup on target refused'
Throws { Resolve-RnRestoreTarget -Meta $meta -Partitions @($parts[0], $parts[2]) -BackupPartitionGuid 'x' } 'missing target refused'
$wrongDisk = $meta.PSObject.Copy(); $wrongDisk.source = [pscustomobject]@{ diskGuid = '{22222222-2222-2222-2222-222222222222}'; partitionGuid = $meta.source.partitionGuid }
Throws { Resolve-RnRestoreTarget -Meta $wrongDisk -Partitions $parts -BackupPartitionGuid 'x' } 'different disk refused'
$locked = @($parts[0], (P $disk '{aaaaaaaa-0000-0000-0000-000000000001}' $basic '' 'C'), $parts[2])
Throws { Resolve-RnRestoreTarget -Meta $meta -Partitions $locked -BackupPartitionGuid '{aaaaaaaa-0000-0000-0000-000000000002}' } 'unreadable (BitLocker) target refused'
Throws { Resolve-RnRestoreTarget -Meta $meta -Partitions @($parts[1], $parts[2]) -BackupPartitionGuid '{aaaaaaaa-0000-0000-0000-000000000002}' } 'no ESP refused'

$plan = Get-RnBootEntryPlan -Root 'D:\RestoreNest' -Letter 'd'
Check ($plan.Device -eq 'ramdisk=[D:]\RestoreNest\boot\boot.wim,{ramdiskoptions}' -and $plan.SdiPath -eq '\RestoreNest\boot\boot.sdi') 'boot entry device strings'
Check ((Get-RnWimlibApplyArguments -WimPath 'D:\a\system.wim' -TargetRoot 'C:') -join ' ' -eq 'apply D:\a\system.wim 1 C:\') 'apply arguments'

# Boot entry dry run: prints commands, touches nothing
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rn-be-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory $tmp
try {
    $wimFile = Join-Path $tmp 'boot.wim'; $sdiFile = Join-Path $tmp 'boot.sdi'
    Set-Content $wimFile x; Set-Content $sdiFile x
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'Install-BootEntry.ps1') -Root 'E:\RestoreNest' -BootWim $wimFile -BootSdi $sdiFile -DryRun 2>&1 | Out-String
    Check ($out -match 'bcdedit /create \{ramdiskoptions\}' -and $out -match 'winpe yes' -and $out -match 'displayorder' -and $out -notmatch '/default') 'dry run prints entry commands without changing default'
    Check (-not (Test-Path 'E:\RestoreNest\boot')) 'dry run wrote nothing'
    $ErrorActionPreference = 'Continue'
    $sys = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tools 'Install-BootEntry.ps1') -Root 'C:\RestoreNest' -BootWim $wimFile -BootSdi $sdiFile -DryRun 2>&1 | Out-String
    $ErrorActionPreference = 'Stop'
    Check ($sys -match 'must not live on the Windows partition') 'system-partition location refused'

    # Real wimlib round trip on scratch folders (no VSS, no live system)
    $wimlib = @('E:\Code\.cache\restorenest-vm\wimlib\wimlib-imagex.exe', (Join-Path $tools 'bin\wimlib-imagex.exe')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($wimlib) {
        $src = Join-Path $tmp 'src'; $dst = Join-Path $tmp 'dst'
        $null = New-Item -ItemType Directory "$src\sub", $dst
        [IO.File]::WriteAllBytes("$src\sub\a.bin", (1..200000 | ForEach-Object { [byte]($_ % 251) }))
        Set-Content "$src\b.txt" 'hello'
        $cfg = Join-Path $tmp 'c.ini'; Set-Content $cfg (Get-RnCaptureConfig) -Encoding Unicode
        $capture = Get-RnWimlibCaptureArguments -SourceDrive 'C' -WimPath "$tmp\t.wim" -ImageName 't' -ConfigPath $cfg
        $capture[1] = $src; $capture = $capture | Where-Object { $_ -ne '--snapshot' }
        & $wimlib @capture | Out-Null
        Check ($LASTEXITCODE -eq 0) 'wimlib capture of scratch folder'
        & $wimlib @(Get-RnWimlibApplyArguments -WimPath "$tmp\t.wim" -TargetRoot $dst) | Out-Null
        Check ($LASTEXITCODE -eq 0) 'wimlib apply'
        $h1 = (Get-FileHash "$src\sub\a.bin").Hash; $h2 = (Get-FileHash "$dst\sub\a.bin").Hash
        Check ($h1 -eq $h2 -and (Get-Content "$dst\b.txt") -eq 'hello') 'round trip preserves content'
        & $wimlib verify "$tmp\t.wim" | Out-Null
        Check ($LASTEXITCODE -eq 0) 'wimlib verify'
        Write-Host 'wimlib round trip passed.'
    } else { Write-Host 'wimlib not found; round trip skipped.' }
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host 'Restore plan checks passed.'
