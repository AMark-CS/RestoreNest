#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Creates the disposable Hyper-V Gen2 lab VM used to validate RestoreNest (Phase 0 of the plan).
.DESCRIPTION
  One 80 GB GPT disk, Secure Boot and vTPM on. Windows Setup creates EFI/MSR/C/Recovery; after the first boot run
  tools/lab/Initialize-LabDisk.ps1 inside the guest to add the D: partition on the SAME physical disk, then take
  the 'baseline' checkpoint. Never run restore experiments on the host.
.EXAMPLE
  .\New-LabVM.ps1 -IsoPath E:\Download\Win10_22H2_Eval.iso
#>
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$Name = 'RN-Lab-Win10',
    [string]$VmRoot = 'E:\HyperV\RestoreNest',
    [int64]$DiskSize = 80GB,
    [int64]$Memory = 4GB,
    [int]$Cpu = 4
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }
if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V module missing. Enable with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All (then reboot).'
}
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM '$Name' already exists." }

$dir = Join-Path $VmRoot $Name
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$vhd = Join-Path $dir 'disk.vhdx'
New-VHD -Path $vhd -SizeBytes $DiskSize -Dynamic | Out-Null

New-VM -Name $Name -Generation 2 -MemoryStartupBytes $Memory -VHDPath $vhd -Path $VmRoot -SwitchName (Get-VMSwitch | Select-Object -First 1 -ExpandProperty Name) | Out-Null
Set-VMProcessor -VMName $Name -Count $Cpu
Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
Add-VMDvdDrive -VMName $Name -Path $IsoPath
$dvd = Get-VMDvdDrive -VMName $Name
Set-VMFirmware -VMName $Name -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -FirstBootDevice $dvd
Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector
Enable-VMTPM -VMName $Name
Set-VM -Name $Name -CheckpointType Standard
Write-Host "Created $Name. Start it, install Windows to the 80 GB disk, then run Initialize-LabDisk.ps1 inside the guest."
