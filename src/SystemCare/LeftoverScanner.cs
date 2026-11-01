using System.IO;

namespace SystemCare;

public record Leftover(string Path, string Reason);

// Lists *candidates* only; the caller decides what to delete. Matching is by exact folder name, never by substring.
public static class LeftoverScanner
{
    public static List<Leftover> Scan(InstalledApp app, IEnumerable<string> otherLocations, IEnumerable<string> protectedTrees, IEnumerable<string> protectedRoots)
    {
        var found = new List<Leftover>();
        var others = otherLocations.ToList();
        var trees = protectedTrees.ToList();
        var roots = protectedRoots.ToList();
        void Add(string path, string reason)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path) || found.Any(f => f.Path.Equals(path, StringComparison.OrdinalIgnoreCase))) return;
            if (RemovalReview.Assess(path, others, trees, roots) == "unverified") found.Add(new(path, reason));
        }
        Add(app.Location, "install");
        var bases = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData)
        };
        var names = new[] { app.Name, app.Publisher }.Where(n => !string.IsNullOrWhiteSpace(n) && IsPlainFolderName(n)).Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var baseDir in bases.Where(b => !string.IsNullOrEmpty(b)))
            foreach (var name in names)
                // A publisher folder is shared by all of that publisher's products, so only offer it for the app's own name.
                if (!name.Equals(app.Publisher, StringComparison.OrdinalIgnoreCase)) Add(System.IO.Path.Combine(baseDir, name), "data");
        return found;
    }

    private static bool IsPlainFolderName(string name) =>
        name.IndexOfAny(System.IO.Path.GetInvalidFileNameChars()) < 0 && name.Trim() == name && name is not ("." or "..");

    // Refuses reparse points so a junction can never redirect a delete outside the candidate.
    public static void Delete(Leftover item)
    {
        var info = new DirectoryInfo(item.Path);
        if (!info.Exists) return;
        if ((info.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Reparse points are not deleted.");
        info.Delete(true);
    }
}
