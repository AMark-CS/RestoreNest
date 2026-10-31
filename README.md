# RestoreNest

Windows 10/11 system maintenance and recovery project. **Early development preview, not a backup or recovery product.**

The current build provides a bilingual (简体中文 / English) inventory of registered desktop applications, a name-only filter for possible 360 products, selection retained across searches, a read-only location review, a read-only Windows backup catalog query and version selection by drive root, and experimental SHA-256 manifest verification. The backup page can invoke Windows Backup to create an experimental system image on a local NTFS drive root; it refuses a target with an existing `WindowsImageBackup` folder and requires administrator privileges. Selecting a version does not perform recovery. Names and registry locations do not establish ownership. The app does not remove applications, restore a system, modify boot configuration, or create recovery media. Its backup interface has not yet been tested end to end in the VM; do not rely on this preview to protect data.

Requires .NET 8 SDK and Windows Desktop runtime. Build with `dotnet build src/SystemCare` and run the path validation checks with `dotnet run --project tests/SystemCare.Tests`.

The recovery page also exports an experimental JSON task containing the selected version and GPT disk/partition identities. This does not perform recovery. See [recovery handoff](docs/recovery-handoff.md) for the read-only preflight and outstanding validation.

## 安全说明

目前可查看已登记的软件、筛选可能的 360 产品、只读检查安装位置、查询备份版本，以及试验性校验 SHA-256 清单。备份页面可调用 Windows 备份创建试验性系统映像，需要管理员权限和本地 NTFS 卷根目录；已有 `WindowsImageBackup` 的目标会被拒绝。选择版本不会执行恢复。强制删除、360 专项适配、系统恢复、启动菜单和恢复 U 盘均未完成。备份界面尚未经虚拟机端到端测试，请勿依赖此预览版保护或恢复实际数据。

## Experimental manifest / 试验性清单

The verifier accepts UTF-8 JSON up to 2 MiB, in the following format. Paths are relative to the directory containing the manifest; traversal, duplicate paths and reparse points are rejected. This format is experimental and the application does not yet create these files.

校验器接受不超过 2 MiB 的 UTF-8 JSON，文件路径相对清单所在目录；路径越界、重复路径和重解析点会被拒绝。哈希只检查文件是否与清单一致，并不验证清单来源或镜像可启动性。此格式尚处于试验阶段，应用暂不能生成清单。

```json
{"version":1,"files":[{"path":"image.bin","sha256":"<64 hexadecimal SHA-256 characters>"}]}
```
