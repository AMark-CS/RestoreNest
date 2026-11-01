using System.IO;

namespace SystemCare;

public static class RemovalReview
{
    // protectedPaths guard a whole subtree (e.g. Windows); protectedRoots guard only the folder itself and its parents
    // (e.g. Program Files, where individual apps legitimately live).
    public static string Assess(string location, IEnumerable<string> otherLocations, IEnumerable<string> protectedPaths, IEnumerable<string>? protectedRoots = null)
    {
        var path = Normalize(location);
        if (path is null) return "unknown";
        if (string.Equals(path, Path.GetPathRoot(path)?.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return "root";
        foreach (var item in protectedRoots ?? Array.Empty<string>())
        {
            var protectedRoot = Normalize(item);
            if (protectedRoot is not null && Within(protectedRoot, path)) return "protected";
        }
        foreach (var item in protectedPaths)
        {
            var protectedPath = Normalize(item);
            if (protectedPath is not null && (Within(path, protectedPath) || Within(protectedPath, path))) return "protected";
        }
        foreach (var item in otherLocations)
        {
            var other = Normalize(item);
            if (other is not null && (Within(path, other) || Within(other, path))) return "shared";
        }
        // shortcut: registry locations are untrusted, add verified product-specific ownership before allowing deletion.
        return "unverified";
    }

    private static string? Normalize(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || path.StartsWith(@"\\", StringComparison.Ordinal) || !Path.IsPathFullyQualified(path)) return null;
        try { return Path.GetFullPath(path).TrimEnd('\\'); }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return null; }
    }

    private static bool Within(string path, string parent) =>
        path.Equals(parent, StringComparison.OrdinalIgnoreCase) || path.StartsWith(parent + "\\", StringComparison.OrdinalIgnoreCase);
}
