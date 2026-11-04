# Host-safe tests for the recovery environment setup helpers: pinned hashes, Microsoft signature check, wimlib unpacking and ADK
# detection. Nothing is downloaded and nothing is installed.
$ErrorActionPreference = 'Stop'
function Check($ok, $name) { if (-not $ok) { throw "FAILED: $name" } }
function Throws($block, $name) { try { & $block; throw 'no error' } catch { if ($_.Exception.Message -eq 'no error') { throw "FAILED (accepted): $name" } } }

$tools = Join-Path $PSScriptRoot '..\tools'
$work = Join-Path $PSScriptRoot ('..\.tmp-su-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $work
$work = (Resolve-Path $work).Path
try {
    . (Join-Path $tools 'RestorePoint.Common.ps1')
    . (Join-Path $tools 'RestoreSetup.Common.ps1')

    # ---- pinned values look right
    Check ($script:RnWimlibSha256 -match '\A[0-9A-F]{64}\z') 'the pinned wimlib hash is a SHA-256'
    Check ($script:RnWimlibUrl -like 'https://wimlib.net/*' -and $script:RnAdkUrl -like 'https://go.microsoft.com/*' -and $script:RnWinPeAddonUrl -like 'https://go.microsoft.com/*') 'downloads come from the publishers over https'

    # ---- hash check
    $file = Join-Path $work 'sample.bin'
    Set-Content -LiteralPath $file -Value 'hello' -Encoding ascii
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    Assert-RnFileHash -Path $file -Sha256 $hash
    Assert-RnFileHash -Path $file -Sha256 $hash.ToLowerInvariant()
    Throws { Assert-RnFileHash -Path $file -Sha256 ('0' * 64) } 'a different file is refused'

    # ---- Microsoft signature check
    $signed = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
    Assert-RnMicrosoftSigned -Path $signed
    Throws { Assert-RnMicrosoftSigned -Path $file } 'an unsigned file is not run'
    $copy = Join-Path $work 'tampered.exe'
    Copy-Item -LiteralPath $signed -Destination $copy
    $bytes = [IO.File]::ReadAllBytes($copy); $bytes[$bytes.Length / 2] = [byte](($bytes[$bytes.Length / 2] + 1) % 256); [IO.File]::WriteAllBytes($copy, $bytes)
    Throws { Assert-RnMicrosoftSigned -Path $copy } 'a modified signed file is not run'

    # ---- wimlib unpacking from a zip
    $stage = Join-Path $work 'zipsource'
    $null = New-Item -ItemType Directory -Path $stage
    Set-Content -LiteralPath (Join-Path $stage 'wimlib-imagex.exe') -Value 'fake exe' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $stage 'libwim-15.dll') -Value 'fake dll' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Value 'readme' -Encoding ascii
    $zip = Join-Path $work 'wimlib.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip
    $zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $bin = Join-Path $work 'tools\bin'
    Throws { Install-RnWimlib -ZipPath $zip -BinDirectory $bin } 'the real pinned hash does not match a different zip'
    Check (-not (Test-Path -LiteralPath $bin)) 'a refused zip puts nothing into the tools folder'
    Install-RnWimlib -ZipPath $zip -BinDirectory $bin -Sha256 $zipHash
    Check ((Test-Path (Join-Path $bin 'wimlib-imagex.exe')) -and (Test-Path (Join-Path $bin 'libwim-15.dll')) -and -not (Test-Path (Join-Path $bin 'README.txt'))) 'only the two needed files are installed'
    $incomplete = Join-Path $work 'incomplete.zip'
    Compress-Archive -Path (Join-Path $stage 'README.txt') -DestinationPath $incomplete
    Throws { Install-RnWimlib -ZipPath $incomplete -BinDirectory (Join-Path $work 'bin2') -Sha256 (Get-FileHash -LiteralPath $incomplete -Algorithm SHA256).Hash } 'a zip without the program is refused'

    # ---- ADK detection
    $adk = Join-Path $work 'adk'
    Check (-not (Test-RnAdkInstalled -AdkRoot $adk)) 'no ADK found in an empty folder'
    $pe = Join-Path $adk 'Windows Preinstallation Environment'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $pe 'amd64\en-us')
    Set-Content -LiteralPath (Join-Path $pe 'copype.cmd') -Value 'rem' -Encoding ascii
    Check (-not (Test-RnAdkInstalled -AdkRoot $adk)) 'copype alone is not enough'
    Set-Content -LiteralPath (Join-Path $pe 'amd64\en-us\winpe.wim') -Value 'wim' -Encoding ascii
    Check (Test-RnAdkInstalled -AdkRoot $adk) 'copype and winpe.wim together mean installed'
    Check ((Get-RnAdkRoot) -like '*Windows Kits\10\Assessment and Deployment Kit') 'default ADK location'

    # ---- a failed download is reported in plain words and leaves no file
    $target = Join-Path $work 'never.bin'
    Throws { Save-RnDownload -Url 'https://invalid.invalid/none.zip' -Destination $target } 'a failed download is an error'
    try { Save-RnDownload -Url 'https://invalid.invalid/none.zip' -Destination $target } catch { Check ($_.Exception.Message -like '*Check the internet connection*') 'the download error tells what to do' }
    Write-Host 'Recovery setup checks passed.'
}
finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
