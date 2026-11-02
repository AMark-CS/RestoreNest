# VM validation record (2026-11-01 to 2026-11-02)

This records what was actually run, so the README claims can be checked. Everything here is one Windows 10 Enterprise Evaluation 22H2 guest, one image, one run per item, under QEMU **software emulation (TCG)**, UEFI. Most items ran without Secure Boot and without BitLocker; the Secure Boot and BitLocker sections below say where those were on. Durations are emulation times, not hardware benchmarks.

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

## Bugs found by these runs (all fixed)

- `bcdedit /store <file> /export` is rejected; offline stores are now backed up by copying the file.
- The installer forced the menu timeout to 10 s and never restored it; it now leaves a non-zero timeout alone and records/restores the original if it had to enable the menu.
- `Restore.ps1` would stop if `manage-bde` was absent; it now warns.
- A BitLocker-locked Windows partition made `Restore.ps1` stop with no way forward; it now accepts `-RecoveryPassword` (or prompts), unlocks in WinPE, and still writes nothing if the key is missing, malformed or wrong.
- After a restore with the recovery entry installed, `Restore.ps1` always re-created the entry although `bcdboot` had kept it, leaving **two** identical entries; it now re-creates it only if the recorded entry is missing.
- Metadata read the Windows version of the running OS (WinPE); it now reads the captured system's kernel version.
- The harness itself had several bugs (strict-mode `Count`, a `$dl:` parse error, results wiped between stages, a BOM breaking a Python helper). Two reruns produced stale logs; they were discarded and rerun from a clean snapshot. A BCD polluted by an earlier test also produced two false failures before the clean rerun.

## Not verified

Windows 11; TPM-bound BitLocker (and the recovery prompt that changing the boot configuration can trigger with it); a BitLocker-locked backup partition; power loss at other restore stages; low space in a real capture; physical hardware and real storage drivers; application-level state after restore (only login and file markers were checked); the re-creation branch of `Restore.ps1` (entry missing after `bcdboot`), which never ran because `bcdboot` kept the entry; the data-partition hash check after the *second* restore cycle (it was checked after the first, which used the same code path); building the WinPE with `Build-WinPE.ps1` (these runs reused an existing WinPE image); the WPF restore points page driving the scripts.
