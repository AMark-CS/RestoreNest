# VM validation record (2026-11-01 to 2026-11-02)

This records what was actually run, so the README claims can be checked. Everything here is one Windows 10 Enterprise Evaluation 22H2 guest (plus one Windows 11 Enterprise Evaluation guest, see its own section), one image per OS, one run per item, under QEMU **software emulation (TCG)**, UEFI. Most items ran without Secure Boot and without BitLocker; the Secure Boot and BitLocker sections below say where those were on. Durations are emulation times, not hardware benchmarks.

## Method

- Disposable qcow2 overlay on the existing Windows 10 base image; one GPT disk, 96 GiB: EFI, MSR, Windows, Recovery.
- WinPE (Windows 10 2004 setup `boot.wim` with PowerShell and Storage, already used in earlier tests) booted from a FAT USB image. A harness script on a small results disk ran one stage per boot (info, prep, baseline, capture, mutate, restore, verify, bootentry, bootremove) and wrote logs and `RN_CHECK … PASS/FAIL` lines back for the host to read.
- The harness and the QEMU launch scripts live outside the repository (they contain machine-specific paths). The product scripts under `tools/` were the ones executed, unmodified apart from the fixes listed below.
- The first capture was **offline** (`-NoSnapshot`) because WinPE has no VSS. A second capture was done **online with VSS** inside the running guest (see "Online VSS capture").

## Setup

In WinPE the Windows partition was shrunk 87.9 → 60 GiB and a 20 GiB NTFS data partition (`RNDATA`, same physical disk) was created holding five random 4 MiB files plus their SHA-256 list. Layout (GUID, size, type of every partition) and hashes were saved as the baseline.

## Results

| Item | Result |
|---|---|
| Offline capture (XPRESS) of the Windows partition to `RNDATA:\RestoreNest\<id>` | OK, 4.48 GiB, ~22 min; `meta.json` written, SHA-256 and `wimlib verify` OK |
| Damage: delete `winload.efi`, add a marker file, remove a marker file | applied |
| `Restore.ps1` dry run | printed plan: write Windows partition, boot files only on EFI partition, backup partition not touched; wrote nothing |
| `Restore.ps1 -Execute` | OK, ~15 min; image applied, `bcdboot` succeeded |
| Files after restore | deleted marker back, new marker gone, `winload.efi` back |
| **Data partition file hashes** | **identical to baseline** |
| **Every partition's GUID, size and type** | **identical to baseline** |
| Backup image after restore | still passes SHA-256 and `wimlib verify` |
| EFI partition | `\EFI\Microsoft\Boot\bootmgfw.efi` present |
| Boot restored disk (UEFI) | reached the Windows 10 lock screen within ~2.5 min; not logged in |
| `Install-BootEntry.ps1 -Store` on the real BCD | entry created, state file written, BCD file backed up, files copied, default OS and menu timeout unchanged |
| Boot via the new entry (entry temporarily set as default for an unattended test) | booted the WinPE ramdisk (`X:`), recovery-side script ran |
| `Install-BootEntry.ps1 -Remove -Store` | entry and state file removed; default OS and timeout unchanged |
| Install entry, damage C:, `Restore.ps1 -Execute` (second full cycle, ~26 min restore) | `bcdboot` kept the entry; `Restore.ps1` reported it still present and did not re-create it; the final BCD has exactly one "RestoreNest Recovery" entry, default still Windows, timeout still 30 |

## Online VSS capture (live guest)

The booted Windows 10 guest ran `New-RestorePoint.ps1` (no `-NoSnapshot`, default LZX) via an offline-configured autologon + RunOnce. The evaluation licence's `wlms.exe` forced shutdown had killed an earlier attempt at 54%, so `wlms` was disabled in the test guest only.

| Step | Result |
|---|---|
| Online capture with `--snapshot` | OK, 4.48 GiB, 7,609 s under QEMU TCG (software emulation: **not** a real-hardware time); `Get-RestorePoint -Verify` status ok |
| Restore this online image from WinPE (`Restore.ps1 -Execute`, 134,751 files, 984 s) | OK; `bcdboot` succeeded |
| WinPE checks | `winload.efi` back, mutation markers gone, live marker restored, one Windows volume, one data volume, partition layout identical, data hashes identical, backup still verifies, `bootmgfw.efi` present: all PASS |
| Boot restored disk, autologon, guest script | logged in and ran: live marker restored, post-capture marker gone, `winload.efi` present, data volume present, data hashes identical: all PASS |

