# Restore point engine (Phase 2, experimental)

`tools/New-RestorePoint.ps1` captures the Windows partition into `<dest>\RestoreNest\<yyyyMMdd-HHmmss>\system.wim` using `wimlib-imagex capture --snapshot` (VSS) and writes `meta.json` (source disk/partition GUIDs, WIM SHA-256 and size). `tools/Get-RestorePoint.ps1 [-Verify]` lists and verifies points. Several restore points coexist; the backup may be on another partition of the same physical disk, never on the Windows partition.

Status: the PowerShell logic is covered by `tests/RestorePoint.Tests.ps1` using a **stub** wimlib. No real capture has been run yet.

## Before relying on it

1. Obtain `wimlib-imagex.exe` (amd64), put it in `tools\bin\` (git-ignored), and confirm the license terms for redistribution.
2. In the lab VM (`tools/lab`), as administrator: `.\tools\New-RestorePoint.ps1 -Destination D:\ -Name test1`. Expect `system.wim` and `meta.json`; record the duration and WIM size.
3. Run it again; two points must be listed and `.\tools\Get-RestorePoint.ps1 -Destination D:\ -Verify -WimlibPath ...` must report `ok` for both.
4. Write to C: during the capture and confirm the image is still a consistent snapshot (open it with `wimlib-imagex info`/`dir`).
5. Interrupt a capture (power off the VM) and confirm only a `*.partial` folder remains and is not listed.

Capture does not prove the image can be restored; that is Phase 4.
