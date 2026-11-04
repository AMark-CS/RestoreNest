<#
.SYNOPSIS
  Registers, removes or reports the Task Scheduler job that creates restore points automatically.
.DESCRIPTION
  -Apply   reads schedule.json and registers the task (or removes it when automatic restore points are switched off). Needs
           administrator rights.
  -Remove  removes the task.
  -Status  prints JSON: whether the task exists, its next/last run and the outcome of the last run recorded by
           Invoke-ScheduledRestorePoint.ps1.
#>
[CmdletBinding()]
param([switch]$Apply, [switch]$Remove, [switch]$Status)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')
. (Join-Path $PSScriptRoot 'RestoreSchedule.Common.ps1')
$taskPath = '\RestoreNest\'
$taskName = 'AutoRestorePoint'

function Get-ExistingTask { Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue }

if ($Apply) {
    $settings = Read-RnScheduleSettings
    if (-not $settings.enabled) {
        if (Get-ExistingTask) { Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false }
        Write-Host 'Automatic restore points are off; the scheduled task is removed.'
    }
    else {
        $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required to schedule restore points.' }
        # The task runs as SYSTEM, so it must not run scripts an ordinary user can edit (the app may be installed in a user-writable
        # folder). Copy what it needs into the data folder and lock that folder to SYSTEM/Administrators (everyone else read-only).
        $dataDir = Get-RnDataDirectory
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
        foreach ($rule in @(
                @('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $sid = New-Object Security.Principal.SecurityIdentifier($rule[0])
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, $rule[1], $inherit, 'None', 'Allow')))
        }
        Set-Acl -LiteralPath $dataDir -AclObject $acl
        $secureBin = Join-Path $dataDir 'bin'
        if (Test-Path -LiteralPath $secureBin) { Remove-Item -LiteralPath $secureBin -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $secureBin | Out-Null
        foreach ($name in 'Invoke-ScheduledRestorePoint.ps1', 'New-RestorePoint.ps1', 'RestorePoint.Common.ps1', 'RestoreSchedule.Common.ps1') {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $secureBin -Force
        }
        $wimlibDir = Join-Path $PSScriptRoot 'bin'
        if (Test-Path -LiteralPath $wimlibDir) { Copy-Item -LiteralPath $wimlibDir -Destination (Join-Path $secureBin 'bin') -Recurse -Force }
        $script = Join-Path $secureBin 'Invoke-ScheduledRestorePoint.ps1'
        $xml = New-RnScheduleTaskXml -Settings $settings -ScriptPath $script
        # -User SYSTEM makes the logon type ServiceAccount; without it the cmdlet registers the XML as "run only when a user is
        # logged on" (InteractiveToken), which does not match a SYSTEM principal. (The XML itself must not name a LogonType:
        # "ServiceAccount" is rejected there.) schtasks.exe with /RU SYSTEM is the fallback.
        try { [void](Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Xml $xml -User 'SYSTEM' -Force) }
        catch {
            Write-Warning "Register-ScheduledTask failed ($($_.Exception.Message)); trying schtasks.exe."
            $xmlFile = Join-Path ([IO.Path]::GetTempPath()) ('rn-task-' + [guid]::NewGuid().ToString('N') + '.xml')
            try {
                Set-Content -LiteralPath $xmlFile -Value $xml -Encoding Unicode
                & schtasks.exe /Create /TN "$taskPath$taskName" /XML $xmlFile /RU SYSTEM /F | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "schtasks.exe failed ($LASTEXITCODE)." }
            }
            finally { Remove-Item -LiteralPath $xmlFile -Force -ErrorAction SilentlyContinue }
        }
        Write-Host 'Scheduled.'
    }
}
elseif ($Remove) {
    if (Get-ExistingTask) { Unregister-ScheduledTask -TaskPath $taskPath -TaskName $taskName -Confirm:$false }
    Write-Host 'Removed.'
}
if ($Status -or -not ($Apply -or $Remove)) {
    $task = Get-ExistingTask
    $info = if ($task) { $task | Get-ScheduledTaskInfo } else { $null }
    $last = $null
    $statusPath = Get-RnScheduleStatusPath
    if (Test-Path -LiteralPath $statusPath -PathType Leaf) { try { $last = Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $last = $null } }
    $nextRun = ''
    if ($info -and $info.NextRunTime -and $info.NextRunTime.Year -gt 1999) { $nextRun = $info.NextRunTime.ToUniversalTime().ToString('o') }
    $action = if ($task -and $task.Actions.Count -gt 0) { [string]$task.Actions[0].Arguments } else { '' }
    [ordered]@{
        registered = [bool]$task
        state      = $(if ($task) { [string]$task.State } else { '' })
        nextRunUtc = $nextRun
        taskAction = $action
        last       = $last
    } | ConvertTo-Json -Depth 4 -Compress
}
