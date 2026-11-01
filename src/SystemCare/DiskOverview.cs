using System.IO;

namespace SystemCare;

public record DiskVolume(string Root, string Label, string Format, long TotalBytes, long FreeBytes, string DriveType)
{
    public long UsedBytes => TotalBytes - FreeBytes;
    public double UsedPercent => TotalBytes <= 0 ? 0 : 100.0 * UsedBytes / TotalBytes;
    public string Summary => $"{FormatBytes(UsedBytes)} / {FormatBytes(TotalBytes)}";
    public string FreeText => FormatBytes(FreeBytes);
    public string Display => string.IsNullOrEmpty(Label) ? Root : $"{Root} {Label}";

    public static string FormatBytes(long bytes) => DiskOverview.FormatBytes(bytes);
}

public static class DiskOverview
{
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
                volumes.Add(new(drive.Name, drive.VolumeLabel, drive.DriveFormat, drive.TotalSize, drive.AvailableFreeSpace, drive.DriveType.ToString()));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return volumes;
    }
}
