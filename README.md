# RestoreNest

Windows 10/11 maintenance tool: **manage installed software and disk space, and create restore points you can boot into a recovery environment to restore.**

**Version 0.1.0: first runnable preview.** Parts are verified, parts are not; read "Status" before trusting it with data.

## What it does

| Area | Feature | Status |
|---|---|---|
| Apps | List registry and Store apps with size, publisher, version; search; multi-select | Built, unit-tested, app launch smoke-tested |
| Apps | Uninstall selected (MSI, registered uninstallers, Store apps); tries a Windows restore point first; lists leftover-folder candidates for you to confirm | Built and unit-tested; **not yet exercised against real installers in a VM** |
| Disks | Per-drive total / used / free overview | Built, tested |
| Restore points | Create a WIM image of the Windows partition (VSS snapshot online, or offline from WinPE) to **any non-Windows NTFS drive or folder (D:, E:, same physical disk allowed)**; several points coexist; SHA-256 + `wimlib verify` | **VM-verified offline** (4.5 GiB image, hashes OK). Script logic unit-tested. **Online VSS capture also VM-verified** (captured in the live guest, restored, logged in; the 7,609 s VM time is emulation, not real hardware) |
| Boot menu | `Install-BootEntry.ps1` adds a "RestoreNest Recovery" WinPE ramdisk entry (default OS and menu timeout preserved, BCD backed up first, removable) | **VM-verified**: install, boot into the recovery WinPE, remove. Not tested: keyboard selection in the menu, Secure Boot, BitLocker |
| Restore | `Restore.ps1` (runs in WinPE): verifies the image, resolves the target by GPT GUID, refuses the partition holding the backup, dry-run by default, formats only the Windows partition | **VM-verified once per scenario** (Windows 10, UEFI, same-disk D:): data partition hashes and all partition GUIDs/sizes unchanged, backup still valid, a deliberately unbootable system booted to the lock screen afterwards |
| WinPE | `Build-WinPE.ps1` builds the recovery image with the Windows ADK | Syntax-checked only; the VM tests used a pre-built WinPE with the same components. **Not run** |

Details, durations (QEMU emulation, not hardware speed), the bugs these runs found, and what is still untested: [docs/vm-validation.md](docs/vm-validation.md).

The older `wbadmin` backup page and the read-only recovery-task export remain as an experimental alternative (separate-disk only).

## Status: what "unverified" means

The restore path is the dangerous part. It has now been run end to end in a disposable VM (see below and [docs/vm-validation.md](docs/vm-validation.md)), but only on one Windows 10 image, offline, without Secure Boot or BitLocker, and never on physical hardware. Treat it as **experimental**: never run `Restore.ps1 -Execute` on a machine you cannot rebuild, and do not rely on it as your only backup. Engine notes: [docs/restore-point-engine.md](docs/restore-point-engine.md); acceptance list: [docs/backup-engine.md](docs/backup-engine.md).

## Build and run

Requires the .NET 8 SDK and Windows. The app asks for administrator rights.

```bash
dotnet build src/SystemCare
dotnet run --project tests/SystemCare.Tests
powershell -ExecutionPolicy Bypass -File tests/RestorePoint.Tests.ps1
powershell -ExecutionPolicy Bypass -File tests/RestorePlan.Tests.ps1
```

Restore points need `wimlib-imagex.exe` and `libwim-15.dll` (wimlib 1.14.x, **GPLv3+ for the command-line tool**). They are not in this repository: download them yourself from <https://wimlib.net> and place them in `tools\bin\` (copied next to the app on build). Review the license before redistributing a build that bundles them.

Lab helpers for a Hyper-V test VM are in `tools/lab`.

## 安全说明

0.1.x 是可运行的预览版。软件列表、卸载、磁盘概览可以使用（卸载尚未用真实安装包在虚拟机中验证）。还原流程已在一个 Windows 10 虚拟机中端到端跑通：同一块盘上的 D 盘数据和分区布局保持不变，被破坏的系统还原后能启动到锁屏；启动菜单项可安装、可进入恢复环境、可移除。**但仅限一个镜像、离线、无 Secure Boot、无 BitLocker、未在真机验证，请勿用于重要数据。**还原脚本默认只做预检（不写入），仅格式化原 Windows 分区，不会触碰保存还原点的分区。使用 BitLocker 时，修改启动配置可能触发恢复密钥提示，请先备份密钥。wimlib 采用 GPLv3+，需自行下载放入 `tools\bin`。

## Legacy: experimental manifest verification

The verifier accepts UTF-8 JSON up to 2 MiB: `{"version":1,"files":[{"path":"image.bin","sha256":"<64 hex chars>"}]}`. Paths are relative to the manifest; traversal, duplicates and reparse points are rejected. It checks files against the manifest only, not manifest origin or bootability.
