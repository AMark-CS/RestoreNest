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
