# VM validation record (2026-11-01)

This records what was actually run, so the README claims can be checked. Everything here is one Windows 10 Enterprise Evaluation 22H2 guest, one image, one run per item, under QEMU **software emulation (TCG)**, UEFI without Secure Boot, no BitLocker. Durations are emulation times, not hardware benchmarks.

## Method

- Disposable qcow2 overlay on the existing Windows 10 base image; one GPT disk, 96 GiB: EFI, MSR, Windows, Recovery.
- WinPE (Windows 10 2004 setup `boot.wim` with PowerShell and Storage, already used in earlier tests) booted from a FAT USB image. A harness script on a small results disk ran one stage per boot (info, prep, baseline, capture, mutate, restore, verify, bootentry, bootremove) and wrote logs and `RN_CHECK … PASS/FAIL` lines back for the host to read.
- The harness and the QEMU launch scripts live outside the repository (they contain machine-specific paths). The product scripts under `tools/` were the ones executed, unmodified apart from the fixes listed below.
- Capture was **offline** (`-NoSnapshot`) because WinPE has no VSS. A live VSS capture has not been run.

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

## Bugs found by these runs (all fixed)

- `bcdedit /store <file> /export` is rejected; offline stores are now backed up by copying the file.
- The installer forced the menu timeout to 10 s and never restored it; it now leaves a non-zero timeout alone and records/restores the original if it had to enable the menu.
- `Restore.ps1` would stop if `manage-bde` was absent; it now warns.
- After a restore with the recovery entry installed, `Restore.ps1` always re-created the entry although `bcdboot` had kept it, leaving **two** identical entries; it now re-creates it only if the recorded entry is missing.
- Metadata read the Windows version of the running OS (WinPE); it now reads the captured system's kernel version.
- The harness itself had several bugs (strict-mode `Count`, a `$dl:` parse error, results wiped between stages, a BOM breaking a Python helper). Two reruns produced stale logs; they were discarded and rerun from a clean snapshot. A BCD polluted by an earlier test also produced two false failures before the clean rerun.

## Not verified

Live VSS capture; Windows 11; Secure Boot; BitLocker/TPM; interrupted capture or restore; low space; physical hardware and real storage drivers; selecting the entry with the keyboard in the boot menu; logging in after restore or checking application state; the re-creation branch of `Restore.ps1` (entry missing after `bcdboot`), which never ran because `bcdboot` kept the entry; the data-partition hash check after the *second* restore cycle (it was checked after the first, which used the same code path); building the WinPE with `Build-WinPE.ps1` (this run reused an existing WinPE image); the WPF restore points page driving the scripts.
