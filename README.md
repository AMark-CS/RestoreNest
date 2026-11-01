# RestoreNest

Windows 10/11 maintenance tool: **manage installed software and disk space, and create restore points you can boot into a recovery environment to restore.**

**Version 0.1.0: first runnable preview.** Parts are verified, parts are not; read "Status" before trusting it with data.

## What it does

| Area | Feature | Status |
|---|---|---|
| Apps | List registry and Store apps with size, publisher, version; search; multi-select | Built, unit-tested, app launch smoke-tested |
| Apps | Uninstall selected (MSI, registered uninstallers, Store apps); tries a Windows restore point first; lists leftover-folder candidates for you to confirm | Built and unit-tested; **not yet exercised against real installers in a VM** |
| Disks | Per-drive total / used / free overview | Built, tested |
| Restore points | Create a VSS-consistent WIM image of the Windows partition to **any non-Windows NTFS drive or folder (D:, E:, same physical disk allowed)**; several points coexist; SHA-256 + `wimlib verify` | Script logic tested with a stub; wimlib capture/apply round trip verified on scratch folders; **a real VSS capture of a Windows system has not been run** |
| Boot menu | `Install-BootEntry.ps1` adds a "RestoreNest Recovery" WinPE ramdisk entry (default OS unchanged, BCD exported first, removable) | Command generation tested in dry run; **never run against a real BCD or booted** |
| Restore | `Restore.ps1` (runs in WinPE): verifies the image, resolves the target by GPT GUID, refuses the partition holding the backup, dry-run by default, formats only the Windows partition | Planning logic tested; **the write path (format / apply / bcdboot) has never been run** |
| WinPE | `Build-WinPE.ps1` builds the recovery image with the Windows ADK | Syntax-checked only; needs the ADK, **not run** |

The older `wbadmin` backup page and the read-only recovery-task export remain as an experimental alternative (separate-disk only).

## Status: what "unverified" means

The restore path is the dangerous part. Until it has been exercised end to end in a disposable VM with `D:` data hashed before and after, treat **creating** restore points as the usable feature and **restoring** as experimental. Never run `Restore.ps1 -Execute` on a machine you cannot rebuild. See [docs/restore-point-engine.md](docs/restore-point-engine.md) and the VM acceptance list in [docs/backup-engine.md](docs/backup-engine.md).

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

0.1.0 是首个可运行预览版。软件列表、卸载、磁盘概览和“创建还原点”可以使用（卸载与真实系统映像尚未在虚拟机中完整验证）；**还原（启动菜单 + WinPE）从未在虚拟机中实际写盘验证，请勿用于重要数据**。还原脚本默认只做预检（不写入），仅格式化原 Windows 分区，不会触碰保存还原点的分区。使用 BitLocker 时，修改启动配置可能触发恢复密钥提示，请先备份密钥。wimlib 采用 GPLv3+，需自行下载放入 `tools\bin`。

## Legacy: experimental manifest verification

The verifier accepts UTF-8 JSON up to 2 MiB: `{"version":1,"files":[{"path":"image.bin","sha256":"<64 hex chars>"}]}`. Paths are relative to the manifest; traversal, duplicates and reparse points are rejected. It checks files against the manifest only, not manifest origin or bootability.
