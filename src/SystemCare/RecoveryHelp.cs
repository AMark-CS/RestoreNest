using System.Text.Json;

namespace SystemCare;

// Result of tools\Get-BitLockerInfo.ps1 for the Windows drive.
public record BitLockerInfo(bool ProtectionOn, string[] RecoveryPasswords)
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNameCaseInsensitive = true };

    public static BitLockerInfo? Parse(string output)
    {
        var line = output.Split('\n').Select(l => l.Trim()).LastOrDefault(l => l.StartsWith('{'));
        if (line is null) return null;
        try { return JsonSerializer.Deserialize<BitLockerInfo>(line, Json); }
        catch (JsonException) { return null; }
    }

    // Only 48-digit groups ever reach a file or a dialog.
    public string[] ValidPasswords => RecoveryPasswords.Where(p => System.Text.RegularExpressions.Regex.IsMatch(p ?? "", @"\A\d{6}(-\d{6}){7}\z")).Distinct().ToArray();

    public string KeyFileText(bool english, string drive)
    {
        var lines = new List<string>
        {
            english ? $"BitLocker recovery password for drive {drive}" : $"{drive} 盘的 BitLocker 恢复密码",
            ""
        };
        lines.AddRange(ValidPasswords);
        lines.Add("");
        lines.Add(english
            ? "Keep this somewhere safe and NOT only on this PC: print it or put it on a USB drive. Anyone who has it can unlock the drive."
            : "请保存在安全的地方，不要只放在这台电脑里：打印出来，或者放在 U 盘上。拿到它的人可以解锁这块磁盘。");
        return string.Join(Environment.NewLine, lines) + Environment.NewLine;
    }
}
