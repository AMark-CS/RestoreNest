#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Run INSIDE the lab guest after Windows is installed. Creates D: on the same physical disk as C: and seeds test data.
.DESCRIPTION
  Writes D:\keep\*.bin plus D:\keep\hashes.txt so later phases can prove D: was untouched by a restore.
#>
param([int]$DriveSizeGB = 30, [switch]$Force)
$ErrorActionPreference = 'Stop'
$os = Get-Partition -DriveLetter C
$disk = Get-Disk -Number $os.DiskNumber
if ($disk.PartitionStyle -ne 'GPT') { throw 'Lab disk must be GPT.' }
if (-not $Force -and (Get-Partition -DriveLetter D -ErrorAction SilentlyContinue)) { throw 'D: already exists; pass -Force to reuse it.' }
if (-not (Get-Partition -DriveLetter D -ErrorAction SilentlyContinue)) {
    $free = (Get-Disk -Number $disk.Number | Get-PartitionSupportedSize -ErrorAction SilentlyContinue)
    $part = New-Partition -DiskNumber $disk.Number -Size ($DriveSizeGB * 1GB) -DriveLetter D
    Format-Volume -Partition $part -FileSystem NTFS -NewFileSystemLabel 'DATA' -Confirm:$false | Out-Null
}
New-Item -ItemType Directory -Force D:\keep | Out-Null
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
1..5 | ForEach-Object {
    $bytes = New-Object byte[] (8MB); $rng.GetBytes($bytes)
    [IO.File]::WriteAllBytes("D:\keep\data$_.bin", $bytes)
}
Get-ChildItem D:\keep -Filter *.bin | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash)  $(Split-Path $_.Path -Leaf)" } | Set-Content D:\keep\hashes.txt -Encoding ascii
Set-Content C:\marker-before.txt "baseline $(Get-Date -Format o)"
Get-Partition -DiskNumber $disk.Number | Select-Object PartitionNumber, DriveLetter, Type, Size, Guid | Format-Table | Out-String | Set-Content D:\keep\layout-baseline.txt
Write-Host 'Done. Same-disk D: ready. Shut down and take the "baseline" checkpoint.'
