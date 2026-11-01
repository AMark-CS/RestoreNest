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
