$ErrorActionPreference = 'Stop'
$output = Join-Path ([IO.Path]::GetTempPath()) ('rn-evidence-' + [guid]::NewGuid() + '.json')
$global:rnRegistryFailure = $false
function Get-ItemProperty { [CmdletBinding()] param($Path) if ($global:rnRegistryFailure) { Write-Error 'Access denied' }; @([pscustomobject]@{ DisplayName='360 Example'; Publisher='Qihoo'; DisplayVersion='1' }, [pscustomobject]@{ DisplayName='Other'; Publisher='Other' }) }
function Get-CimInstance { param($ClassName) if ($ClassName -eq 'Win32_Service') { [pscustomobject]@{ Name='360Example'; DisplayName='Example'; PathName='C:\360\example.exe' } } }
function Get-ScheduledTask { @([pscustomobject]@{ TaskName='Other'; TaskPath='\'; Actions=@([pscustomobject]@{ Execute='C:\360\example.exe' }) }) }
function Test-Path { param($LiteralPath, $PathType) return $false }
try {
    & (Join-Path $PSScriptRoot '..\tools\Get-QihooEvidence.ps1') -OutputPath $output
    $result = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if (-not $result.Complete -or $result.Schema -ne 3) { throw 'Complete snapshot was not marked complete.' }
    if ($result.Applications.Count -ne 1 -or $result.Applications[0].DisplayName -ne '360 Example') { throw 'Application filtering failed.' }
    if ($result.ServicesAndDrivers.Count -ne 1 -or $result.ScheduledTasks.Count -ne 1) { throw 'Service or task discovery failed.' }
    if ($result.Files.Count -ne 0) { throw 'Missing directory should not produce files.' }
    $global:rnRegistryFailure = $true
    & (Join-Path $PSScriptRoot '..\tools\Get-QihooEvidence.ps1') -OutputPath $output
    $incomplete = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if ($incomplete.Complete -or $incomplete.UninstallReadErrors -lt 1) { throw 'Registry access failure was not recorded.' }
    'Qihoo evidence tests passed.'
}
finally { Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue }
