using System.Diagnostics;
using System.IO;

namespace SystemCare;

public static class MsiUninstall
{
    public static Guid? ProductCode(string keyName, object? windowsInstaller) =>
        windowsInstaller is int value && value == 1 && Guid.TryParseExact(keyName, "B", out var code) && code != Guid.Empty ? code : null;

    public static string[] BuildArguments(Guid productCode)
    {
        if (productCode == Guid.Empty) throw new ArgumentException("A product code is required.");
        return new[] { "/x", productCode.ToString("B").ToUpperInvariant(), "/qn", "/norestart" };
    }

    // shortcut: not exposed until product identity and real uninstall are verified in an isolated VM.
    public static async Task<int> RunAsync(Guid productCode)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "msiexec.exe")) { UseShellExecute = false, CreateNoWindow = true };
        foreach (var argument in BuildArguments(productCode)) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start Windows Installer.");
        await process.WaitForExitAsync();
        return process.ExitCode;
    }
}
