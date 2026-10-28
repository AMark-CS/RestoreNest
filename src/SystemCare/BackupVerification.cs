using System.IO;
using System.Security.Cryptography;

namespace SystemCare;

public sealed record BackupFile(string Path, string Sha256);
public sealed record BackupManifest(int Version, BackupFile[] Files);

public static class BackupVerification
{
    public static bool Verify(string directory, BackupManifest manifest)
    {
        if (manifest is null || manifest.Version != 1 || manifest.Files is null || manifest.Files.Length == 0) return false;
        try
        {
            var root = Path.GetFullPath(directory);
            if (!Path.IsPathFullyQualified(root) || root.StartsWith(@"\\", StringComparison.Ordinal) || HasReparsePoint(root)) return false;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var file in manifest.Files)
            {
                if (file is null || string.IsNullOrWhiteSpace(file.Path) || string.IsNullOrWhiteSpace(file.Sha256)) return false;
                var parts = file.Path.Split(new[] { '/', '\\' }, StringSplitOptions.None);
                if (parts.Any(p => p.Length == 0 || p is "." or ".." || p.Contains(':'))) return false;
                var path = Path.GetFullPath(Path.Combine(root, Path.Combine(parts)));
                if (!path.StartsWith(Path.TrimEndingDirectorySeparator(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !seen.Add(path) || HasReparsePoint(path)) return false;
                var expected = Convert.FromHexString(file.Sha256);
                if (expected.Length != 32) return false;
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                if (!CryptographicOperations.FixedTimeEquals(SHA256.HashData(stream), expected)) return false;
            }
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or FormatException or NotSupportedException or System.Security.SecurityException)
        {
            return false;
        }
    }

    private static bool HasReparsePoint(string path)
    {
        var root = Path.GetPathRoot(path) ?? throw new ArgumentException("Missing root");
        var current = root;
        foreach (var part in path[root.Length..].Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, part);
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) return true;
        }
        return false;
    }
}
