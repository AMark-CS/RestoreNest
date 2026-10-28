namespace SystemCare;

public static class QihooIdentification
{
    private static readonly string[] Names = { "360安全卫士", "360安全浏览器", "360浏览器", "360软件管家", "360 Total Security", "360 Security" };

    // shortcut: names identify candidates only; verify publisher and product versions before removal.
    public static bool IsCandidate(string name) => !string.IsNullOrWhiteSpace(name) && Names.Any(prefix => name.Trim().StartsWith(prefix, StringComparison.OrdinalIgnoreCase));
}
