using System.Diagnostics;
using System.IO;

namespace SystemCare;

public record UninstallCommand(string FileName, string Arguments, bool Silent);

public static class Uninstaller
{
    // Picks the quietest trustworthy command we can derive from the registry entry; returns null when none is usable.
    public static UninstallCommand? Plan(InstalledApp app)
    {
        if (app.MsiProductCode is { } code)
            return new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "msiexec.exe"), string.Join(' ', MsiUninstall.BuildArguments(code)), true);
        if (Parse(app.QuietUninstallString) is { } quiet) return new(quiet.File, quiet.Args, true);
        if (Parse(app.UninstallString) is { } normal)
        {
            // Registry sometimes stores the MSI "install" verb; an uninstall must never reinstall.
            if (Path.GetFileName(normal.File).Equals("msiexec.exe", StringComparison.OrdinalIgnoreCase))
            {
                var converted = System.Text.RegularExpressions.Regex.Replace(normal.Args, @"/I(?=\s*\{)", "/X", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                return new(normal.File, converted, false);
            }
            return new(normal.File, normal.Args, false);
        }
        return null;
    }

    public static (string File, string Args)? Parse(string command)
    {
        if (string.IsNullOrWhiteSpace(command)) return null;
        command = command.Trim();
        string file, args;
        if (command[0] == '"')
        {
            var end = command.IndexOf('"', 1);
            if (end < 0) return null;
            file = command[1..end]; args = command[(end + 1)..].Trim();
        }
        else
        {
            var idx = command.IndexOf(".exe", StringComparison.OrdinalIgnoreCase);
            if (idx < 0) return null;
            file = command[..(idx + 4)]; args = command[(idx + 4)..].Trim();
        }
        file = Environment.ExpandEnvironmentVariables(file);
        // Windows Installer entries usually store a bare "MsiExec.exe"; resolve it to System32 instead of trusting PATH.
        if (file.Equals("msiexec.exe", StringComparison.OrdinalIgnoreCase)) file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "msiexec.exe");
        if (!Path.IsPathFullyQualified(file) || file.StartsWith(@"\\", StringComparison.Ordinal) || !file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return null;
        return (file, args);
    }

    public static async Task<int> RunAsync(UninstallCommand command)
    {
        if (!File.Exists(command.FileName)) throw new FileNotFoundException("Uninstaller not found.", command.FileName);
        var start = new ProcessStartInfo(command.FileName, command.Arguments) { UseShellExecute = false, CreateNoWindow = command.Silent };
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start uninstaller.");
        await process.WaitForExitAsync();
        return process.ExitCode;
    }

    public static bool StillInstalled(InstalledApp app) =>
        InstalledApps.Get().Any(x => x.Name == app.Name && x.UninstallString == app.UninstallString && x.MsiProductCode == app.MsiProductCode);

    // Best effort: Windows throttles automatic restore points (default one per 24 h), so failure is reported, not fatal.
    public static async Task<(bool Ok, string Message)> CreateRestorePointAsync(string description)
    {
        var safe = new string(description.Where(c => char.IsLetterOrDigit(c) || c is ' ' or '.' or '-').ToArray());
        var script = $"$ErrorActionPreference='Stop'; Enable-ComputerRestore -Drive $env:SystemDrive; Checkpoint-Computer -Description 'RestoreNest {safe}' -RestorePointType MODIFY_SETTINGS";
        var result = await PowerShell.RunAsync(script);
        return (result.ExitCode == 0, result.ExitCode == 0 ? "" : result.Error.Trim());
    }
}
