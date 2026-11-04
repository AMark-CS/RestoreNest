using System.IO;
using System.Text.Json;

namespace SystemCare;

// Settings of the automatic restore points. The same file is read by the scheduled task (tools\Invoke-ScheduledRestorePoint.ps1),
// so field names and rules match tools\RestoreSchedule.Common.ps1.
public record ScheduleSettings(bool Enabled, string Frequency, string Time, string DayOfWeek, int DayOfMonth, int Keep, string Destination, bool OnlyOnAC)
{
    public static readonly string[] Frequencies = { "daily", "every3days", "weekly", "biweekly", "monthly" };
    public static readonly string[] WeekDays = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };
    public static ScheduleSettings Default => new(false, "weekly", "02:00", "Sunday", 1, 3, "", true);

    // null when the settings are acceptable, otherwise a short code of the first problem.
    public string? Validate()
    {
        if (!Frequencies.Contains(Frequency)) return "frequency";
        if (!System.Text.RegularExpressions.Regex.IsMatch(Time ?? "", @"\A([01]\d|2[0-3]):[0-5]\d\z")) return "time";
        if (!WeekDays.Contains(DayOfWeek)) return "day";
        if (DayOfMonth < 1 || DayOfMonth > 28) return "dayOfMonth";
        if (Keep < 1 || Keep > 30) return "keep";
        if (Enabled && AutoProtection.CheckDestination(Destination ?? "") is { } problem) return "destination:" + problem;
        return null;
    }
}

public record ScheduleLast(string? LastRunUtc, string? Code, string? Detail, string? LastSuccessUtc, int PointCount);
public record ScheduleStatus(bool Registered, string? State, string? NextRunUtc, string? TaskAction, ScheduleLast? Last);

public static class AutoProtection
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true, WriteIndented = true };

    public static string DataDirectory => Environment.GetEnvironmentVariable("RN_DATA") is { Length: > 0 } overridden ? overridden : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "RestoreNest");
    public static string SettingsPath => Path.Combine(DataDirectory, "schedule.json");

    public static ScheduleSettings Load()
    {
        try { return File.Exists(SettingsPath) ? JsonSerializer.Deserialize<ScheduleSettings>(File.ReadAllText(SettingsPath), Json) ?? ScheduleSettings.Default : ScheduleSettings.Default; }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException) { return ScheduleSettings.Default; }
    }

    public static void Save(ScheduleSettings settings)
    {
        Directory.CreateDirectory(DataDirectory);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, Json), new System.Text.UTF8Encoding(false));
    }

    // A restore point cannot live on the Windows partition; the drive must be present and NTFS. null when fine.
    public static string? CheckDestination(string path)
    {
        if (path.Length < 2 || !char.IsLetter(path[0]) || path[1] != ':') return "format";
        var windowsRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
        if (string.Equals(Path.GetPathRoot(path), windowsRoot, StringComparison.OrdinalIgnoreCase)) return "windows-drive";
        try
        {
            var drive = new DriveInfo(path.Substring(0, 1));
            if (!drive.IsReady) return "not-ready";
            if (!string.Equals(drive.DriveFormat, "NTFS", StringComparison.OrdinalIgnoreCase)) return "not-ntfs";
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException) { return "not-ready"; }
        return null;
    }

    // Set-RestoreSchedule.ps1 -Status prints one JSON line; script chatter around it is ignored.
    public static ScheduleStatus? ParseStatus(string output)
    {
        var line = output.Split('\n').Select(l => l.Trim()).LastOrDefault(l => l.StartsWith('{'));
        if (line is null) return null;
        try { return JsonSerializer.Deserialize<ScheduleStatus>(line, Json); }
        catch (JsonException) { return null; }
    }

    public static string? Local(string? utc) =>
        DateTime.TryParse(utc, null, System.Globalization.DateTimeStyles.RoundtripKind, out var t) && t.Year > 2000 ? t.ToLocalTime().ToString("yyyy-MM-dd HH:mm") : null;

    // One or two sentences for the card: what happens next and how the last run went.
    public static string Describe(ScheduleSettings settings, ScheduleStatus? status, bool english)
    {
        string T(string zh, string en) => english ? en : zh;
        if (!settings.Enabled) return T("自动保护已关闭。", "Automatic protection is off.");
        if (status is null) return T("无法读取计划任务状态。", "Could not read the scheduled task.");
        var parts = new List<string>();
        parts.Add(status.Registered
            ? (Local(status.NextRunUtc) is { } next ? T($"下次自动创建：{next}", $"Next automatic restore point: {next}") : T("计划任务已设置。", "Scheduled."))
            : T("计划任务尚未生效，请点击“保存设置”。", "Not scheduled yet; click “Save settings”."));
        if (status.Last is { Code: { Length: > 0 } code } last)
        {
            var when = Local(last.LastRunUtc) ?? "";
            var detail = last.Detail ?? "";
            parts.Add(code switch
            {
                "ok" => T($"上次 {when}：成功，现有 {last.PointCount} 个还原点。", $"Last run {when}: succeeded, {last.PointCount} restore points kept."),
                "destination-unavailable" => T($"上次 {when}：没有执行，找不到保存位置（外接硬盘没插上？）。", $"Last run {when}: skipped, the storage location was not found (disk unplugged?)."),
                "no-space" => T($"上次 {when}：空间不足，没有创建（{detail}）。最新的还原点已保留。", $"Last run {when}: not enough space, nothing created ({detail}). The newest restore point was kept."),
                "busy" => T($"上次 {when}：已有还原点正在创建，本次跳过。", $"Last run {when}: another restore point was being created; skipped."),
                "capture-failed" => T($"上次 {when}：创建失败（{detail}）。原有还原点未受影响。", $"Last run {when}: failed ({detail}). Existing restore points are untouched."),
                "disabled" => "",
                _ => T($"上次 {when}：出错（{detail}）。", $"Last run {when}: error ({detail}).")
            });
        }
        return string.Join("  ", parts.Where(p => p.Length > 0));
    }

    // The scheduled task runs as SYSTEM, so Set-RestoreSchedule.ps1 copies the scripts into the (administrator-only) data folder.
    public static string ScriptPath => Path.Combine(DataDirectory, "bin", "Invoke-ScheduledRestorePoint.ps1");

    // True when the registered task does not point at the protected copy (for example it was registered by an older version).
    public static bool TaskPointsElsewhere(ScheduleStatus status) =>
        status.Registered && !(status.TaskAction ?? "").Contains(ScriptPath, StringComparison.OrdinalIgnoreCase);

    public static async Task<(bool Ok, string Message)> ApplyAsync(ScheduleSettings settings)
    {
        Save(settings);
        var result = await RestorePoints.RunScriptAsync("Set-RestoreSchedule.ps1", new[] { "-Apply" });
        return (result.ExitCode == 0, result.Output.Trim());
    }

    public static async Task<ScheduleStatus?> GetStatusAsync()
    {
        var result = await RestorePoints.RunScriptAsync("Set-RestoreSchedule.ps1", new[] { "-Status" });
        return result.ExitCode == 0 ? ParseStatus(result.Output) : null;
    }
}
