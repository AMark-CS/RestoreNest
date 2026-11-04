# Host-safe tests for scheduled restore points: settings, the Task Scheduler definition, retention and the scheduled run.
# wimlib is replaced by a stub, nothing is registered with Task Scheduler and nothing is captured from the live system.
$ErrorActionPreference = 'Stop'
function Check($ok, $name) { if (-not $ok) { throw "FAILED: $name" } }
function Throws($block, $name) { try { & $block; throw 'no error' } catch { if ($_.Exception.Message -eq 'no error') { throw "FAILED (accepted): $name" } } }

$tools = Join-Path $PSScriptRoot '..\tools'
$work = Join-Path $PSScriptRoot ('..\.tmp-rs-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $work
$work = (Resolve-Path $work).Path
$stub = Join-Path $work 'wimlib-stub.cmd'
Set-Content -LiteralPath $stub -Encoding ascii -Value @(
    '@echo off',
    'if "%RN_STUB_FAIL%"=="1" exit /b 7',
    'if "%1"=="capture" ( echo fake-wim-%~4 > "%~3" & exit /b 0 )',
    'if "%1"=="verify" exit /b 0',
    'exit /b 9')
$data = Join-Path $work 'data'
$store = Join-Path $work 'points'
$null = New-Item -ItemType Directory -Path $store
$env:RN_DATA = $data
try {
    . (Join-Path $tools 'RestorePoint.Common.ps1')
    . (Join-Path $tools 'RestoreSchedule.Common.ps1')

    # ---- settings: defaults, validation, file round trip
    $default = ConvertTo-RnScheduleSettings -Raw ([pscustomobject]@{})
    Check (-not $default.enabled -and $default.frequency -eq 'weekly' -and $default.time -eq '02:00' -and $default.keep -eq 3 -and $default.onlyOnAC) 'defaults'
    foreach ($bad in @{ frequency = 'hourly' }, @{ time = '25:00' }, @{ time = '2:00' }, @{ dayOfWeek = 'Funday' }, @{ dayOfMonth = 29 }, @{ keep = 0 }, @{ keep = 31 }, @{ enabled = $true }, @{ enabled = $true; destination = 'relative\path' }) {
        Throws { ConvertTo-RnScheduleSettings -Raw ([pscustomobject]$bad) } ('rejected: ' + (($bad.Keys | ForEach-Object { "$_=$($bad[$_])" }) -join ','))
    }
    foreach ($frequency in 'daily', 'every3days', 'weekly', 'biweekly', 'monthly') { Check ((ConvertTo-RnScheduleSettings -Raw ([pscustomobject]@{ frequency = $frequency })).frequency -eq $frequency) "frequency $frequency accepted" }
    Check ((Read-RnScheduleSettings).enabled -eq $false) 'missing settings file means switched off'
    $null = New-Item -ItemType Directory -Force -Path $data
    Set-Content -LiteralPath (Get-RnSchedulePath) -Encoding UTF8 -Value (@{ enabled = $true; frequency = 'biweekly'; time = '03:30'; dayOfWeek = 'Friday'; keep = 5; destination = 'D:\'; onlyOnAC = $false } | ConvertTo-Json)
    $read = Read-RnScheduleSettings
    Check ($read.enabled -and $read.frequency -eq 'biweekly' -and $read.time -eq '03:30' -and $read.dayOfWeek -eq 'Friday' -and $read.keep -eq 5 -and $read.destination -eq 'D:\' -and -not $read.onlyOnAC) 'settings file round trip'

    # ---- Task Scheduler definition
    $script = 'C:\Program Files\Rest&oreNest\tools\Invoke-ScheduledRestorePoint.ps1'
    function Get-Xml($overrides) {
        $base = @{ enabled = $true; destination = 'D:\'; time = '02:00' }
        foreach ($k in $overrides.Keys) { $base[$k] = $overrides[$k] }
        [xml](New-RnScheduleTaskXml -Settings (ConvertTo-RnScheduleSettings -Raw ([pscustomobject]$base)) -ScriptPath $script -Start ([datetime]'2026-01-01'))
    }
    $daily = Get-Xml @{ frequency = 'daily' }
    Check ($daily.Task.Triggers.CalendarTrigger.ScheduleByDay.DaysInterval -eq '1' -and $daily.Task.Triggers.CalendarTrigger.StartBoundary -eq '2026-01-01T02:00:00') 'daily trigger'
    Check ((Get-Xml @{ frequency = 'every3days' }).Task.Triggers.CalendarTrigger.ScheduleByDay.DaysInterval -eq '3') 'every three days trigger'
    $weekly = Get-Xml @{ frequency = 'weekly'; dayOfWeek = 'Wednesday'; time = '04:15' }
    Check ($weekly.Task.Triggers.CalendarTrigger.ScheduleByWeek.WeeksInterval -eq '1' -and $null -ne $weekly.Task.Triggers.CalendarTrigger.ScheduleByWeek.DaysOfWeek.Wednesday -and $weekly.Task.Triggers.CalendarTrigger.StartBoundary -eq '2026-01-01T04:15:00') 'weekly trigger'
    Check ((Get-Xml @{ frequency = 'biweekly'; dayOfWeek = 'Monday' }).Task.Triggers.CalendarTrigger.ScheduleByWeek.WeeksInterval -eq '2') 'every two weeks trigger'
    $monthly = Get-Xml @{ frequency = 'monthly'; dayOfMonth = 15 }
    Check ($monthly.Task.Triggers.CalendarTrigger.ScheduleByMonth.DaysOfMonth.Day -eq '15' -and $null -ne $monthly.Task.Triggers.CalendarTrigger.ScheduleByMonth.Months.December) 'monthly trigger'
    Check ($daily.Task.Principals.Principal.UserId -eq 'S-1-5-18' -and $daily.Task.Principals.Principal.RunLevel -eq 'HighestAvailable') 'runs as SYSTEM with highest rights'
    # Task Scheduler rejects <LogonType>ServiceAccount</LogonType> in XML (0x80041318). The logon type of a SYSTEM task comes from
    # registering it with -User SYSTEM / /RU SYSTEM instead; the VM test checks the result.
    Check ($null -eq $daily.Task.Principals.Principal.PSObject.Properties['LogonType']) 'the XML leaves the logon type to the registration'
    Check ($daily.Task.Settings.StartWhenAvailable -eq 'true' -and $daily.Task.Settings.MultipleInstancesPolicy -eq 'IgnoreNew') 'catches up after a missed time, never two copies'
    Check ($daily.Task.Settings.DisallowStartIfOnBatteries -eq 'true' -and (Get-Xml @{ frequency = 'daily'; onlyOnAC = $false }).Task.Settings.DisallowStartIfOnBatteries -eq 'false') 'battery option'
    Check ($daily.Task.Actions.Exec.Arguments -like '*"C:\Program Files\Rest&oreNest\tools\Invoke-ScheduledRestorePoint.ps1"*') 'script path is quoted and XML-escaped'

    # ---- unattended scripts must not compute anything from $PSScriptRoot in their parameter block (it was empty when they ran as SYSTEM)
    foreach ($name in 'Invoke-ScheduledRestorePoint.ps1', 'New-RestorePoint.ps1') {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $tools $name), [ref]$null, [ref]$null)
        $defaults = @($ast.ParamBlock.Parameters | Where-Object { $_.DefaultValue } | ForEach-Object { $_.DefaultValue.Extent.Text })
        Check (-not ($defaults -match 'PSScriptRoot')) "$name does not use `$PSScriptRoot in a parameter default"
    }

    # ---- retention
    $fake = @('20260101-000000', '20260102-000000', '20260103-000000', '20260104-000000') | ForEach-Object { [pscustomobject]@{ Id = $_ } }
    Check ((@(Get-RnPointsToPrune -Points $fake -Keep 2) | ForEach-Object Id) -join ',' -eq '20260101-000000,20260102-000000') 'keep 2 prunes the two oldest'
    Check (@(Get-RnPointsToPrune -Points $fake -Keep 10).Count -eq 0) 'nothing to prune below the limit'
    Check (@(Get-RnPointsToPrune -Points $fake -Keep 0).Count -eq 3) 'at least one point is always kept'
    Check (@(Get-RnPointsToPrune -Points @() -Keep 3).Count -eq 0) 'empty list'
    Throws { Remove-RnRestorePoint -Point ([pscustomobject]@{ Id = '..\evil'; Path = $work }) -Root $store } 'bad id never deleted'
    Throws { Remove-RnRestorePoint -Point ([pscustomobject]@{ Id = '20260101-000000'; Path = (Join-Path $work 'other\20260101-000000') }) -Root $store } 'folder outside the root never deleted'
    Check ((Get-RnRequiredBytes -SystemDrive 'C') -gt 0) 'required space is computed'

    # ---- the scheduled run
    function Save-Settings($overrides) {
        $base = @{ enabled = $true; frequency = 'daily'; time = '02:00'; keep = 2; destination = $store; onlyOnAC = $true }
        foreach ($k in $overrides.Keys) { $base[$k] = $overrides[$k] }
        Set-Content -LiteralPath (Get-RnSchedulePath) -Encoding UTF8 -Value ($base | ConvertTo-Json)
    }
    function Get-Status { Get-Content -LiteralPath (Get-RnScheduleStatusPath) -Raw -Encoding UTF8 | ConvertFrom-Json }
    function Invoke-Run($extra = @{}) { & (Join-Path $tools 'Invoke-ScheduledRestorePoint.ps1') -WimlibPath $stub -SkipAdminCheck @extra | Out-Null }

    Save-Settings @{ enabled = $false }
    Invoke-Run
    Check ((Get-Status).code -eq 'disabled' -and @(Get-RnRestorePoints -Root $store).Count -eq 0) 'switched off: nothing is created'

    Save-Settings @{}
    1..3 | ForEach-Object { Invoke-Run; Start-Sleep -Seconds 2 }
    $kept = @(Get-RnRestorePoints -Root $store)
    Check ($kept.Count -eq 2) 'three runs with keep=2 leave two points'
    Check ((Get-Status).code -eq 'ok' -and (Get-Status).pointCount -eq 2 -and (Get-Status).lastSuccessUtc) 'status records the success'
    $ids = @($kept | ForEach-Object Id)

    Save-Settings @{ keep = 1 }
    Start-Sleep -Seconds 2
    Invoke-Run
    Check (@(Get-RnRestorePoints -Root $store).Count -eq 1 -and @(Get-RnRestorePoints -Root $store)[0].Id -notin $ids) 'keep=1 leaves only the newest point'

    Save-Settings @{ keep = 3 }
    Start-Sleep -Seconds 2; Invoke-Run; Start-Sleep -Seconds 2; Invoke-Run
    Check (@(Get-RnRestorePoints -Root $store).Count -eq 3) 'three points again'

    $env:RN_STUB_FAIL = '1'
    Start-Sleep -Seconds 2
    Invoke-Run
    Remove-Item Env:\RN_STUB_FAIL
    $statusAfterFailure = Get-Status
    Check ($statusAfterFailure.code -eq 'capture-failed' -and $LASTEXITCODE -eq 1) 'a failed capture is reported'
    Check (@(Get-RnRestorePoints -Root $store).Count -eq 3) 'a failed capture does not cost an old point'
    Check ($statusAfterFailure.lastSuccessUtc) 'the last success is remembered across a failure'

    Invoke-Run @{ RequiredBytesOverride = [long]::MaxValue / 2 }
    $afterNoSpace = @(Get-RnRestorePoints -Root $store)
    Check ((Get-Status).code -eq 'no-space' -and $LASTEXITCODE -eq 1) 'not enough space is reported'
    Check ($afterNoSpace.Count -eq 1) 'room is made by removing older points but the newest one stays'

    $busy = New-Item -ItemType Directory -Path (Join-Path $store '20990101-000000.partial')
    # A leftover .partial alone (killed capture) must NOT block; only together with a running wimlib process.
    Check (-not (Test-RnCaptureRunning -Root $store)) 'a leftover .partial folder without a wimlib process is not a running capture'
    $busy = New-Item -ItemType Directory -Force -Path (Join-Path $store '20990101-000000.partial')
    $fake = Join-Path $data 'wimlib-imagex.exe'
    Copy-Item (Join-Path $env:SystemRoot 'System32\ping.exe') $fake -Force
    $proc = Start-Process -FilePath $fake -ArgumentList '-n 30 127.0.0.1' -PassThru -WindowStyle Hidden
    try {
        Start-Sleep -Milliseconds 500
        Invoke-Run
        Check ((Get-Status).code -eq 'busy') 'a capture in progress means a skipped run'
    }
    finally { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 300 }
    Remove-Item $busy -Recurse -Force -ErrorAction SilentlyContinue

    $used = (Get-Volume | Select-Object -ExpandProperty DriveLetter) -join ''
    $free = [char[]](68..90) | Where-Object { $used -notmatch [string]$_ } | Select-Object -First 1
    Save-Settings @{ destination = "${free}:\" }
    Invoke-Run
    Check ((Get-Status).code -eq 'destination-unavailable') 'an unplugged destination drive is a skipped run'

    # ---- Set-RestoreSchedule without administrator rights: report and switch-off paths
    Save-Settings @{ enabled = $false }
    $report = (& (Join-Path $tools 'Set-RestoreSchedule.ps1') -Status) | ConvertFrom-Json
    Check ($report.registered -eq $false -and $report.last.code) 'status report is valid JSON'
    $applied = & (Join-Path $tools 'Set-RestoreSchedule.ps1') -Apply 6>&1 | Out-String
    Check ($applied -match 'off') 'applying a switched-off schedule needs no registration'
    Write-Host 'Restore schedule checks passed.'
}
finally {
    Remove-Item Env:\RN_STUB_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:\RN_DATA -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
