using System.IO;
using System.Windows;

namespace SystemCare;

// Recovery environment extras on the restore page: restart straight into recovery, and BitLocker recovery-password help.
public partial class MainWindow
{
    private BitLockerInfo? bitLocker;

    private string RecoveryRoot()
    {
        var root = RpPath.Text.Trim().TrimEnd('\\');
        if (root.Length == 2) root += @"\RestoreNest";
        return root;
    }

    private void RefreshRecoveryText()
    {
        RpRecoverNowButton.Content = T("重启并还原…", "Restart and restore…");
        RpKeyShowButton.Content = T("查看恢复密码", "Show recovery password");
        RpKeySaveButton.Content = T("保存到文件…", "Save to a file…");
        RpBitLockerTitle.Text = T("这台电脑开启了 BitLocker，请先保存恢复密码", "BitLocker is on: save your recovery password now");
        RpBitLockerText.Text = T("系统出问题后还原，或修改启动配置时，可能需要输入 48 位恢复密码。没有它，加密的磁盘就打不开。请现在保存好，并且不要只放在这台电脑里。提醒：还原点里的文件没有加密，请把保存还原点的磁盘也用 BitLocker 加密，或妥善保管这块磁盘。",
            "After a problem, restoring (or changing the boot configuration) may ask for the 48-digit recovery password; without it the encrypted drive cannot be opened. Save it now, and not only on this PC. Note: the files inside restore points are not encrypted; encrypt the drive that holds them with BitLocker too, or keep that drive safe.");
    }

    // The restore page shows the BitLocker card only when the Windows drive is protected.
    private async Task LoadBitLockerAsync()
    {
        try
        {
            var result = await RestorePoints.RunScriptAsync("Get-BitLockerInfo.ps1", Array.Empty<string>());
            bitLocker = result.ExitCode == 0 ? BitLockerInfo.Parse(result.Output) : null;
            RpBitLockerCard.Visibility = bitLocker is { ProtectionOn: true } ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { RpBitLockerCard.Visibility = Visibility.Collapsed; }
    }

    private void RpKeyShowClick(object sender, RoutedEventArgs e)
    {
        var keys = bitLocker?.ValidPasswords ?? Array.Empty<string>();
        var drive = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
        var text = keys.Length == 0
            ? T("没有找到恢复密码。请在微软账户（aka.ms/myrecoverykey）里查找，或在 BitLocker 管理里添加一个恢复密码。", "No recovery password was found. Look in your Microsoft account (aka.ms/myrecoverykey) or add one in BitLocker management.")
            : string.Join("\n", keys) + "\n\n" + T("请保存在安全的地方，不要只放在这台电脑里。", "Keep it somewhere safe, not only on this PC.");
        System.Windows.MessageBox.Show(this, text, T($"{drive} 盘的 BitLocker 恢复密码", $"BitLocker recovery password for {drive}"));
    }

    private void RpKeySaveClick(object sender, RoutedEventArgs e)
    {
        if (bitLocker is null || bitLocker.ValidPasswords.Length == 0) { RpKeyShowClick(sender, e); return; }
        var drive = Environment.GetEnvironmentVariable("SystemDrive") ?? "C:";
        var dialog = new Microsoft.Win32.SaveFileDialog { FileName = T("BitLocker恢复密码.txt", "BitLocker-recovery-password.txt"), Filter = "Text|*.txt", InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.Desktop) };
        if (dialog.ShowDialog(this) != true) return;
        try
        {
            File.WriteAllText(dialog.FileName, bitLocker.KeyFileText(English, drive), new System.Text.UTF8Encoding(true));
            System.Windows.MessageBox.Show(this, T("已保存。请把这个文件放到 U 盘上或打印出来，然后从这台电脑里删除它。", "Saved. Put the file on a USB drive or print it, then delete it from this PC."), "RestoreNest");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { System.Windows.MessageBox.Show(this, ex.Message, "RestoreNest"); }
    }

    private async void RpRecoverNowClick(object sender, RoutedEventArgs e)
    {
        if (System.Windows.MessageBox.Show(this, T("电脑将在几秒钟后重启，并进入恢复环境（只这一次，之后恢复正常启动）。请先保存并关闭正在使用的文件。继续吗？", "The PC will restart in a few seconds into the recovery environment (this once only; afterwards it starts normally). Save and close your files first. Continue?"), "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        SetRestoreBusy(true); RpLogExpander.IsExpanded = true; RpOutput.Text = "";
        try
        {
            var result = await RestorePoints.RunScriptAsync("Start-Recovery.ps1", new[] { "-Root", RecoveryRoot() }, RpLog);
            if (result.ExitCode != 0) System.Windows.MessageBox.Show(this, T("无法重启进入恢复环境，详细信息在“详细输出”里。", "Could not restart into the recovery environment; see “Details”."), "RestoreNest", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { RpLog(ex.Message); }
        finally { SetRestoreBusy(false); }
    }
}
