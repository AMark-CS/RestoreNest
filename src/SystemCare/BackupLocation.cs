using System.IO;

namespace SystemCare;

public static class BackupLocation
{
    public static string? Validate(string path, string systemRoot)
    {
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path)) return "absolute";
        if (path.StartsWith(@"\\", StringComparison.Ordinal)) return "network";
        string root;
        try { root = Path.GetPathRoot(Path.GetFullPath(path)) ?? ""; }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return "absolute"; }
        if (string.Equals(root, Path.GetPathRoot(systemRoot), StringComparison.OrdinalIgnoreCase)) return "system";
        return null;
    }
}
