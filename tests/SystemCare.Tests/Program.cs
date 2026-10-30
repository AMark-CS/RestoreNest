using SystemCare;

static void Check(bool condition, string name)
{
    if (!condition) throw new Exception(name);
}

Check(BackupLocation.Validate(@"D:\Backups", @"C:\") == null, "separate partition");
Check(BackupLocation.Validate(@"C:\Backups", @"C:\") != null, "source partition rejected");
Check(BackupLocation.Validate(@"D:Backups", @"C:\") != null, "relative path rejected");
Check(BackupLocation.Validate(@"\\server\share\backups", @"C:\") != null, "network path rejected");
Check(BackupLocation.Validate("", @"C:\") != null, "empty path rejected");
Console.WriteLine("Backup path checks passed.");

var protectedPaths = new[] { @"C:\Windows", @"C:\Program Files", @"C:\Users" };
Check(RemovalReview.Assess(@"C:\Windows\System32", Array.Empty<string>(), protectedPaths) == "protected", "system folder protected");
Check(RemovalReview.Assess(@"C:\Program Files", Array.Empty<string>(), protectedPaths) == "protected", "program files root protected");
Check(RemovalReview.Assess(@"C:\", Array.Empty<string>(), protectedPaths) == "root", "drive root protected");
Check(RemovalReview.Assess(@"C:\Apps\Example", new[] { @"C:\Apps\Example\Other" }, protectedPaths) == "shared", "nested application protected");
Check(RemovalReview.Assess(@"C:\Apps\Example", new[] { @"c:\apps\example" }, protectedPaths) == "shared", "shared application protected");
Check(RemovalReview.Assess(@"C:\Apps\Example", new[] { @"C:\Apps\Example2" }, protectedPaths) == "unverified", "similar prefix is not shared");
Check(RemovalReview.Assess(@"relative\path", Array.Empty<string>(), protectedPaths) == "unknown", "relative location rejected");
Console.WriteLine("Removal review checks passed.");

var choices = new[] { new AppChoice(new InstalledApp("Alpha", "Vendor", "1", "")), new AppChoice(new InstalledApp("Beta", "Vendor", "1", "")) };
choices[0].IsSelected = true;
var filtered = choices.Where(c => c.App.Name.Contains("Beta")).ToList();
filtered[0].IsSelected = true;
Check(choices.Count(c => c.IsSelected) == 2, "selection persists across filtering");
Console.WriteLine("App selection checks passed.");

Check(QihooIdentification.IsCandidate("360安全卫士 版本 1"), "360 security candidate");
Check(QihooIdentification.IsCandidate("360 Total Security"), "360 English candidate");
Check(!QihooIdentification.IsCandidate("My 360安全卫士 unrelated"), "substring is not product name");
Check(!QihooIdentification.IsCandidate("360度全景工具"), "unrelated 360 app excluded");
Console.WriteLine("360 candidate checks passed.");

var productCode = "{AAD3D77A-7476-469F-ADF4-04424124E91D}";
Check(MsiUninstall.ProductCode(productCode, 1) == Guid.Parse(productCode), "registered MSI product recognized");
Check(MsiUninstall.ProductCode(productCode, 0) is null, "non-MSI registration rejected");
Check(MsiUninstall.ProductCode(productCode, "1") is null, "malformed installer flag rejected");
Check(MsiUninstall.ProductCode("not-a-guid", 1) is null, "invalid MSI product rejected");
Check(MsiUninstall.ProductCode(Guid.Empty.ToString("B"), 1) is null, "empty product rejected");
Check(MsiUninstall.BuildArguments(Guid.Parse(productCode)).SequenceEqual(new[] { "/x", productCode, "/qn", "/norestart" }), "safe MSI uninstall arguments");
try { MsiUninstall.BuildArguments(Guid.Empty); throw new Exception("empty MSI product accepted"); }
catch (ArgumentException) { }
Console.WriteLine("MSI uninstall command checks passed.");

var backupArguments = WbadminBackup.BuildArguments(@"D:\", @"C:\");
Check(backupArguments.SequenceEqual(new[] { "start", "backup", "-backupTarget:D:", "-allCritical", "-vssCopy", "-quiet" }), "wbadmin arguments");
foreach (var invalid in new[] { @"D:\Folder", @"C:\", @"\\server\share", @"D:relative", "" })
{
    try { WbadminBackup.BuildArguments(invalid, @"C:\"); throw new Exception("unsafe backup target accepted: " + invalid); }
    catch (ArgumentException) { }
}
try { WbadminBackup.BuildArguments(@"D:\", ""); throw new Exception("unknown system volume accepted"); }
catch (ArgumentException) { }
Console.WriteLine("Backup command checks passed.");

Check(RecoveryCatalog.BuildArguments(@"D:\").SequenceEqual(new[] { "get", "versions", "-backupTarget:D:" }), "recovery catalog arguments");
foreach (var invalid in new[] { @"D:\Folder", @"\\server\share", @"D:relative", "" })
{
    try { RecoveryCatalog.BuildArguments(invalid); throw new Exception("unsafe catalog target accepted: " + invalid); }
    catch (ArgumentException) { }
}
Console.WriteLine("Recovery catalog checks passed.");
var catalog = "Backup time: 10/29/2026 2:53 AM\nVersion identifier: 10/29/2026-09:53\n版本标识符: 11/30/2026-23:59\nVersion identifier: 02/30/2026-09:53\nVersion identifier: 10/29/2026-09:53\n";
Check(RecoveryCatalog.ParseVersions(catalog).SequenceEqual(new[] { "10/29/2026-09:53", "11/30/2026-23:59" }), "only valid unique version identifiers are listed");
Check(RecoveryCatalog.ParseVersions("Error 10/29/2026-09:53 extra\n").Count == 0, "unstructured output is not a version");
Console.WriteLine("Recovery version parsing checks passed.");
var sourceVolume = new RecoveryVolume(Guid.NewGuid(), Guid.NewGuid());
var targetVolume = new RecoveryVolume(Guid.NewGuid(), Guid.NewGuid());
var recoveryTask = new RecoveryTask(1, "10/29/2026-09:53", "RN-VM", sourceVolume, targetVolume);
recoveryTask.Validate();
foreach (var invalidTask in new[] { recoveryTask with { Version = "02/30/2026-09:53" }, recoveryTask with { Schema = 2 }, recoveryTask with { Machine = "bad & name" }, recoveryTask with { Windows = sourceVolume }, recoveryTask with { Backup = sourceVolume with { Partition = Guid.Empty } } })
{
    try { invalidTask.Validate(); throw new Exception("invalid recovery task accepted"); }
    catch (ArgumentException) { }
}
Check(System.Text.Json.JsonSerializer.Deserialize<RecoveryTask>(System.Text.Json.JsonSerializer.Serialize(recoveryTask)) == recoveryTask, "recovery task round trip preserves identities");
Console.WriteLine("Recovery task checks passed.");

var fixture = Path.Combine(Path.GetTempPath(), "restorenest-test-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(fixture);
try
{
    var file = Path.Combine(fixture, "image.bin");
    File.WriteAllText(file, "known backup data");
    var hash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(file)));
    var manifest = new BackupManifest(1, new[] { new BackupFile("image.bin", hash) });
    Check(BackupVerification.Verify(fixture, manifest), "valid backup verifies");
    File.WriteAllText(file, "changed");
    Check(!BackupVerification.Verify(fixture, manifest), "modified backup rejected");
    Check(!BackupVerification.Verify(fixture, new BackupManifest(1, new[] { new BackupFile("../outside", hash) })), "traversal rejected");
    Check(!BackupVerification.Verify(fixture, new BackupManifest(1, new[] { new BackupFile("missing.bin", hash) })), "missing file rejected");
    Check(!BackupVerification.Verify(fixture, new BackupManifest(1, new[] { new BackupFile("image.bin", "not-a-hash") })), "invalid hash rejected");
    Check(!BackupVerification.Verify(fixture, new BackupManifest(1, new[] { new BackupFile("image.bin", hash), new BackupFile("IMAGE.BIN", hash) })), "duplicate paths rejected");
    Check(!BackupVerification.Verify(fixture, new BackupManifest(1, Array.Empty<BackupFile>())), "empty manifest rejected");
    Check(!BackupVerification.Verify(fixture, new BackupManifest(2, new[] { new BackupFile("image.bin", hash) })), "unknown version rejected");
    Console.WriteLine("Backup integrity checks passed.");
}
finally { Directory.Delete(fixture, true); }
