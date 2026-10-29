$ErrorActionPreference = 'Stop'
$output = Join-Path ([IO.Path]::GetTempPath()) ('rn-evidence-' + [guid]::NewGuid() + '.json')
function Get-ItemProperty { param($Path, $ErrorAction) @([pscustomobject]@{ DisplayName='360 Example'; Publisher='Qihoo'; DisplayVersion='1' }, [pscustomobject]@{ DisplayName='Other'; Publisher='Other' }) }
function Get-CimInstance { param($ClassName) if ($ClassName -eq 'Win32_Service') { [pscustomobject]@{ Name='360Example'; DisplayName='Example'; PathName='C:\360\example.exe' } } }
function Get-ScheduledTask { @([pscustomobject]@{ TaskName='Other'; TaskPath='\'; Actions=@([pscustomobject]@{ Execute='C:\360\example.exe' }) }) }
function Test-Path { param($LiteralPath, $PathType) return $false }
try {
    & (Join-Path $PSScriptRoot '..\tools\Get-QihooEvidence.ps1') -OutputPath $output
    $result = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if ($result.Applications.Count -ne 1 -or $result.Applications[0].DisplayName -ne '360 Example') { throw 'Application filtering failed.' }
    if ($result.ServicesAndDrivers.Count -ne 1 -or $result.ScheduledTasks.Count -ne 1) { throw 'Service or task discovery failed.' }
    if ($result.Files.Count -ne 0) { throw 'Missing directory should not produce files.' }
    'Qihoo evidence tests passed.'
}
finally { Remove-Item -LiteralPath $output -ErrorAction SilentlyContinue }
