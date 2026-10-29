param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'

# This collects candidates only; matching names do not prove ownership.
$pattern = '(?i)(360|qihoo|qihu|zhudongfangyu)'
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$uninstallErrors = @()
$apps = @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue -ErrorVariable +uninstallErrors |
    Where-Object { $_.DisplayName -match $pattern -or $_.Publisher -match $pattern } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallLocation, UninstallString, PSPath, PSChildName)
$services = @($(foreach ($class in @('Win32_SystemDriver', 'Win32_Service')) { Get-CimInstance -ClassName $class }) |
    Where-Object { $_.Name -match $pattern -or $_.DisplayName -match $pattern -or $_.PathName -match $pattern } |
    Select-Object Name, DisplayName, PathName, State, StartMode, SystemName)
$tasks = @(Get-ScheduledTask | Where-Object {
    $_.TaskName -match $pattern -or $_.TaskPath -match $pattern -or
    @($_.Actions | Where-Object { $_.Execute -match $pattern -or $_.Arguments -match $pattern }).Count -gt 0
} | Select-Object TaskName, TaskPath, State, Actions)
$roots = @(
    (Join-Path ${env:ProgramFiles(x86)} '360'),
    (Join-Path $env:ProgramFiles '360'),
    (Join-Path $env:ProgramData '360')
) | Select-Object -Unique
$files = foreach ($root in $roots) {
    if (Test-Path -LiteralPath $root -PathType Container) {
        Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop |
            Select-Object FullName, Length, LastWriteTimeUtc
    }
}
$evidence = [ordered]@{
    Schema = 3
    Complete = ($uninstallErrors.Count -eq 0)
    UninstallReadErrors = $uninstallErrors.Count
    CapturedUtc = [DateTime]::UtcNow.ToString('o')
    Computer = $env:COMPUTERNAME
    Applications = $apps
    ServicesAndDrivers = $services
    ScheduledTasks = $tasks
    Files = @($files)
}
$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 -ErrorAction Stop
