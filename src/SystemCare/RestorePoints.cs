using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace SystemCare;

public record RestorePointInfo(string Id, string Name, string CreatedUtc, double SizeGiB, string Status, string Path)
{
    public string Created => DateTime.TryParse(CreatedUtc, null, System.Globalization.DateTimeStyles.RoundtripKind, out var t) ? t.ToLocalTime().ToString("yyyy-MM-dd HH:mm") : CreatedUtc;
    public string SizeText => $"{SizeGiB:F1} GiB";
}

public static class RestorePoints
{
    public static string ToolsDirectory => Environment.GetEnvironmentVariable("RN_TOOLS") is { Length: > 0 } overridden ? overridden : System.IO.Path.Combine(AppContext.BaseDirectory, "tools");
    public static string WimlibPath => System.IO.Path.Combine(ToolsDirectory, "bin", "wimlib-imagex.exe");

    // -Verbose also prints PowerShell module import chatter (hundreds of "Exporting function" lines); the UI log hides it.
    public static bool IsModuleNoise(string line) => System.Text.RegularExpressions.Regex.IsMatch(line, @"^VERBOSE: (Exporting|Importing|Loading|Populating) ");

    public static List<RestorePointInfo> ParseList(string json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new();
        try
        {
            var items = JsonSerializer.Deserialize<List<RestorePointInfo>>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            return items?.Where(i => i is not null && !string.IsNullOrEmpty(i.Id)).ToList() ?? new();
        }
        catch (JsonException) { return new(); }
    }

    // Arguments are passed as an argument list, never concatenated into a command line.
    public static string[] BuildScriptArguments(string script, IEnumerable<string> arguments) =>
        new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", System.IO.Path.Combine(ToolsDirectory, script) }.Concat(arguments).ToArray();

    public static async Task<(int ExitCode, string Output)> RunScriptAsync(string script, IEnumerable<string> arguments, Action<string>? progress = null)
    {
        var scriptPath = System.IO.Path.Combine(ToolsDirectory, script);
        if (!File.Exists(scriptPath)) throw new FileNotFoundException("Script missing.", scriptPath);
        var executable = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in BuildScriptArguments(script, arguments)) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start PowerShell.");
        var text = new System.Text.StringBuilder();
        async Task Read(StreamReader reader)
        {
            while (await reader.ReadLineAsync() is { } line) { lock (text) text.AppendLine(line); progress?.Invoke(line); }
        }
        await Task.WhenAll(Read(process.StandardOutput), Read(process.StandardError), process.WaitForExitAsync());
        return (process.ExitCode, text.ToString());
    }

    public static async Task<List<RestorePointInfo>> ListAsync(string destination, bool verify)
    {
        var args = new List<string> { "-Destination", destination, "-Json" };
        if (verify) { args.Add("-Verify"); if (File.Exists(WimlibPath)) { args.Add("-WimlibPath"); args.Add(WimlibPath); } }
        var result = await RunScriptAsync("Get-RestorePoint.ps1", args);
        if (result.ExitCode != 0) throw new InvalidOperationException(result.Output.Trim());
        return ParseList(result.Output);
    }
}
