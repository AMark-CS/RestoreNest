using Microsoft.Win32;

namespace SystemCare;

public record InstalledApp(string Name, string Publisher, string Version, string Location, Guid? MsiProductCode = null);

public static class InstalledApps
{
    public static List<InstalledApp> Get()
    {
        var apps = new List<InstalledApp>();
        foreach (var hive in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
        foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var root = RegistryKey.OpenBaseKey(hive, view);
            using var uninstall = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall");
            if (uninstall is null) continue;
            foreach (var name in uninstall.GetSubKeyNames())
            {
                try
                {
                    using var item = uninstall.OpenSubKey(name);
                    var display = item?.GetValue("DisplayName") as string;
                    if (string.IsNullOrWhiteSpace(display) || Convert.ToInt32(item?.GetValue("SystemComponent") ?? 0) == 1) continue;
                    apps.Add(new(display, item?.GetValue("Publisher") as string ?? "", item?.GetValue("DisplayVersion") as string ?? "", item?.GetValue("InstallLocation") as string ?? "", MsiUninstall.ProductCode(name, item?.GetValue("WindowsInstaller"))));
                }
                catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException or FormatException or InvalidCastException or OverflowException or System.IO.IOException) { }
            }
        }
        return apps.Distinct().OrderBy(x => x.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
    }
}
