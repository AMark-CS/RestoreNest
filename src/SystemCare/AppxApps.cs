using System.Text.Json;
using System.Text.RegularExpressions;

namespace SystemCare;

public static class AppxApps
{
    private static readonly Regex FullName = new(@"\A[A-Za-z0-9._-]+_[A-Za-z0-9._~-]*_[A-Za-z0-9._~-]*_[A-Za-z0-9._~-]*_[a-z0-9]+\z", RegexOptions.CultureInvariant);

    public static bool IsValidFullName(string name) => FullName.IsMatch(name);

    // Current-user, non-framework, removable packages only.
    public static async Task<List<InstalledApp>> GetAsync()
    {
        var script = "Get-AppxPackage | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -ne 'System' } | ForEach-Object { [pscustomobject]@{ N=$_.Name; F=$_.PackageFullName; V=$_.Version.ToString(); P=$_.Publisher } } | ConvertTo-Json -Compress";
        var result = await PowerShell.RunAsync(script);
        return result.ExitCode == 0 ? Parse(result.Output) : new();
    }

    public static List<InstalledApp> Parse(string json)
    {
        var apps = new List<InstalledApp>();
        if (string.IsNullOrWhiteSpace(json)) return apps;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var items = doc.RootElement.ValueKind == JsonValueKind.Array ? doc.RootElement.EnumerateArray().ToList() : new List<JsonElement> { doc.RootElement };
            foreach (var item in items)
            {
                var name = item.TryGetProperty("N", out var n) ? n.GetString() : null;
                var full = item.TryGetProperty("F", out var f) ? f.GetString() : null;
                if (string.IsNullOrWhiteSpace(name) || full is null || !IsValidFullName(full)) continue;
                var version = item.TryGetProperty("V", out var v) ? v.GetString() ?? "" : "";
                var publisher = item.TryGetProperty("P", out var p) ? p.GetString() ?? "" : "";
                apps.Add(new(name + " (Store)", publisher, version, "", AppxPackage: full));
            }
        }
        catch (JsonException) { }
        return apps;
    }

    public static async Task<int> RemoveAsync(string fullName)
    {
        if (!IsValidFullName(fullName)) throw new ArgumentException("Invalid package name.");
        return (await PowerShell.RunAsync($"Remove-AppxPackage -Package '{fullName}'")).ExitCode;
    }
}
