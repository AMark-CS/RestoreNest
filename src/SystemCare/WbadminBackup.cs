using System.Diagnostics;
using System.IO;
using System.Security.Principal;

namespace SystemCare;

public static class WbadminBackup
{
    public static string[] BuildArguments(string destination, string systemRoot)
    {
        if (string.IsNullOrWhiteSpace(destination) || !Path.IsPathFullyQualified(destination) || destination.StartsWith(@"\\", StringComparison.Ordinal)) throw new ArgumentException("A local drive root is required.");
        var path = Path.GetFullPath(destination);
        var root = Path.GetPathRoot(path);
        if (root is null || root.Length != 3 || !char.IsAsciiLetter(root[0]) || root[1] != ':' || !string.Equals(path, root, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("A local drive root is required.");
        if (string.IsNullOrWhiteSpace(systemRoot) || !Path.IsPathFullyQualified(systemRoot) || Path.GetPathRoot(systemRoot) is not { Length: 3 } windowsRoot || windowsRoot[1] != ':') throw new ArgumentException("The system volume must be known.");
        if (string.Equals(root, windowsRoot, StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("The system volume cannot be the backup destination.");
        return new[] { "start", "backup", "-backupTarget:" + root[..2], "-allCritical", "-vssCopy", "-quiet" };
    }

    // shortcut: existing backup folders are refused until retention and repeated backups are tested.
    public static async Task<int> RunAsync(string destination, Action<string> progress)
    {
        var systemRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? throw new InvalidOperationException("Windows volume unavailable.");
        var arguments = BuildArguments(destination, systemRoot);
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator)) throw new UnauthorizedAccessException("Administrator privileges are required.");
        var root = Path.GetPathRoot(Path.GetFullPath(destination))!;
        var drive = new DriveInfo(root);
        if (!drive.IsReady || drive.DriveType is not (DriveType.Fixed or DriveType.Removable) || !drive.DriveFormat.Equals("NTFS", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("A ready local NTFS volume is required.");
        try
        {
            File.GetAttributes(Path.Combine(root, "WindowsImageBackup"));
            throw new InvalidOperationException("Existing Windows backups must not be overwritten.");
        }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }

        var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "wbadmin.exe");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start Windows Backup.");
        async Task ReadAsync(StreamReader reader)
        {
            while (await reader.ReadLineAsync() is { } line) progress(line);
        }
        await Task.WhenAll(ReadAsync(process.StandardOutput), ReadAsync(process.StandardError), process.WaitForExitAsync());
        return process.ExitCode;
    }
}
