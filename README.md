# RestoreNest

Windows 10/11 system maintenance and recovery project. **Early development preview, not a backup or recovery product.**

The current build provides a bilingual (简体中文 / English) inventory of registered desktop applications, selection retained across searches, a read-only location review for selected apps, and backup destination format and free-space information. The review is conservative: registry locations do not establish ownership, and all results remain unverified. It does not remove applications, create backups, restore a system, modify boot configuration, or create recovery media. Do not rely on it to protect data.

Requires .NET 8 SDK and Windows Desktop runtime. Build with `dotnet build src/SystemCare` and run the path validation checks with `dotnet run --project tests/SystemCare.Tests`.

## 安全说明

目前仅能查看已登记的桌面软件、只读检查所选软件的安装位置，并查看备份路径格式及磁盘可用空间。安装位置来自注册表，不能证明文件归属，检查结果均不代表可安全删除。强制删除、360 专项适配、系统备份、系统恢复、启动菜单和恢复 U 盘均未实现。请勿将本项目用于保护或恢复实际数据。
