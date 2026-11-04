# Scheduled restore points: settings, the Task Scheduler definition and retention. Dot-source after RestorePoint.Common.ps1.
# Settings live in %ProgramData%\RestoreNest\schedule.json (only administrators can write there); the last run is recorded in
# schedule-status.json next to it. Set $env:RN_DATA to use another folder (tests).
Set-StrictMode -Version 2.0

$script:RnFrequencies = @('daily', 'every3days', 'weekly', 'biweekly', 'monthly')
$script:RnWeekDays = @('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')

function Get-RnDataDirectory { if ($env:RN_DATA) { $env:RN_DATA } else { Join-Path $env:ProgramData 'RestoreNest' } }
function Get-RnSchedulePath { Join-Path (Get-RnDataDirectory) 'schedule.json' }
function Get-RnScheduleStatusPath { Join-Path (Get-RnDataDirectory) 'schedule-status.json' }

function Get-RnProperty { param($Object, [string]$Name, $Default) if ($null -ne $Object -and $Object.PSObject.Properties[$Name] -and $null -ne $Object.$Name) { $Object.$Name } else { $Default } }

# Normalizes settings read from JSON (missing fields get defaults) and throws on a value that is not allowed.
function ConvertTo-RnScheduleSettings {
    param([Parameter(Mandatory)]$Raw)
    $frequency = [string](Get-RnProperty $Raw 'frequency' 'weekly')
    if ($frequency -notin $script:RnFrequencies) { throw "Unknown frequency '$frequency'." }
    $time = [string](Get-RnProperty $Raw 'time' '02:00')
    if ($time -notmatch '\A([01]\d|2[0-3]):[0-5]\d\z') { throw "Invalid time '$time' (use HH:mm)." }
    $day = [string](Get-RnProperty $Raw 'dayOfWeek' 'Sunday')
    if ($day -notin $script:RnWeekDays) { throw "Invalid day of week '$day'." }
    $dayOfMonth = [int](Get-RnProperty $Raw 'dayOfMonth' 1)
    if ($dayOfMonth -lt 1 -or $dayOfMonth -gt 28) { throw 'The day of the month must be 1 to 28.' }
    $keep = [int](Get-RnProperty $Raw 'keep' 3)
    if ($keep -lt 1 -or $keep -gt 30) { throw 'Keep must be 1 to 30 restore points.' }
    $enabled = [bool](Get-RnProperty $Raw 'enabled' $false)
    $destination = [string](Get-RnProperty $Raw 'destination' '')
    if ($enabled -and $destination -notmatch '\A[A-Za-z]:[\\/]') { throw 'Choose a local drive or folder (for example D:\) to store the restore points.' }
    [pscustomobject]@{
        enabled     = $enabled
        frequency   = $frequency
        time        = $time
        dayOfWeek   = $day
        dayOfMonth  = $dayOfMonth
        keep        = $keep
        destination = $destination
        onlyOnAC    = [bool](Get-RnProperty $Raw 'onlyOnAC' $true)
    }
}

function Read-RnScheduleSettings {
    param([string]$Path = (Get-RnSchedulePath))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return ConvertTo-RnScheduleSettings -Raw ([pscustomobject]@{}) }
    ConvertTo-RnScheduleSettings -Raw (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

# The Task Scheduler definition: runs as SYSTEM (VSS needs it), catches up when the PC was off at the scheduled time, optionally
# only on mains power, never starts a second copy.
function New-RnScheduleTaskXml {
    param([Parameter(Mandatory)]$Settings, [Parameter(Mandatory)][string]$ScriptPath, [datetime]$Start = (Get-Date).Date)
    $esc = { param($t) [Security.SecurityElement]::Escape($t) }
    $boundary = '{0}T{1}:00' -f $Start.ToString('yyyy-MM-dd'), $Settings.time
    $schedule = switch ($Settings.frequency) {
        'daily'      { '<ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>' }
        'every3days' { '<ScheduleByDay><DaysInterval>3</DaysInterval></ScheduleByDay>' }
        'weekly'     { "<ScheduleByWeek><DaysOfWeek><$($Settings.dayOfWeek) /></DaysOfWeek><WeeksInterval>1</WeeksInterval></ScheduleByWeek>" }
        'biweekly'   { "<ScheduleByWeek><DaysOfWeek><$($Settings.dayOfWeek) /></DaysOfWeek><WeeksInterval>2</WeeksInterval></ScheduleByWeek>" }
        'monthly'    { "<ScheduleByMonth><DaysOfMonth><Day>$($Settings.dayOfMonth)</Day></DaysOfMonth><Months><January /><February /><March /><April /><May /><June /><July /><August /><September /><October /><November /><December /></Months></ScheduleByMonth>" }
    }
    $powershell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $ScriptPath
    $battery = if ($Settings.onlyOnAC) { 'true' } else { 'false' }
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>RestoreNest: creates a restore point on a schedule and keeps only the newest ones.</Description></RegistrationInfo>
  <Triggers><CalendarTrigger><StartBoundary>$boundary</StartBoundary><Enabled>true</Enabled>$schedule</CalendarTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>$battery</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT8H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author"><Exec><Command>$(& $esc $powershell)</Command><Arguments>$(& $esc $arguments)</Arguments></Exec></Actions>
</Task>
"@
}

# Oldest restore points beyond the newest $Keep (at least one is always kept). Points are objects with an Id (yyyyMMdd-HHmmss).
function Get-RnPointsToPrune {
    param([Parameter(Mandatory)]$Points, [Parameter(Mandatory)][int]$Keep)
    $ordered = @($Points | Sort-Object Id)
    $keepCount = [math]::Max($Keep, 1)
    if ($ordered.Count -le $keepCount) { return @() }
    @($ordered[0..($ordered.Count - $keepCount - 1)])
}

# Deletes one restore point folder. It must be a complete-point folder directly under $Root; nothing else is ever removed.
function Remove-RnRestorePoint {
    param([Parameter(Mandatory)]$Point, [Parameter(Mandatory)][string]$Root)
    if (-not (Test-RnRestorePointId $Point.Id)) { throw "Refusing to delete '$($Point.Id)': not a restore point id." }
    $expected = [IO.Path]::GetFullPath((Join-Path $Root $Point.Id))
    if ([IO.Path]::GetFullPath($Point.Path) -ine $expected) { throw "Refusing to delete '$($Point.Path)': it is not directly under $Root." }
    Remove-Item -LiteralPath $expected -Recurse -Force
}

function Write-RnScheduleStatus {
    param([Parameter(Mandatory)][string]$Code, [string]$Detail = '', [int]$PointCount = -1, [string[]]$Removed = @())
    $path = Get-RnScheduleStatusPath
    $previous = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) { try { $previous = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $previous = $null } }
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $lastSuccess = if ($Code -eq 'ok') { $now } else { [string](Get-RnProperty $previous 'lastSuccessUtc' '') }
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [ordered]@{ lastRunUtc = $now; code = $Code; detail = $Detail; lastSuccessUtc = $lastSuccess; pointCount = $PointCount; removed = @($Removed) } |
        ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
}
