# Uninstall research

[Bulk Crap Uninstaller](https://github.com/BCUninstaller/Bulk-Crap-Uninstaller) is an Apache-2.0 Windows uninstaller. Its source separates application discovery, uninstall execution, leftover scanners and confidence evaluation (`source/UninstallTools/Junk`). It also has separate handling for several application formats. Its command-line tool describes leftover cleanup following uninstall; this does not establish that it can safely satisfy RestoreNest's requested direct forced removal of every selected product.

RestoreNest should keep discovery and removal separate, show the evidence for candidate resources, and never infer ownership solely from an uninstall registry entry or a matching directory name. Product-specific 360 rules require real installer samples and isolated test machines. In particular, a shared location or a system folder must not be deleted just because a selected application mentions it.

No BCUninstaller code is bundled here. Before reuse, review the project and individual dependencies' licenses and preserve required notices; before enabling removal, test normal, shared, protected, locked and self-protected installations in disposable Windows environments.
