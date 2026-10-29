using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SystemCare;

public record RecoveryVolume(Guid Disk, Guid Partition);

public record RecoveryTask(int Schema, string Version, string Machine, RecoveryVolume Backup, RecoveryVolume Windows)
{
    public void Validate()
    {
        if (Schema != 1 || !DateTime.TryParseExact(Version, "MM/dd/yyyy-HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out _)) throw new ArgumentException("Invalid recovery task version.");
        if (Machine is null || !Regex.IsMatch(Machine, @"\A[A-Za-z0-9][A-Za-z0-9-]{0,62}\z")) throw new ArgumentException("Unsupported computer name.");
        if (Backup is null || Windows is null || Backup.Disk == Guid.Empty || Backup.Partition == Guid.Empty || Windows.Disk == Guid.Empty || Windows.Partition == Guid.Empty) throw new ArgumentException("GPT disk and partition identities are required.");
        if (Backup.Disk == Windows.Disk || Backup.Partition == Windows.Partition) throw new ArgumentException("This experimental workflow requires separate system and backup disks.");
    }

    public static async Task<RecoveryVolume> IdentifyAsync(string driveRoot)
    {
        RecoveryCatalog.BuildArguments(driveRoot);
        var letter = driveRoot[0];
        var script = "$ErrorActionPreference='Stop'; $p=Get-Partition -DriveLetter '" + letter + "'; $d=$p | Get-Disk; if ($d.PartitionStyle -ne 'GPT') { throw 'Only GPT disks are supported.' }; @{Disk=$d.Guid; Partition=$p.Guid} | ConvertTo-Json -Compress";
        var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(script)) }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not read disk identity.");
        var output = process.StandardOutput.ReadToEndAsync();
        var errors = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0) throw new InvalidOperationException(await errors);
        return JsonSerializer.Deserialize<RecoveryVolume>(await output) ?? throw new InvalidOperationException("Disk identity unavailable.");
    }
}
