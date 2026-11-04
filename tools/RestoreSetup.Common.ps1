# Helpers for setting up the recovery environment (downloads and their checks). Dot-source after RestorePoint.Common.ps1.
Set-StrictMode -Version 2.0

# Pinned download: wimlib 1.14.5 for Windows x64 from the project's own site (it publishes no checksum, so this one was taken from
# a download and matched against a second copy). A different file is refused rather than trusted.
$script:RnWimlibUrl = 'https://wimlib.net/downloads/wimlib-1.14.5-windows-x86_64-bin.zip'
$script:RnWimlibSha256 = '2F446D6FA3866582175F1A22A7BE198EEEE0AEC7ABA5B4E04AD25C99EAE2D265'
# Microsoft's current ADK and Windows PE add-on installers (10.1.26100.9457). They are small bootstrappers that fetch the rest.
$script:RnAdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2289980'
$script:RnWinPeAddonUrl = 'https://go.microsoft.com/fwlink/?linkid=2289981'

function Get-RnAdkRoot { Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Assessment and Deployment Kit' }

# True when both the Deployment Tools and the Windows PE add-on are installed (what Build-WinPE.ps1 needs).
function Test-RnAdkInstalled {
    param([string]$AdkRoot = (Get-RnAdkRoot))
    (Test-Path -LiteralPath (Join-Path $AdkRoot 'Windows Preinstallation Environment\copype.cmd')) -and
    (Test-Path -LiteralPath (Join-Path $AdkRoot 'Windows Preinstallation Environment\amd64\en-us\winpe.wim'))
}

function Assert-RnFileHash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Sha256)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Sha256.ToUpperInvariant()) { throw "The downloaded file '$(Split-Path $Path -Leaf)' is not the expected one (SHA-256 differs); it was not used." }
}

# Installers are only run when they carry a valid Microsoft signature.
function Assert-RnMicrosoftSigned {
    param([Parameter(Mandatory)][string]$Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "'$(Split-Path $Path -Leaf)' does not carry a valid Microsoft signature; it was not run."
    }
}

function Save-RnDownload {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Destination)
    $previous = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest very slow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    }
    catch { throw "Could not download $Url. Check the internet connection and try again. ($($_.Exception.Message))" }
    finally { $ProgressPreference = $previous }
}

# Puts wimlib-imagex.exe and libwim-15.dll into $BinDirectory from a wimlib zip whose hash matches the pinned one.
function Install-RnWimlib {
    param([Parameter(Mandatory)][string]$ZipPath, [Parameter(Mandatory)][string]$BinDirectory, [string]$Sha256 = $script:RnWimlibSha256)
    Assert-RnFileHash -Path $ZipPath -Sha256 $Sha256
    $extract = Join-Path ([IO.Path]::GetTempPath()) ('rn-wimlib-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $extract -Force
        foreach ($name in 'wimlib-imagex.exe', 'libwim-15.dll') {
            if (-not (Test-Path -LiteralPath (Join-Path $extract $name))) { throw "$name is missing in the wimlib archive." }
        }
        New-Item -ItemType Directory -Force -Path $BinDirectory | Out-Null
        foreach ($name in 'wimlib-imagex.exe', 'libwim-15.dll') { Copy-Item -LiteralPath (Join-Path $extract $name) -Destination $BinDirectory -Force }
    }
    finally { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue }
}

# Runs an ADK installer silently. 0 = installed, 3010 = installed but a restart is pending (not needed for building the image).
function Install-RnAdkComponent {
    param([Parameter(Mandatory)][string]$Installer, [Parameter(Mandatory)][string]$Feature)
    Assert-RnMicrosoftSigned -Path $Installer
    $process = Start-Process -FilePath $Installer -ArgumentList '/quiet', '/norestart', '/ceip', 'off', '/features', $Feature -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) { throw "The Windows ADK installer ($Feature) failed with exit code $($process.ExitCode)." }
}