## Failure injection and the app-to-script layer

| Test | Result |
|---|---|
| Offline capture killed (QEMU stopped) 5 minutes in | no partial image is listed; `Get-RestorePoint` lists only the 2 complete points; a `.partial` folder stays on disk and is reclaimed by the next create after 2 h; a new capture still plans normally |
| Restore (`Restore.ps1 -Execute`) killed ~2 minutes into the apply, then run again from scratch | second run completed (1,050 s); same 11 WinPE checks as before PASS (hashes, partition layout, markers, backup verifies, `bootmgfw.efi`); restored system logged in and passed the live checks |
| The app's own C# code (`RestorePoints.ListAsync` / `RunScriptAsync`) run inside the guest as a self-contained exe | lists points and parses every field; a name like `测试 name; calc` stays one argument; script output streams back; a system-drive destination is rejected (exit 1) |

Not tested: the WPF window itself in the guest (no .NET 8 desktop runtime there; the window was only rendered offscreen on the host), power loss at other points of a restore (for example during `Format-Volume`, where the Windows partition is by definition unusable until a restore finishes), and a low-space destination in a real capture (the free-space check is unit-tested only).

## Secure Boot (edk2 secure firmware, keys enrolled)

Method: QEMU with `edk2-x86_64-secure-code.fd`, `q35,smm=on` and `-global cfi.pflash01,secure=on`; the vars file started in Setup Mode. Inside the live guest `Set-SecureBootUEFI` enrolled db (a throwaway KEK certificate plus *Microsoft Windows Production PCA 2011*, taken from a signed Windows boot manager), KEK and PK, in that order. The payloads are signed with throwaway keys; they are test keys, not Microsoft's.

| Test | Result |
|---|---|
| Enrollment in the live guest | OK; `Confirm-SecureBootUEFI` False before, True after; guest booted and logged in with `UEFISecureBootEnabled=1` |
| Full restore chain under enforcing Secure Boot: break the system, `Restore.ps1 -Execute` in WinPE (1,043 s), verify, boot, login | 12 WinPE checks and 8 live checks PASS (hashes, partition layout, markers, `bootmgfw.efi`, `UEFISecureBootEnabled=1`) |
| Recovery boot-menu entry under Secure Boot: install in WinPE, boot the installed OS, select the entry **with the keyboard** (Down + Enter sent through QMP), land in WinPE, remove the entry | OK; Windows stayed the default, timeout unchanged, entry and state file removed |

Finding: the first WinPE boot under enforcement failed with `0xc000000f` from Windows Boot Manager. The test media paired a Windows 11 boot manager (10.0.26089 / 28000) with a Windows 10 `boot.wim` (`winload.efi` 19041.1949). Replacing the boot manager and `bootx64.efi` with the copies from inside that same `boot.wim` (19041.1949) fixed it; the same media booted in Setup Mode, so the cause was the version mismatch under enforcement, not the BCD, the signatures or the firmware. `Build-WinPE.ps1` uses `copype`, which takes both from one ADK and so should not mix versions, but **a WinPE whose boot manager and `winload.efi` come from different builds will not boot with Secure Boot on**. `Build-WinPE.ps1` itself was still not run.

## BitLocker (password protector, no TPM)

Method: in the live Windows 10 guest, group policy `EnableBDEWithNoTPM`, then `Enable-BitLocker -UsedSpaceOnly -PasswordProtector` plus a recovery password on C: (Secure Boot on). There is no TPM in the VM, so **TPM-bound BitLocker was not tested**; the pre-boot password prompt was answered through QMP key presses.

