param([Parameter(Mandatory=$true)][string]$BeforePath, [Parameter(Mandatory=$true)][string]$AfterPath)
$ErrorActionPreference = 'Stop'
$before = Get-Content -LiteralPath $BeforePath -Raw | ConvertFrom-Json
$after = Get-Content -LiteralPath $AfterPath -Raw | ConvertFrom-Json
if ($before.Schema -ne 2 -or $after.Schema -ne 2 -or [string]::IsNullOrWhiteSpace($before.Computer) -or $before.Computer -ne $after.Computer) { throw 'Snapshots must use schema 2 and come from the same machine.' }
foreach ($snapshot in @($before, $after)) {
    foreach ($category in @('Applications', 'ServicesAndDrivers', 'ScheduledTasks', 'Files')) {
        if ($null -eq $snapshot.PSObject.Properties[$category] -or $null -eq $snapshot.$category) { throw "Missing snapshot category: $category" }
    }
    foreach ($entry in @($snapshot.Applications)) { if ([string]::IsNullOrWhiteSpace($entry.PSPath)) { throw 'Application identity is missing.' } }
    foreach ($entry in @($snapshot.ServicesAndDrivers)) { if ([string]::IsNullOrWhiteSpace($entry.Name)) { throw 'Service identity is missing.' } }
    foreach ($entry in @($snapshot.ScheduledTasks)) { if ([string]::IsNullOrWhiteSpace($entry.TaskPath) -or [string]::IsNullOrWhiteSpace($entry.TaskName)) { throw 'Task identity is missing.' } }
    foreach ($entry in @($snapshot.Files)) { if ([string]::IsNullOrWhiteSpace($entry.FullName)) { throw 'File identity is missing.' } }
}
function Compare-Keys($old, $new) {
    $oldSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $newSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $old) { if (-not [string]::IsNullOrWhiteSpace($item)) { [void]$oldSet.Add($item) } }
    foreach ($item in $new) { if (-not [string]::IsNullOrWhiteSpace($item)) { [void]$newSet.Add($item) } }
    [pscustomobject]@{ Added = @($newSet | Where-Object { -not $oldSet.Contains($_) } | Sort-Object); Removed = @($oldSet | Where-Object { -not $newSet.Contains($_) } | Sort-Object) }
}
[pscustomobject]@{
    Applications = Compare-Keys @($before.Applications | ForEach-Object PSPath) @($after.Applications | ForEach-Object PSPath)
    ServicesAndDrivers = Compare-Keys @($before.ServicesAndDrivers | ForEach-Object Name) @($after.ServicesAndDrivers | ForEach-Object Name)
    ScheduledTasks = Compare-Keys @($before.ScheduledTasks | ForEach-Object { $_.TaskPath + $_.TaskName }) @($after.ScheduledTasks | ForEach-Object { $_.TaskPath + $_.TaskName })
    Files = Compare-Keys @($before.Files | ForEach-Object FullName) @($after.Files | ForEach-Object FullName)
    Note = 'Candidates only: name matching is incomplete and does not establish ownership.'
}
