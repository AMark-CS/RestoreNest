# Experimental recovery handoff

The recovery page can export a JSON task after querying and selecting a Windows backup version. Export reads GPT disk and partition GUIDs for the backup and current Windows volumes through Windows Storage cmdlets. Administrative privileges may be required. Only separate GPT system and backup disks are supported at this stage.

`tools/Test-RecoveryTask.ps1 -TaskPath <exported-json>` performs read-only checks. It resolves current disk and partition numbers from GUIDs instead of assuming the drive letters stayed unchanged. It rejects missing or ambiguous disks, same-disk backup storage, missing drive letters, a missing machine backup directory and a backup version absent from the current `wbadmin` catalog. It does not verify backup contents or perform recovery. A matching identity and catalog entry are not proof that a restore is safe.

The task is unsigned and editable; it is not authorization to write a disk. Before a recovery executor can consume it, it must re-query the backup version and machine, validate the complete target partition layout, check encryption and media availability, and obtain confirmation for the resolved write targets inside the recovery environment. No automatic restart or disk write is connected to this workflow.

The WPF application is not itself a WinPE application. A recovery environment still needs a separately built and tested frontend/runtime. Windows Storage cmdlets and PowerShell are not available in every WinPE image; the preflight requires those components.

The ADK WinPE image built and boot-tested on 2026-10-30 contains PowerShell and StorageWMI, but its WIM file listing does not contain `wbadmin.exe`. The existing preflight and proposed `wbadmin` restore therefore cannot be assumed to work in that image. The previous successful native restore used Windows installation media, a different environment. A supported recovery environment with the required tool and dependencies must be verified before connecting the restore button.

Inspection of the Windows 10 Enterprise Evaluation installation media used for that successful native restore found `wbadmin.exe` and `wbengine.exe` in its boot WIM (index 2), but no PowerShell executable or Storage module. Thus this media cannot run the current PowerShell preflight as-is. Combining a compatible recovery environment and the identity checks remains an unverified integration step; copying individual system binaries into the ADK image is not a validated solution.

In an isolated VM, DISM successfully added the matching Windows 10 2004 ADK WMI, .NET, scripting, PowerShell and StorageWMI packages and their en-US resources to a copy of that installer image. Committing the image succeeded, but exporting it to the test's virtual FAT output disk failed for insufficient space. The modified image has not yet been exported, booted, or tested with the preflight and recovery command.

Validation so far: task validation and serialization tests, mocked preflight checks for drive-letter resolution, a missing version and ambiguous disks, a clean WPF build, and a read-only host Storage-cmdlet probe. Export through the UI and identity matching after a VM reboot remain untested. Forced removal and 360 removal remain separate unfinished work.