| Test | Result |
|---|---|
| Encrypt C: (XTS-AES-128, used space only) | FullyEncrypted in 17 min; protection on |
| Boot with the pre-boot password prompt | OK; autologon reached the desktop |
| Online VSS capture of the encrypted C: | OK: 4,294 s, listed and verified (`bl-vss`); the VSS snapshot of an unlocked encrypted volume is readable |
| WinPE view of the encrypted C: | partition present, **no file system, size 0**: unreadable, as expected |
| `Restore.ps1` on the locked C: (before the fix) | refused with "Target filesystem is '', not NTFS (locked by BitLocker, or damaged?)"; nothing written (safe, but no way forward) |
| `manage-bde -unlock C: -RecoveryPassword` in WinPE | OK |
| `Restore.ps1 -RecoveryPassword` with a wrong (well-formed) key | refused, nothing written, C: still locked |
| `Restore.ps1 -RecoveryPassword` with a malformed key | refused before `manage-bde` is called |
| `Restore.ps1 -RecoveryPassword` with the right key on the encrypted C: | unlocked, formatted, applied (882 s); `manage-bde`: Fully Decrypted, Protection Off |
| Boot the restored system | OK; marker from the capture restored, marker created after the capture gone, `winload.efi` present, data hashes identical, `UEFISecureBootEnabled=1` |

Behaviour to know: the restored Windows partition is **not encrypted** (the image is plain files; `Format-Volume` replaces the encrypted volume). Turn BitLocker on again afterwards. The recovery password has to be available in WinPE; without it a restore of a BitLocker system partition cannot proceed. A BitLocker-locked *backup* partition is not listed (no file system) and was not tested.

Harness notes (test setup, not product): a second QEMU writing the same FAT results disk corrupted it and made WinPE find no harness; after BitLocker boots the one-shot search for the results disk in `GuestBoot.cmd` ran before the USB disk was mounted (now a retry loop); the BitLocker pre-boot screen powers the VM off after about a minute without input.

## Windows 11 (restored from the Windows 10 WinPE)

Guest: Windows 11 Enterprise Evaluation, zh-CN, build 10.0.26300, installed unattended from the ISO into a fresh 96 GiB disk laid out like the Windows 10 guest (EFI 300 MB, MSR, Windows 60 GiB, Recovery 1 GiB, the rest left for the data partition). The VM has no TPM and no Secure Boot, so the install used the usual `LabConfig` bypass values (`BypassTPMCheck`, `BypassSecureBootCheck`, `BypassRAMCheck`, `BypassCPUCheck`, `BypassStorageCheck`) set from `autounattend.xml` before setup starts; normal (non Secure Boot) firmware, because the install media's boot manager is not signed by the hand-enrolled db. The install took 100 minutes under TCG. The recovery WinPE was **still the Windows 10 2004 one**; the point of the test was that it can restore a Windows 11 image.

| Test | Result |
|---|---|
| Online VSS capture in the live Windows 11 guest | OK: 14 GiB of files, 6.85 GiB image, 2,456 s; `Get-RestorePoint -Verify` status ok |
| Break the system from WinPE (`winload.efi` deleted, markers changed) | done |
| `Restore.ps1 -Execute` from the Windows 10 WinPE | OK (1,920 s); `bcdboot` ran and reported "Boot files successfully created"; wimlib warned that it could not set short (8.3) names on 10 files, which is harmless |
| WinPE checks | `winload.efi` back, markers correct, one Windows volume, one data volume, partition layout identical, data hashes identical, backup still verifies, `bootmgfw.efi` present: all PASS |
| Boot the restored disk, autologon, guest script | logged in, build 10.0.26300; markers correct, `winload.efi` present, data hashes identical: all PASS |

Not tested for Windows 11: Secure Boot (the Windows 11 boot manager on the disk may be signed with the 2023 CA that the test db does not contain), BitLocker, the boot-menu entry, TPM.

Finding (fixed): the first Windows 11 restore passed every check and still had a bug. wimlib's stderr warning above is a terminating error under `$ErrorActionPreference = 'Stop'` in Windows PowerShell 5.1 when the caller redirects streams, so `Restore.ps1` stopped right after the apply, **before `bcdboot` ran**. The disk booted only because the previous Windows 11 boot files were still on the EFI partition, so the checks could not tell. Native tools are now run through `Invoke-RnNative`, which judges them by exit code; the rerun above is the one with "Boot files successfully created". `New-RestorePoint.ps1` uses the same helper for the capture.

## Rerun with the final scripts (Windows 10, Secure Boot on)

The Windows 10 Secure Boot and BitLocker runs above predate the last script fix (`Invoke-RnNative`), so the whole chain was run once more with the committed scripts: online VSS capture (6,309 s, status ok), break, `Restore.ps1 -Execute` from WinPE (843 s, "Boot files successfully created"), then the 12 WinPE checks and, after booting, the 8 live checks (`UEFISecureBootEnabled=1`, markers, `winload.efi`, data hashes): all PASS.

