# Uninstall research

[Bulk Crap Uninstaller](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller) is an Apache-2.0 Windows uninstaller. Its source separates application discovery, uninstall execution, leftover scanners and confidence evaluation (`source/UninstallTools/Junk`). It also has separate handling for several application formats. Its command-line tool describes leftover cleanup following uninstall; this does not establish that it can safely satisfy RestoreNest's requested direct forced removal of every selected product.

RestoreNest should keep discovery and removal separate, show the evidence for candidate resources, and never infer ownership solely from an uninstall registry entry or a matching directory name. Product-specific 360 rules require real installer samples and isolated test machines. In particular, a shared location or a system folder must not be deleted just because a selected application mentions it.

No BCUninstaller code is bundled here. Before reuse, review the project and individual dependencies' licenses and preserve required notices; before enabling removal, test normal, shared, protected, locked and self-protected installations in disposable Windows environments.

## Source inspection, 2026-10-29

The upstream [JunkManager implementation](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/JunkManager.cs) sets up scanners with the complete application inventory, merges duplicate results and confidence evidence, and filters prohibited locations and resources belonging to BCU itself. These are useful design references, not proof of correct ownership for a 360 sample.

The [UninstallTools project](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/UninstallTools.csproj) references KlocTools, ObjectListView, System.Management, TaskScheduler and a Scripting COM component. Directly importing only JunkManager would therefore not produce a working cleanup engine. No upstream code has been copied or linked into RestoreNest.

The next removal acceptance case must start with a fully installed, recorded 360 version. The existing guest only establishes a signed executable's presence; its uninstall registration was absent. A before/after inventory must cover files, services/drivers, scheduled tasks, startup entries and registry resources, distinguish shared components used by unselected products, and verify removal after reboot before product-specific rules can be enabled.

`tools/Get-QihooEvidence.ps1 -OutputPath <file>` is a read-only candidate collector for that VM. It records matching uninstall entries, service/driver properties, scheduled tasks, and file metadata under selected 360 directories. Its name-based matches are not proof of ownership and it does not collect all registry, per-user, startup, network or filesystem locations. Uninstall registry read errors mark the snapshot incomplete. The output may contain machine names, paths, task arguments and uninstall commands, so keep it local and review it before sharing. Run before and after installation on a disposable VM; no cleanup rules should be inferred without manual verification.

`tools/Compare-QihooEvidence.ps1 -BeforePath <file> -AfterPath <file>` compares candidate identities from two schema-3 captures of the same machine. It rejects incomplete captures or categories and reports added and removed candidate paths, registry entries, services and tasks. It does not check file contents or prove that an item belongs to a product. Older captures must be recaptured; they do not include the completeness flag.

## Isolated sample, 2026-10-30

An offline Windows 10 evaluation VM ran a signed 360 installer with `/S`. The installer returned exit code 1, so successful installation is not established. An independently collected after-snapshot nevertheless contained an uninstall entry for 360安全卫士 13.0.1.2006, ten matching service or driver entries and 1,339 matching files; the same collector found none of those candidates before installation. The capture covered only the locations described above, and neither the count nor a matching name establishes exclusive ownership. The test did not execute removal or verify reboot after removal.

The guest harness also printed zero matching registrations, conflicting with the independently collected uninstall entry. Treat that check as unreliable until its encoding and matching are fixed; do not use it as an installation-success criterion. The local VM snapshots and logs contain machine-specific details and are not included in the repository.

An offline experiment on a disposable difference disk removed the sample's `360Safe` directory and set nine observed service/driver registry entries to disabled. A separate read-only audit confirmed those nine start values and found that the uninstall registration remained. The tenth observed driver, `360Sensor`, had no matching registry key in the audited control sets; its status after boot is not yet known. The modified system subsequently reached the Windows lock screen, but login and post-boot service behavior have not been checked. The experiment intentionally leaves other files and registration data, is not a complete uninstall, and is not connected to the application. A fresh post-boot inventory is still required.
