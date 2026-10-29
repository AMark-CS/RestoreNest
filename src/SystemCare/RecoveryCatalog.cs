using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Text.RegularExpressions;

namespace SystemCare;

public static class RecoveryCatalog
{
    public static List<string> ParseVersions(string output)
    {
        var versions = new List<string>();
        foreach (var line in output.Split('\n'))
        {
            var match = Regex.Match(line.Trim(), @"^[^:：\r\n]+[:：]\s*(\d{2}/\d{2}/\d{4}-\d{2}:\d{2})\s*$", RegexOptions.CultureInvariant);
            if (match.Success && DateTime.TryParseExact(match.Groups[1].Value, "MM/dd/yyyy-HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _) && !versions.Contains(match.Groups[1].Value))
                versions.Add(match.Groups[1].Value);
        }
        return versions;
    }

    public static string[] BuildArguments(string destination)
    {
        if (string.IsNullOrWhiteSpace(destination) || !Path.IsPathFullyQualified(destination) || destination.StartsWith(@"\\", StringComparison.Ordinal)) throw new ArgumentException("A local drive root is required.");
        var path = Path.GetFullPath(destination);
        var root = Path.GetPathRoot(path);
        if (root is null || root.Length != 3 || !char.IsAsciiLetter(root[0]) || root[1] != ':' || !string.Equals(path, root, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("A local drive root is required.");
        return new[] { "get", "versions", "-backupTarget:" + root[..2] };
    }

    public static async Task<(int ExitCode, string Output)> ReadAsync(string destination)
    {
        var arguments = BuildArguments(destination);
        var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "wbadmin.exe");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start Windows Backup.");
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return (process.ExitCode, (await output + Environment.NewLine + await errors).Trim());
    }
}
