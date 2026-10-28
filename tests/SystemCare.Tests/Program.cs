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
