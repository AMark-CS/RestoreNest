# Backup engine investigation

RestoreNest needs a backup stored in a user-selected local directory and a restore that preserves the partition containing that backup. No engine has yet met these requirements.

## Windows Backup (`wbadmin`)

Microsoft documents `-allCritical` for bare-metal backups, but a local `-backupTarget` is a drive letter or volume GUID, not an arbitrary local directory. The backup target cannot be one of the critical volumes included in the backup. A network share supports a directory but is outside the initial local-disk scope, and repeated backups to a share may overwrite earlier ones. See [wbadmin start backup](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wbadmin-start-backup).

Do not silently replace the user's chosen directory with the root of its drive. The behavior and partition selection of bare-metal recovery need an end-to-end test before this can be considered as a backend.

An experimental `WbadminBackup` code path prepares a VSS copy of critical volumes to a local NTFS drive root, rejects the Windows drive and an existing `WindowsImageBackup` directory, and invokes `wbadmin` without a shell. The preview interface exposes this limited path with an indeterminate progress indicator; the interface itself has not been tested end to end. Its preflight does not establish the identity of all critical volumes or prove backup retention under concurrency, and it cannot honor a user-selected local subdirectory. One isolated Windows 10 test created a backup through this code and restored it with a separate native recovery harness; the recovered system reached the lock screen. See [the test record](isolated-vm-test.md). This does not validate the product's restore workflow or the other requirements below.

## DISM images

DISM can capture a drive into a WIM at a selected path, but an image of the Windows volume alone does not establish that all boot and recovery partitions, partition metadata, BitLocker behavior, or user data can be restored correctly. Microsoft's documented capture workflow boots into Windows PE. See [capture and apply Windows using WIM](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/capture-and-apply-windows-using-a-single-wim?view=windows-11).

FFU captures a physical drive and therefore cannot simply be restored over the same disk while promising to preserve a D: partition and a backup stored there. Microsoft also documents FFU capture restrictions. See [FFU images](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/deploy-windows-using-full-flash-update--ffu?view=windows-11).

## Required acceptance before relying on backups

1. Confirm redistribution licenses and availability in Windows 10/11 and recovery media.
2. On disposable virtual disks, capture a UEFI/GPT system to a directory on a separate D: partition of the same physical disk. Restore only the selected required partitions and verify D: and its backup are unchanged.
3. Boot the restored system and validate files, installed applications and boot configuration; repeat with a separate external target.
4. Test BitLocker, storage drivers, missing/corrupt media and interrupted restores. Block unsupported layouts before any write.
5. Measure end-to-end backup and restore times on the agreed hardware and dataset. Integrity verification is necessary but does not itself prove bootability.

Do not test restoration against the user's live system disk.

## Existing projects to evaluate

* [Windows Backup & Recovery Tool](https://github.com/abdullah-erturk/Windows-Backup-Recovery-Tool) describes VSS, DISM WIM capture, and separate partition restore. Its documented direct-capture fallback after VSS failure does not satisfy RestoreNest's consistency requirement. Its exclusion list, EFI handling, licenses and D: preservation require source review and isolated tests.
* [UrBackup](https://github.com/uroni/urbackup_backend) supports image backups and recovery, but is a client/server system and its repository is AGPL-3.0. Fit, distribution obligations, local storage and recovery behavior require evaluation before integration.
* [Bulkhead](https://github.com/sp00nznet/bulkhead) describes VHDX imaging and WinPE recovery under MIT. Its maturity, component licenses, isolation of selected partitions and restore correctness have not been independently validated.

These are candidates, not recommendations to use on production systems. A project's own README or checksum verification does not substitute for the recovery acceptance tests above.