The first attempt stopped on purpose: the capture script refused with "Not enough free space: need about 8.6 GiB, have 5.9 GiB" because the 20 GiB test data partition held three old test points. Nothing was written. The old points were deleted from WinPE and the run was repeated, which confirms the free-space guard works in a real run.

## Building the recovery WinPE with the real ADK, and restoring from it

Until now every test booted a WinPE assembled by hand in a builder VM, and `Build-WinPE.ps1` had never been run. It was run for real in the Windows 10 guest (elevated, Secure Boot on): the official offline installers of the Windows ADK and the WinPE add-on (both 10.1.26100.9457) were installed silently (692 s and 389 s under TCG), then `Build-WinPE.ps1 -WimlibPath ... -OutDir ...` with its default ADK path. It produced a 479 MiB `boot.wim` plus `boot.sdi` in 2,921 s; the image contains `restorenest\Restore.ps1` and `manage-bde.exe`.

Then the whole product flow was exercised with that image:

| Step | Result |
|---|---|
| `Install-BootEntry.ps1` on the **live** BCD (not an offline copy) | OK; entry in `displayorder`, Windows still the default |
| Break the system (`winload.efi` deleted) and boot it | Windows Boot Manager shows the "Recovery" screen for `\Windows\system32\winload.efi` (0xc000000f) **instead of the boot menu**; F9 ("use a different operating system") leads to the menu. |
| Select "RestoreNest Recovery" | the built WinPE booted, `startnet.cmd` started `Restore.ps1` automatically |
| Interactive dry run: choose restore point `1` | image verified, plan printed (format + apply the 60 GiB Windows partition, write the EFI partition, backup partition untouched), "Dry run only" |
| `.\Restore.ps1 -Id <id> -Execute`, then type `RESTORE <id>` at the prompt | restored (135,020 files); "Boot files successfully created", "Recovery boot entry is still present", "Restore finished" |
| Verify from WinPE, then boot | 12 WinPE checks and 8 live checks PASS (Windows 10 build 10.0.19045, `UEFISecureBootEnabled=1`) |

Findings from running `Build-WinPE.ps1` for the first time (all fixed):

- It failed immediately: `copype.cmd` reads `%WinPERoot%`, `%OSCDImgRoot%` and `%DISMRoot%`, which the "Deployment and Imaging Tools Environment" normally sets and a plain PowerShell does not. The script now sets them.
- `dism /Add-Package /PackagePath:(Join-Path ...)` reached `dism.exe` as two arguments ("/PackagePath:" and the path) and failed with error 87. The paths are now built first.
- A failed build left its work directory behind, and the next run refused to start. A failed build now removes it.
- The image had no `manage-bde`, so `Restore.ps1` warned "BitLocker state could not be checked" and **could not unlock a BitLocker-locked Windows partition** (the unlock tests above used the hand-built WinPE, which had it). `WinPE-SecureStartup` is now part of the build; the rebuilt image has `manage-bde.exe`. The recovery-password unlock itself was not repeated with the rebuilt image.
- The bootable media is not part of the output: the recovery entry is a ramdisk boot of `boot.wim` from the data partition, so the Windows boot manager of the installed system is used. In this run that was the Windows 10 (19041) boot manager loading the 26100 WinPE under enforcing Secure Boot, and it worked; the boot manager / `boot.wim` mismatch described under Secure Boot only concerned the USB test media.

## Second round (2026-11-04 to 2026-11-05): scheduled capture, uninstall, one-click setup, graphical recovery

Same QEMU/edk2 Secure Boot lab, Windows 10 22H2 guest.

