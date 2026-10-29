$ErrorActionPreference = 'Stop'
$beforePath = Join-Path ([IO.Path]::GetTempPath()) ('rn-before-' + [guid]::NewGuid() + '.json')
$afterPath = Join-Path ([IO.Path]::GetTempPath()) ('rn-after-' + [guid]::NewGuid() + '.json')
try {
    @{ Schema=2; Computer='TEST'; Applications=@(); ServicesAndDrivers=@(); ScheduledTasks=@(); Files=@(@{FullName='C:\360\old.exe'}, @{FullName='C:\360\SAME.exe'}) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $beforePath
    @{ Schema=2; Computer='TEST'; Applications=@(); ServicesAndDrivers=@(@{Name='360svc'}); ScheduledTasks=@(); Files=@(@{FullName='c:\360\same.exe'}, @{FullName='C:\360\new.exe'}) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $afterPath
    $tool = Join-Path $PSScriptRoot '..\tools\Compare-QihooEvidence.ps1'
    $result = & $tool -BeforePath $beforePath -AfterPath $afterPath
    if ($result.Files.Added.Count -ne 1 -or $result.Files.Added[0] -ne 'C:\360\new.exe' -or $result.Files.Removed.Count -ne 1 -or $result.ServicesAndDrivers.Added[0] -ne '360svc') { throw 'Snapshot comparison failed.' }
    @{ Schema=2; Computer='TEST'; Files=@() } | ConvertTo-Json | Set-Content -LiteralPath $afterPath
    try { & $tool -BeforePath $beforePath -AfterPath $afterPath; throw 'Incomplete snapshot was accepted.' }
    catch { if ($_.Exception.Message -ne 'Missing snapshot category: Applications') { throw } }
    @{ Schema=2; Computer='OTHER' } | ConvertTo-Json | Set-Content -LiteralPath $afterPath
    try { & $tool -BeforePath $beforePath -AfterPath $afterPath; throw 'Mismatched machines were accepted.' }
    catch { if ($_.Exception.Message -ne 'Snapshots must use schema 2 and come from the same machine.') { throw } }
    'Qihoo evidence comparison tests passed.'
}
finally { Remove-Item -LiteralPath $beforePath,$afterPath -ErrorAction SilentlyContinue }
