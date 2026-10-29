# Uninstall research

[Bulk Crap Uninstaller](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller) is an Apache-2.0 Windows uninstaller. Its source separates application discovery, uninstall execution, leftover scanners and confidence evaluation (`source/UninstallTools/Junk`). It also has separate handling for several application formats. Its command-line tool describes leftover cleanup following uninstall; this does not establish that it can safely satisfy RestoreNest's requested direct forced removal of every selected product.

RestoreNest should keep discovery and removal separate, show the evidence for candidate resources, and never infer ownership solely from an uninstall registry entry or a matching directory name. Product-specific 360 rules require real installer samples and isolated test machines. In particular, a shared location or a system folder must not be deleted just because a selected application mentions it.

No BCUninstaller code is bundled here. Before reuse, review the project and individual dependencies' licenses and preserve required notices; before enabling removal, test normal, shared, protected, locked and self-protected installations in disposable Windows environments.

## Source inspection, 2026-10-29

The upstream [JunkManager implementation](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/Junk/JunkManager.cs) sets up scanners with the complete application inventory, merges duplicate results and confidence evidence, and filters prohibited locations and resources belonging to BCU itself. These are useful design references, not proof of correct ownership for a 360 sample.

The [UninstallTools project](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller/blob/master/source/UninstallTools/UninstallTools.csproj) references KlocTools, ObjectListView, System.Management, TaskScheduler and a Scripting COM component. Directly importing only JunkManager would therefore not produce a working cleanup engine. No upstream code has been copied or linked into RestoreNest.

The next removal acceptance case must start with a fully installed, recorded 360 version. The existing guest only establishes a signed executable's presence; its uninstall registration was absent. A before/after inventory must cover files, services/drivers, scheduled tasks, startup entries and registry resources, distinguish shared components used by unselected products, and verify removal after reboot before product-specific rules can be enabled.