| Area | What was run | Result |
|---|---|---|
| Scheduled restore points | `Set-RestoreSchedule.ps1 -Apply` registers the SYSTEM task; the task was started and ran the whole chain (capture to the data partition, retention, status file) | PASS. Scripts run from the admin-only `%ProgramData%\RestoreNest\bin` copy. A too-small data partition was refused with the free-space message (nothing written), then grown and rerun. |
| Uninstall with real installers | 7-Zip (MSI) and Notepad++ (NSIS) installed silently, removed through the app's own `Uninstaller`; a Store app removed with `Remove-AppxPackage`; a Windows restore point requested first | PASS for the listing, silent plans, exit codes, "gone from the list" and the Store removal. The leftover scan missed the NSIS install folder (empty `InstallLocation`); it now also offers the folder holding the uninstaller when that sits directly in Program Files / `LocalAppData\Programs`. That fix has unit tests but was **not rerun in the VM**. |
| One-click setup | `Prepare-Recovery.ps1` (9 checks) | PASS. The ADK was already installed in the guest, so the silent ADK install and signature check on a fresh machine were not exercised. |
| Graphical recovery screen in real WinPE | Booted from the boot menu entry; Chinese UI; list, confirmation, progress, real restore of the 60 GiB Windows partition, restart | The restore worked and the system booted afterwards (8 post-checks PASS: Secure Boot on, marker created after the point is gone, `winload.efi` present, booted into Windows not recovery, data partition hashes unchanged, one-time boot entry not sticky). |

Bugs found in the graphical recovery screen (fixed, covered by regression tests):

- The confirmation phrase `RESTORE <id>` reached the restore process unquoted, so `Start-Process` split it into two arguments and the restore refused to start. Arguments are now built and quoted by `Get-RnRestoreProcessArguments`.
- `Start-Process -PassThru` returned a process whose `ExitCode` was empty (Windows PowerShell 5.1), so a restore that had **succeeded** was shown as "not finished". `Start-RnProcess` now caches the handle; the rerun shows the "Restore finished" page.
- Minor: the button on the finished page read "Restart without restoring"; it now reads "Restart". (Wording only; the image was built before this change, so the new label itself was not seen in the VM.)

Installer (`RestoreNest-Setup-0.2.0.exe`, Inno Setup, self-contained): in the Windows 10 guest, which has **no .NET runtime**, a silent install (exit 0) put `SystemCare.exe` and the scripts in Program Files, created the empty `tools\bin` folder (wimlib is not bundled), the "Apps & features" entry and the Start menu and desktop shortcuts. The app started and was still running after 15 s. The silent uninstall (exit 0) removed the folder, the entry and the shortcuts: 17 checks PASS. Not covered: the wizard pages themselves (only silent mode was run), upgrading over an older version, and user-run Windows Defender / SmartScreen behaviour for an unsigned installer.

Not covered in this round: the BitLocker prompt inside the graphical screen, and the ADK silent install on a clean machine.

## Bugs found by these runs (all fixed)

- `bcdedit /store <file> /export` is rejected; offline stores are now backed up by copying the file.
- The installer forced the menu timeout to 10 s and never restored it; it now leaves a non-zero timeout alone and records/restores the original if it had to enable the menu.
- `Restore.ps1` would stop if `manage-bde` was absent; it now warns.
- `Build-WinPE.ps1` had never been run and failed in several ways (see "Building the recovery WinPE with the real ADK"); it now builds, and the image includes `manage-bde`.
- A harmless wimlib warning on stderr aborted `Restore.ps1` before `bcdboot` (see the Windows 11 section); native tools are now judged by exit code.
- A BitLocker-locked Windows partition made `Restore.ps1` stop with no way forward; it now accepts `-RecoveryPassword` (or prompts), unlocks in WinPE, and still writes nothing if the key is missing, malformed or wrong.
- After a restore with the recovery entry installed, `Restore.ps1` always re-created the entry although `bcdboot` had kept it, leaving **two** identical entries; it now re-creates it only if the recorded entry is missing.
- Metadata read the Windows version of the running OS (WinPE); it now reads the captured system's kernel version.
- The harness itself had several bugs (strict-mode `Count`, a `$dl:` parse error, results wiped between stages, a BOM breaking a Python helper). Two reruns produced stale logs; they were discarded and rerun from a clean snapshot. A BCD polluted by an earlier test also produced two false failures before the clean rerun.

## Not verified

Secure Boot and BitLocker on Windows 11; TPM-bound BitLocker (and the recovery prompt that changing the boot configuration can trigger with it); a BitLocker-locked backup partition; the recovery-password unlock run again inside the image built by `Build-WinPE.ps1`; power loss at other restore stages; low space in a real capture; physical hardware and real storage drivers; application-level state after restore (only login and file markers were checked); the re-creation branch of `Restore.ps1` (entry missing after `bcdboot`), which never ran because `bcdboot` kept the entry; the data-partition hash check after the *second* restore cycle (it was checked after the first, which used the same code path); the WPF restore points page driving the scripts.
