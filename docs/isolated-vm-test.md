# Isolated Windows 10 backup and recovery test

Date: 2026-10-29. This is one experimental test, not a release qualification.

- Windows 10 Enterprise Evaluation 22H2 ran offline in QEMU using software emulation. The system and backup were separate virtual disks; recovery wrote to a disposable system-disk overlay and the backup disk was attached through a temporary snapshot.
- A test runner invoked the repository's experimental `WbadminBackup.RunAsync` to back up the critical volumes to a local NTFS volume, `R:`. The command exited with code 0, and `wbadmin get versions` listed a bare-metal recovery backup.
- A separate test harness booted the Windows installation media's recovery environment and invoked native `wbadmin start sysrecovery`. The backup volume appeared as `D:` in that environment. Recovery exited with code 0 and reported successful recovery of EFI, Windows, and recovery volumes.
- The recovered system-disk overlay subsequently booted to the Windows lock screen. Login, application behavior and restored user files were not verified.
- A signed 360 Safe executable was present in the guest. An uninstall-registry scan did not find an entry, so a complete installation is not established. Forced removal and 360 cleanup were not tested.

The guest clock recorded approximately 14 minutes for the backup, but software emulation can affect the clock; this is not an elapsed-time benchmark or a 30-minute guarantee. Restore duration was not measured reliably.

The experimental backup path is not connected to the application UI and accepts a drive root, not an arbitrary directory. The recovery command was run by the test harness, not by a RestoreNest recovery feature. Same-physical-disk backup preservation, external drives, Windows 11, BitLocker, failure cases, and interrupted recovery remain untested. The VM images and logs are local test artifacts and are not included in the repository.
