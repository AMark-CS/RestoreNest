# RestoreNest

Windows 10/11 system maintenance and recovery project. **Early development preview, not a backup or recovery product.**

The current build provides a bilingual (简体中文 / English) inventory of registered desktop applications, a name-only filter for possible 360 products, selection retained across searches, a read-only location review, backup destination information, a read-only Windows backup catalog query and version selection by drive root, and experimental SHA-256 manifest verification. Selecting a version does not perform recovery. The review is conservative: names and registry locations do not establish ownership. It does not remove applications, create backups, restore a system, modify boot configuration, or create recovery media. Do not rely on it to protect data.

Requires .NET 8 SDK and Windows Desktop runtime. Build with `dotnet build src/SystemCare` and run the path validation checks with `dotnet run --project tests/SystemCare.Tests`.

The recovery page also exports an experimental JSON task containing the selected version and GPT disk/partition identities. This does not perform recovery. See [recovery handoff](docs/recovery-handoff.md) for the read-only preflight and outstanding validation.

## 安全说明

目前可查看已登记的桌面软件、按名称筛选可能的 360 产品、只读检查安装位置、查看备份目标信息、按盘符只读查询并选择 Windows 备份版本，以及试验性校验 SHA-256 清单。选择版本不会执行恢复。名称和注册表位置不能证明文件归属，校验通过也不代表镜像可以恢复或启动。强制删除、360 专项适配、系统备份、系统恢复、启动菜单和恢复 U 盘均未实现。请勿将本项目用于保护或恢复实际数据。

## Experimental manifest / 试验性清单

The verifier accepts UTF-8 JSON up to 2 MiB, in the following format. Paths are relative to the directory containing the manifest; traversal, duplicate paths and reparse points are rejected. This format is experimental and the application does not yet create these files.

校验器接受不超过 2 MiB 的 UTF-8 JSON，文件路径相对清单所在目录；路径越界、重复路径和重解析点会被拒绝。哈希只检查文件是否与清单一致，并不验证清单来源或镜像可启动性。此格式尚处于试验阶段，应用暂不能生成清单。

```json
{"version":1,"files":[{"path":"image.bin","sha256":"<64 hexadecimal SHA-256 characters>"}]}
```
