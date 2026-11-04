using SystemCare;

static void Check(bool condition, string name)
{
    if (!condition) throw new Exception(name);
}


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


// Phase 1: uninstall planning, app roots, disk overview
Check(RemovalReview.Assess(@"C:\Program Files\Example", Array.Empty<string>(), new[] { @"C:\Windows" }, new[] { @"C:\Program Files" }) == "unverified", "app under Program Files is reviewable");
Check(RemovalReview.Assess(@"C:\Program Files", Array.Empty<string>(), new[] { @"C:\Windows" }, new[] { @"C:\Program Files" }) == "protected", "Program Files itself protected");
Check(RemovalReview.Assess(@"C:\Users\x\AppData", Array.Empty<string>(), Array.Empty<string>(), new[] { @"C:\Users\x\AppData\Roaming" }) == "protected", "parent of protected root protected");
Check(Uninstaller.Parse("\"C:\\Program Files\\App\\unins000.exe\" /SILENT") is { File: @"C:\Program Files\App\unins000.exe", Args: "/SILENT" }, "quoted uninstall command parsed");
Check(Uninstaller.Parse(@"C:\Apps\un.exe -x") is { File: @"C:\Apps\un.exe", Args: "-x" }, "unquoted uninstall command parsed");
Check(Uninstaller.Parse(@"cmd /c del x") is null, "non-absolute command rejected");
Check(Uninstaller.Parse(@"\server\share\un.exe") is null, "network uninstaller rejected");
Check(Uninstaller.Parse("") is null, "empty command rejected");
var msiApp = new InstalledApp("M", "", "", "", Guid.Parse(productCode));
Check(Uninstaller.Plan(msiApp)!.Arguments == "/x " + productCode + " /qn /norestart", "MSI plan is silent uninstall");
var verbApp = new InstalledApp("V", "", "", "", null, @"MsiExec.exe /I{AAD3D77A-7476-469F-ADF4-04424124E91D}");
Check(Uninstaller.Plan(verbApp)!.Arguments.StartsWith("/X{"), "install verb converted to uninstall");
var quietApp = new InstalledApp("Q", "", "", "", null, @"C:\A\u.exe", @"C:\A\u.exe /S");
Check(Uninstaller.Plan(quietApp) is { Silent: true, Arguments: "/S" }, "quiet command preferred");
Check(Uninstaller.Plan(new InstalledApp("N", "", "", "")) is null, "no command, no plan");
Check(DiskOverview.FormatBytes(1536) == "1.5 KiB" && DiskOverview.FormatBytes(0) == "0 B", "size formatting");
Check(new DiskVolume(@"C:\", "", "NTFS", 200, 50, "Fixed").UsedPercent == 75, "used percentage");
Check(DiskOverview.Get().Count > 0, "at least one drive listed");
{
    // An installer that records no InstallLocation: the folder holding its uninstaller is offered, but only inside an application folder.
    var programs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs");
    var holder = Path.Combine(programs, "RnLeftoverTest-" + Guid.NewGuid().ToString("N"));
    var temp = Path.Combine(Path.GetTempPath(), "RnLeftoverTemp-" + Guid.NewGuid().ToString("N"));
    try
    {
        Directory.CreateDirectory(holder); Directory.CreateDirectory(temp);
        InstalledApp Make(string folder) => new("Rn Leftover Test", "Nobody", "1.0", "", null, "\"" + Path.Combine(folder, "uninstall.exe") + "\"", "", 0, "");
        var windows = new[] { Environment.GetFolderPath(Environment.SpecialFolder.Windows) };
        var found = LeftoverScanner.Scan(Make(holder), Array.Empty<string>(), windows, Array.Empty<string>());
        Check(found.Any(f => string.Equals(f.Path, holder, StringComparison.OrdinalIgnoreCase)), "leftover folder is found from the uninstaller's path when InstallLocation is empty");
        Check(!LeftoverScanner.Scan(Make(temp), Array.Empty<string>(), windows, Array.Empty<string>()).Any(f => string.Equals(f.Path, temp, StringComparison.OrdinalIgnoreCase)), "a folder outside the application folders is never offered that way");
        Check(!LeftoverScanner.Scan(Make(holder), new[] { holder }, windows, Array.Empty<string>()).Any(), "a folder another app uses is not offered");
    }
    finally { if (Directory.Exists(holder)) Directory.Delete(holder, true); if (Directory.Exists(temp)) Directory.Delete(temp, true); }
}
{
    var hardware = DiskOverview.ParseHardware("[{\"letter\":\"C\",\"disk\":2,\"model\":\"WD Blue SN570 500GB \",\"media\":\"SSD\",\"bus\":\"NVMe\",\"style\":\"GPT\",\"health\":\"Healthy\",\"size\":500107862016},{\"letter\":\"E\",\"disk\":1,\"model\":\"USB Stick\",\"media\":\"Unspecified\",\"bus\":\"USB\",\"style\":\"MBR\",\"health\":\"Healthy\",\"size\":1}]");
    Check(hardware.Count == 2 && hardware[@"C:\"].DiskNumber == 2 && hardware[@"C:\"].Model == "WD Blue SN570 500GB" && hardware[@"C:\"].Kind == "NVMe SSD" && hardware[@"E:\"].Kind == "USB", "disk hardware JSON is parsed (array form)");
    Check(DiskOverview.ParseHardware("{\"letter\":\"D\",\"disk\":0,\"model\":\"X\",\"media\":\"HDD\",\"bus\":\"SATA\",\"style\":\"GPT\",\"health\":\"Healthy\",\"size\":5}")[@"D:\"].Kind == "HDD", "disk hardware JSON is parsed (single object form)");
    Check(DiskOverview.ParseHardware("not json").Count == 0 && DiskOverview.ParseHardware("").Count == 0, "bad disk hardware output gives an empty map");
    Check(DiskOverview.KindOf("Unspecified", "SATA") == "SATA" && DiskOverview.KindOf("", "Unknown") == "" && DiskOverview.KindOf("SSD", "USB") == "USB SSD", "disk kind names");
    var shown = new DiskVolume(@"C:\", "Base", "NTFS", 200, 20, "Fixed") { Hardware = hardware[@"C:\"], RestorePoints = 2, RestorePointBytes = 2048 };
    Check(shown.IsCritical && !shown.IsWarning && new DiskVolume(@"D:\", "", "NTFS", 100, 20, "Fixed").IsWarning, "usage tiers: warning from 75%, critical from 90%");
    Check(shown.HardwareText.Contains("NVMe SSD") && shown.HardwareText.Contains("GPT") && new DiskVolume(@"D:\", "", "NTFS", 1, 1, "Fixed").HardwareText == "", "hardware line is empty until known");
    Check(shown.RestoreBadge.Contains("2") && new DiskVolume(@"D:\", "", "NTFS", 1, 1, "Fixed").RestoreBadge == "", "restore point badge");
    var tmp = Path.Combine(Path.GetTempPath(), "rn-dv-" + Guid.NewGuid().ToString("N"));
    try
    {
        Directory.CreateDirectory(Path.Combine(tmp, "20261101-020000")); File.WriteAllBytes(Path.Combine(tmp, "20261101-020000", "system.wim"), new byte[100]);
        Directory.CreateDirectory(Path.Combine(tmp, "20261102-020000.partial")); File.WriteAllBytes(Path.Combine(tmp, "20261102-020000.partial", "system.wim"), new byte[50]);
        Directory.CreateDirectory(Path.Combine(tmp, "20261103-020000"));   // no image: not a restore point
        Check(DiskOverview.CountRestorePoints(tmp) == (1, 100) && DiskOverview.CountRestorePoints(Path.Combine(tmp, "missing")) == (0, 0), "restore points are counted per drive (partial and empty folders are not)");
    }
    finally { Directory.Delete(tmp, true); }
}
var appxJson = "[{\"N\":\"Microsoft.Foo\",\"F\":\"Microsoft.Foo_1.0.0.0_x64__8wekyb3d8bbwe\",\"V\":\"1.0.0.0\",\"P\":\"CN=X\"},{\"N\":\"Bad\",\"F\":\"x'; calc; '\",\"V\":\"\",\"P\":\"\"}]";
Check(AppxApps.Parse(appxJson).Count == 1, "appx parsing drops unsafe package names");
Check(AppxApps.Parse("not json").Count == 0, "appx bad json ignored");
Console.WriteLine("Phase 1 checks passed.");

var rpJson = "[{\"Id\":\"20261031-153005\",\"Name\":\"first\",\"CreatedUtc\":\"2026-10-31T07:30:05.0000000Z\",\"SizeGiB\":12.5,\"Status\":\"ok\",\"Path\":\"D:/x\"}]";
var rpList = RestorePoints.ParseList(rpJson);
Check(rpList.Count == 1 && rpList[0].Id == "20261031-153005" && rpList[0].SizeText == "12.5 GiB", "restore point list parsed");
Check(RestorePoints.ParseList("").Count == 0 && RestorePoints.ParseList("not json").Count == 0 && RestorePoints.ParseList("[]").Count == 0, "bad restore point output ignored");
var rpArgs = RestorePoints.BuildScriptArguments("New-RestorePoint.ps1", new[] { "-Destination", "D:; calc" });
Check(rpArgs[^1] == "D:; calc" && rpArgs.Contains("-File"), "script arguments stay separate");
Console.WriteLine("Restore point UI checks passed.");
Check(RestorePoints.IsModuleNoise("VERBOSE: Exporting function 'Get-Disk'.") && !RestorePoints.IsModuleNoise("VERBOSE: Captured in 5 s"), "module import noise filtered from log");

// Automatic protection settings and status
var scheduleTemp = Path.Combine(Path.GetTempPath(), "rn-schedule-test-" + Guid.NewGuid().ToString("N")[..8]);
Environment.SetEnvironmentVariable("RN_DATA", scheduleTemp);
try
{
    Check(AutoProtection.Load() == ScheduleSettings.Default && !AutoProtection.Load().Enabled, "no settings file means switched off");
    var windowsDrive = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows))!;
    var saved = new ScheduleSettings(true, "biweekly", "03:30", "Friday", 15, 5, windowsDrive, false);
    AutoProtection.Save(saved);
    Check(AutoProtection.Load() == saved, "settings round trip through the shared JSON file");
    Check(File.ReadAllText(AutoProtection.SettingsPath).Contains("\"dayOfMonth\"") && File.ReadAllText(AutoProtection.SettingsPath).Contains("\"onlyOnAC\""), "JSON field names match the PowerShell side");
    File.WriteAllText(AutoProtection.SettingsPath, "not json");
    Check(AutoProtection.Load() == ScheduleSettings.Default, "unreadable settings fall back to the default");
}
finally { Environment.SetEnvironmentVariable("RN_DATA", null); if (Directory.Exists(scheduleTemp)) Directory.Delete(scheduleTemp, true); }
var okSettings = ScheduleSettings.Default with { Enabled = false };
Check(okSettings.Validate() is null, "switched-off default is valid without a destination");
Check((okSettings with { Frequency = "hourly" }).Validate() == "frequency" && (okSettings with { Time = "25:00" }).Validate() == "time" && (okSettings with { Time = "2:00" }).Validate() == "time", "bad frequency or time rejected");
Check((okSettings with { DayOfWeek = "Funday" }).Validate() == "day" && (okSettings with { DayOfMonth = 29 }).Validate() == "dayOfMonth", "bad day rejected");
Check((okSettings with { Keep = 0 }).Validate() == "keep" && (okSettings with { Keep = 31 }).Validate() == "keep" && (okSettings with { Keep = 30 }).Validate() is null, "keep must be 1 to 30");
Check((okSettings with { Enabled = true, Destination = "" }).Validate() == "destination:format", "enabled needs a destination");
Check((okSettings with { Enabled = true, Destination = "relative" }).Validate() == "destination:format", "relative destination rejected");
Check(AutoProtection.CheckDestination(Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows))! + "Backups") == "windows-drive", "the Windows partition is rejected");
Check(AutoProtection.CheckDestination("Q:\\") is "not-ready" or "windows-drive", "a missing drive is rejected");
var statusObject = new { registered = true, state = "Ready", nextRunUtc = "2026-11-08T18:00:00.0000000Z", taskAction = "-NoProfile -File \"C:\\App\\tools\\Invoke-ScheduledRestorePoint.ps1\"", last = new { lastRunUtc = "2026-11-01T18:00:00.0000000Z", code = "ok", detail = "20261101-180000", lastSuccessUtc = "2026-11-01T18:00:00.0000000Z", pointCount = 3, removed = Array.Empty<string>() } };
var statusJson = "warning text" + Environment.NewLine + System.Text.Json.JsonSerializer.Serialize(statusObject) + Environment.NewLine;
var parsedStatus = AutoProtection.ParseStatus(statusJson);
Check(parsedStatus is { Registered: true, Last: { Code: "ok", PointCount: 3 } } && AutoProtection.ParseStatus("garbage") is null && AutoProtection.ParseStatus("{broken") is null, "scheduler status parsed");
Check(parsedStatus!.TaskAction!.Contains("Invoke-ScheduledRestorePoint.ps1") && AutoProtection.TaskPointsElsewhere(parsedStatus) == !parsedStatus.TaskAction.Contains(AutoProtection.ScriptPath, StringComparison.OrdinalIgnoreCase), "a task pointing at another copy of the scripts is detected");
var enabledSettings = okSettings with { Enabled = true, Destination = "D:\\" };
Check(AutoProtection.Describe(okSettings, parsedStatus, false).Contains("关闭") && AutoProtection.Describe(okSettings, parsedStatus, true).Contains("off"), "switched-off text in both languages");
Check(AutoProtection.Describe(enabledSettings, parsedStatus, true).Contains("Next automatic restore point") && AutoProtection.Describe(enabledSettings, parsedStatus, false).Contains("成功"), "next run and last success are described");
Check(AutoProtection.Describe(enabledSettings, parsedStatus with { Last = parsedStatus.Last! with { Code = "no-space", Detail = "need 9 GiB" } }, false).Contains("最新的还原点已保留"), "no-space text says the newest point was kept");
Check(AutoProtection.Describe(enabledSettings, parsedStatus with { Registered = false }, true).Contains("Save settings"), "unregistered task asks to save");
Check(AutoProtection.Describe(enabledSettings, null, true).Contains("Could not read"), "unreadable status handled");
Console.WriteLine("Automatic protection checks passed.");

// Recovery setup progress
Check(RestorePoints.ParseStep("RN_STEP 2/5 adk") is (2, 5, "adk") && RestorePoints.ParseStep("RN_STEP 4/5 bootentry") is (4, 5, "bootentry"), "setup steps parsed");
Check(RestorePoints.ParseStep("Downloading the Windows ADK installer") is null && RestorePoints.ParseStep("RN_STEP x/5 adk") is null && RestorePoints.ParseStep("") is null, "other output lines are not steps");
Check(RestorePoints.StepText((2, 5, "adk"), true).StartsWith("[2/5] Installing") && RestorePoints.StepText((2, 5, "adk"), false).Contains("ADK"), "step text in both languages");
Check(RestorePoints.StepText((5, 5, "done"), false) == "[5/5] 完成", "last step text");
Console.WriteLine("Recovery setup progress checks passed.");

// BitLocker help
var goodKey = "398706-073337-291610-054714-140228-593967-459360-006688";
var blJson = "warning text" + Environment.NewLine + System.Text.Json.JsonSerializer.Serialize(new { protectionOn = true, recoveryPasswords = new[] { goodKey, "not-a-key", goodKey } }) + Environment.NewLine;
var bl = BitLockerInfo.Parse(blJson);
Check(bl is { ProtectionOn: true } && bl.ValidPasswords.Length == 1 && bl.ValidPasswords[0] == goodKey, "BitLocker info parsed, junk and duplicates dropped");
Check(BitLockerInfo.Parse("garbage") is null && BitLockerInfo.Parse("{broken") is null && BitLockerInfo.Parse("") is null, "bad BitLocker output ignored");
Check(BitLockerInfo.Parse("{\"protectionOn\":false,\"recoveryPasswords\":[]}") is { ProtectionOn: false, RecoveryPasswords.Length: 0 }, "unprotected drive parsed");
Check(bl!.KeyFileText(true, "C:").Contains(goodKey) && bl.KeyFileText(false, "C:").Contains("BitLocker 恢复密码") && !bl.KeyFileText(true, "C:").Contains("not-a-key"), "key file text holds only valid passwords");
Console.WriteLine("BitLocker help checks passed.");
