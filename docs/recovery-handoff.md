# Experimental recovery handoff

The recovery page can export a JSON task after querying and selecting a Windows backup version. Export reads GPT disk and partition GUIDs for the backup and current Windows volumes through Windows Storage cmdlets. Administrative privileges may be required. Only separate GPT system and backup disks are supported at this stage.

`tools/Test-RecoveryTask.ps1 -TaskPath <exported-json>` performs a read-only identity check. It resolves current disk and partition numbers from GUIDs instead of assuming the drive letters stayed unchanged. It rejects missing or ambiguous disks, same-disk backup storage, missing drive letters and a missing machine backup directory. It does not verify backup contents or perform recovery. A matching identity is not proof that a restore is safe.

The task is unsigned and editable; it is not authorization to write a disk. Before a recovery executor can consume it, it must re-query the backup version and machine, validate the complete target partition layout, check encryption and media availability, and obtain confirmation for the resolved write targets inside the recovery environment. No automatic restart or disk write is connected to this workflow.

The WPF application is not itself a WinPE application. A recovery environment still needs a separately built and tested frontend/runtime. Windows Storage cmdlets and PowerShell are not available in every WinPE image; the preflight requires those components.

Validation so far: task validation and serialization tests, a clean WPF build, and a read-only host Storage-cmdlet probe. Export through the UI and identity matching after a VM reboot remain untested. Forced removal and 360 removal remain separate unfinished work.
