# Host-safe tests: wimlib is replaced by a stub, so no snapshot is taken and nothing is captured from the live system.
$ErrorActionPreference = 'Stop'
function Check($ok, $name) { if (-not $ok) { throw "FAILED: $name" } }
function Throws($block, $name) { try { & $block; throw 'no error' } catch { if ($_.Exception.Message -eq 'no error') { throw "FAILED (accepted): $name" } } }

$tools = Join-Path $PSScriptRoot '..\tools'
$work = Join-Path $PSScriptRoot ('..\.tmp-rp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $work
$work = (Resolve-Path $work).Path
$stub = Join-Path $work 'wimlib-stub.cmd'
Set-Content -LiteralPath $stub -Encoding ascii -Value @(
    '@echo off',
    'if "%RN_STUB_FAIL%"=="1" exit /b 7',
    'if "%1"=="capture" ( echo fake-wim-%~4 > "%~3" & exit /b 0 )',
    'if "%1"=="verify" exit /b 0',
    'exit /b 9')
try {
    . (Join-Path $tools 'RestorePoint.Common.ps1')
    $dest = $work
    Check ((Get-Volume -DriveLetter $dest.Substring(0, 1)).FileSystem -eq 'NTFS') 'test drive must be NTFS'

    # Destination rules
    Throws { Resolve-RnDestination -Destination 'C:\Backups' -SystemDrive 'C' } 'system partition rejected'
    Throws { Resolve-RnDestination -Destination '\\server\share' -SystemDrive 'C' } 'network rejected'
    Throws { Resolve-RnDestination -Destination 'relative\path' -SystemDrive 'C' } 'relative rejected'
    Throws { Resolve-RnDestination -Destination $dest -SystemDrive 'C' -RequiredBytes ([long]::MaxValue) } 'insufficient space rejected'
    Check ((Resolve-RnDestination -Destination ($dest.Substring(0, 3)) -SystemDrive 'C') -eq ($dest.Substring(0, 3) + 'RestoreNest')) 'drive root gets RestoreNest folder'
    Check ((Resolve-RnDestination -Destination $dest -SystemDrive 'C') -eq $dest) 'explicit folder kept'

    # Capture arguments and ids
    $argsOut = Get-RnWimlibCaptureArguments -SourceDrive 'C' -WimPath 'D:\x\system.wim' -ImageName 'n' -ConfigPath 'D:\x\c.ini'
    Check (($argsOut -join ' ') -eq 'capture C:\ D:\x\system.wim n --snapshot --compress=LZX --check --config=D:\x\c.ini') 'wimlib arguments'
    Check ((New-RnRestorePointId -Now ([datetime]'2026-10-31 15:30:05')) -eq '20261031-153005') 'id format'
    Check (-not (Test-RnRestorePointId '..\evil')) 'id rejects traversal'

    # Dry run changes nothing
    $plan = & (Join-Path $tools 'New-RestorePoint.ps1') -Destination $dest -WimlibPath $stub -DryRun
    Check ($plan.Id -match '\A\d{8}-\d{6}\z' -and -not (Test-Path (Join-Path $dest $plan.Id))) 'dry run creates nothing'

    # Real flow with the stub; two restore points must coexist
    $first = & (Join-Path $tools 'New-RestorePoint.ps1') -Destination $dest -Name 'first' -WimlibPath $stub -SkipAdminCheck
    Start-Sleep -Seconds 2
    $second = & (Join-Path $tools 'New-RestorePoint.ps1') -Destination $dest -Name 'second' -WimlibPath $stub -SkipAdminCheck
    Check ($first.Id -ne $second.Id) 'distinct ids'
    $list = @(& (Join-Path $tools 'Get-RestorePoint.ps1') -Destination $dest -Verify -WimlibPath $stub)
    Check ($list.Count -eq 2) 'two restore points listed'
    Check (@($list | Where-Object Status -ne 'ok').Count -eq 0) 'both verify'
    Check (-not (Get-ChildItem $dest -Directory | Where-Object Name -like '*.partial')) 'no partial folders'
    Check (-not (Test-Path (Join-Path $first.Path 'capture.ini'))) 'temporary config removed'
    $meta = Read-RnMeta -Directory $first.Path
    Check ($meta.name -eq 'first' -and $meta.source.driveLetter -eq 'C' -and $meta.source.partitionGuid -and $meta.source.diskGuid) 'meta records source identity'

    # Corruption is caught
    Add-Content -LiteralPath (Join-Path $first.Path 'system.wim') -Value 'x'
    Throws { Test-RnRestorePoint -Directory $first.Path } 'tampered wim rejected'
    Check ((Test-RnRestorePoint -Directory $second.Path)) 'untouched point still ok'

    # Failed capture leaves nothing behind and does not disturb existing points
    $env:RN_STUB_FAIL = '1'
    Throws { & (Join-Path $tools 'New-RestorePoint.ps1') -Destination $dest -WimlibPath $stub -SkipAdminCheck } 'failed capture reported'
    Remove-Item Env:\RN_STUB_FAIL
    Check (@(Get-ChildItem $dest -Directory).Count -eq 2) 'failed capture leaves no folder'

    # Stale partial captures are reclaimed; a fresh one (capture in progress) and real restore points are left alone
    $staleDir = Join-Path $dest '20250101-000000.partial'; $freshDir = Join-Path $dest '20990101-000000.partial'
    $null = New-Item -ItemType Directory $staleDir, $freshDir
    Set-Content (Join-Path $staleDir 'system.wim') 'x'; Set-Content (Join-Path $freshDir 'system.wim') 'x'
    (Get-Item $staleDir).LastWriteTime = (Get-Date).AddHours(-5); (Get-Item (Join-Path $staleDir 'system.wim')).LastWriteTime = (Get-Date).AddHours(-5)
    $null = Remove-RnStalePartials -Root $dest
    Check (-not (Test-Path $staleDir)) 'stale partial removed'
    Check (Test-Path $freshDir) 'fresh partial kept'
    Check (@(Get-RnRestorePoints -Root $dest -WarningAction SilentlyContinue).Count -eq 2) 'restore points untouched by cleanup'
    Remove-Item $freshDir -Recurse -Force

    # Malformed meta is skipped, not trusted
    $bad = Join-Path $dest '20260101-000000'
    $null = New-Item -ItemType Directory $bad
    Set-Content (Join-Path $bad 'meta.json') '{"schema":1,"id":"20260101-000000","wim":{"file":"..\\evil.wim","sha256":"zz"}}'
    Check (@(Get-RnRestorePoints -Root $dest -WarningAction SilentlyContinue).Count -eq 2) 'invalid meta skipped'
    Write-Host 'Restore point checks passed.'
}
finally {
    Remove-Item Env:\RN_STUB_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
