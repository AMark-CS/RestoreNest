using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SystemCare;

// What sits under a drive letter: the physical disk (model, kind, health). Filled in after the quick listing, because asking
// Windows for it takes a second or two.
public record DiskHardware(int DiskNumber, string Model, string Kind, string PartitionStyle, string Health, long DiskBytes);

public record DiskVolume(string Root, string Label, string Format, long TotalBytes, long FreeBytes, string DriveType)
{
    public DiskHardware? Hardware { get; init; }
    public int RestorePoints { get; init; }
    public long RestorePointBytes { get; init; }

    public long UsedBytes => TotalBytes - FreeBytes;
    public double UsedPercent => TotalBytes <= 0 ? 0 : 100.0 * UsedBytes / TotalBytes;
    public string Summary => $"{FormatBytes(UsedBytes)} / {FormatBytes(TotalBytes)}";
    public string UsageText => string.Format(DiskWords.UsageFormat, FormatBytes(UsedBytes), UsedPercent.ToString("F0"), FormatBytes(TotalBytes));
    public string FreeText => FormatBytes(FreeBytes);
    public bool IsCritical => UsedPercent >= 90;
    public bool IsWarning => UsedPercent >= 75 && !IsCritical;
    public static string FreeWord { get; set; } = "free";
    public string FreeLabel => IsCritical ? FreeWord + " ⚠" : FreeWord;
    public string Display => string.IsNullOrEmpty(Label) ? Root : $"{Root} {Label}";

    public bool IsSystem => string.Equals(Root, DiskOverview.WindowsRoot, StringComparison.OrdinalIgnoreCase);
    public string SystemBadge => IsSystem ? DiskWords.System : "";
    public string KindBadge => DriveType switch { "Removable" => DiskWords.Removable, "Network" => DiskWords.Network, _ => "" };
    public string RestoreBadge => RestorePoints > 0 ? string.Format(DiskWords.RestoreFormat, RestorePoints, FormatBytes(RestorePointBytes)) : "";

    // "Disk 0 · Samsung SSD 980 · NVMe SSD · GPT · Healthy", empty until the hardware is known.
    public string HardwareText => Hardware is null ? "" : string.Join("  ·  ", new[]
    {
        string.Format(DiskWords.DiskFormat, Hardware.DiskNumber), Hardware.Model, Hardware.Kind, Hardware.PartitionStyle, Hardware.Health
    }.Where(part => !string.IsNullOrWhiteSpace(part)));

    public static string FormatBytes(long bytes) => DiskOverview.FormatBytes(bytes);
}

// Words shown in the disk page, set from the UI language (the same way FreeWord is).
public static class DiskWords
{
    public static string System { get; set; } = "Windows";
    public static string Removable { get; set; } = "Removable";
    public static string Network { get; set; } = "Network";
    public static string RestoreFormat { get; set; } = "{0} restore points · {1}";
    public static string DiskFormat { get; set; } = "Disk {0}";
    public static string UsageFormat { get; set; } = "{0} used ({1}%) of {2}";
}

public static class DiskOverview
{
    public static string WindowsRoot => Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? @"C:\";

    public static string FormatBytes(long bytes)
    {
        string[] units = { "B", "KiB", "MiB", "GiB", "TiB" };
        double value = Math.Max(bytes, 0);
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1) { value /= 1024; unit++; }
        return unit == 0 ? $"{value:F0} {units[unit]}" : $"{value:F1} {units[unit]}";
    }

    public static List<DiskVolume> Get()
    {
        var volumes = new List<DiskVolume>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            if (drive.DriveType is not (DriveType.Fixed or DriveType.Removable or DriveType.Network)) continue;
            try
            {
                if (!drive.IsReady) continue;
                var (count, bytes) = CountRestorePoints(Path.Combine(drive.Name, "RestoreNest"));
                volumes.Add(new(drive.Name, drive.VolumeLabel, drive.DriveFormat, drive.TotalSize, drive.AvailableFreeSpace, drive.DriveType.ToString()) { RestorePoints = count, RestorePointBytes = bytes });
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return volumes;
    }

    // Restore points are folders named yyyyMMdd-HHmmss holding system.wim; the interrupted ones end in .partial and do not count.
    public static (int Count, long Bytes) CountRestorePoints(string root)
    {
        var count = 0; long bytes = 0;
        try
        {
            if (!Directory.Exists(root)) return (0, 0);
            foreach (var directory in Directory.EnumerateDirectories(root))
            {
                if (!Regex.IsMatch(Path.GetFileName(directory), @"\A\d{8}-\d{6}\z")) continue;
                var wim = Path.Combine(directory, "system.wim");
                if (!File.Exists(wim)) continue;
                count++; bytes += new FileInfo(wim).Length;
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return (count, bytes);
    }

    // Physical disk behind each drive letter. Returns an empty map when Windows cannot say (no storage cmdlets, no rights).
    public static async Task<Dictionary<string, DiskHardware>> GetHardwareAsync()
    {
        const string script = @"
$ErrorActionPreference = 'Stop'
$physical = @{}
Get-PhysicalDisk | ForEach-Object { $physical[[string]$_.DeviceId] = $_ }
$rows = @(Get-Partition | Where-Object DriveLetter | ForEach-Object {
    $partition = $_
    $disk = Get-Disk -Number $partition.DiskNumber
    $pd = $physical[[string]$partition.DiskNumber]
    [pscustomobject]@{ letter = [string]$partition.DriveLetter; disk = [int]$partition.DiskNumber; model = [string]$disk.FriendlyName
        media = $(if ($pd) { [string]$pd.MediaType } else { '' }); bus = [string]$disk.BusType; style = [string]$disk.PartitionStyle
        health = [string]$disk.HealthStatus; size = [long]$disk.Size }
})
ConvertTo-Json -InputObject $rows -Compress";
        try
        {
            var result = await PowerShell.RunAsync(script);
            return result.ExitCode == 0 ? ParseHardware(result.Output) : new();
        }
        catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { return new(); }
    }

    public static Dictionary<string, DiskHardware> ParseHardware(string json)
    {
        var map = new Dictionary<string, DiskHardware>(StringComparer.OrdinalIgnoreCase);
        try
        {
            using var document = JsonDocument.Parse(json);
            var items = document.RootElement.ValueKind == JsonValueKind.Array ? document.RootElement.EnumerateArray().ToArray() : new[] { document.RootElement };
            foreach (var item in items)
            {
                if (item.ValueKind != JsonValueKind.Object) continue;
                string Text(string name) => item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : "";
                long Number(string name) => item.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetInt64() : 0;
                var letter = Text("letter");
                if (letter.Length != 1) continue;
                map[letter + @":\"] = new DiskHardware((int)Number("disk"), Text("model").Trim(), KindOf(Text("media"), Text("bus")), Text("style"), Text("health"), Number("size"));
            }
        }
        catch (JsonException) { }
        return map;
    }

    // "NVMe SSD", "SSD", "HDD", "USB"... from the media type and the bus the disk hangs on.
    public static string KindOf(string media, string bus)
    {
        var solid = media.Equals("SSD", StringComparison.OrdinalIgnoreCase);
        var spinning = media.Equals("HDD", StringComparison.OrdinalIgnoreCase);
        if (bus.Equals("NVMe", StringComparison.OrdinalIgnoreCase)) return "NVMe SSD";
        if (bus.Equals("USB", StringComparison.OrdinalIgnoreCase)) return solid ? "USB SSD" : spinning ? "USB HDD" : "USB";
        if (solid) return "SSD";
        if (spinning) return "HDD";
        return bus.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ? "" : bus;
    }
}
