using System.IO;
using System.Windows;

namespace SystemCare;

public partial class MainWindow
{
    private bool restoreBusy;

    private void RefreshRestoreText()
    {
        RpTitle.Text = T("还原点", "Restore points");
        RpSubtitle.Text = T("为 Windows 分区创建映像，出问题时可从启动菜单还原。", "Image the Windows partition now; restore it from the boot menu if something goes wrong.");
        RpPathLabel.Text = T("保存位置", "Storage location");
        RpName.ToolTip = T("还原点名称（可选）", "Restore point name (optional)");
        RpCreateButton.Content = T("创建还原点", "Create restore point"); RpRefreshButton.Content = T("刷新", "Refresh");
        RpVerifyButton.Content = T("校验全部", "Verify all"); RpInstallBootButton.Content = T("设置恢复环境", "Set up recovery"); RpRemoveBootButton.Content = T("移除启动项", "Remove boot entry");
        RpListTitle.Text = T("已有还原点", "Existing restore points");
        RpEnvTitle.Text = T("恢复环境", "Recovery environment");
        RefreshEnvStatus();
        RpIdColumn.Header = T("编号", "Id"); RpNameColumn.Header = T("名称", "Name"); RpCreatedColumn.Header = T("创建时间", "Created"); RpSizeColumn.Header = T("大小", "Size"); RpStatusColumn.Header = T("状态", "Status");
        RpLogExpander.Header = T("详细输出", "Details");
        RpEmpty.Text = T("此位置还没有还原点。\n选择保存位置后点击“创建还原点”。", "No restore points here yet.\nChoose a location and click “Create restore point”.");
        RpNotice.Text = T("预览版：已在虚拟机（Windows 10 与 Windows 11、UEFI；Windows 10 另含 Secure Boot 与密码保护的 BitLocker）中验证创建与还原，尚未在真机或 TPM 绑定的 BitLocker 下验证。还原加密分区需要 BitLocker 恢复密码。请勿作为重要数据的唯一保护。",
            "Preview: creation and restore were verified in a VM (Windows 10 and Windows 11, UEFI; Windows 10 also with Secure Boot and a password-protected BitLocker volume). Not yet verified on real hardware or TPM-bound BitLocker. Restoring an encrypted partition needs the BitLocker recovery password. Do not rely on it as the only protection for important data.");
        RpPathChanged(null, null!);
        RefreshScheduleText();
        RefreshRecoveryText();
    }

    private void RpPathChanged(object? sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (!IsInitialized) return;
        var path = RpPath.Text.Trim();
        try
        {
            if (path.Length < 2 || !char.IsLetter(path[0]) || path[1] != ':') { RpPathHint.Text = T("请输入本地盘符或文件夹，例如 D:\\。", "Enter a local drive or folder such as D:\\."); return; }
            var windowsRoot = Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows));
            if (string.Equals(Path.GetPathRoot(path), windowsRoot, StringComparison.OrdinalIgnoreCase)) { RpPathHint.Text = T("不能保存在 Windows 所在分区，请选择其他分区（可以是同一块物理磁盘）。", "Cannot be stored on the Windows partition. Pick another partition (the same physical disk is fine)."); return; }
            var drive = new DriveInfo(path.Substring(0, 1));
            RpPathHint.Text = drive.IsReady
                ? T($"{drive.Name} · {drive.DriveFormat} · 可用 {DiskOverview.FormatBytes(drive.AvailableFreeSpace)}", $"{drive.Name} · {drive.DriveFormat} · {DiskOverview.FormatBytes(drive.AvailableFreeSpace)} free")
                : T("所选磁盘不可用。", "The selected drive is unavailable.");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException) { RpPathHint.Text = ""; }
    }

    private void SetRestoreBusy(bool busy)
    {
        restoreBusy = busy;
        foreach (var button in new[] { RpCreateButton, RpRefreshButton, RpVerifyButton, RpInstallBootButton, RpRemoveBootButton, RpRecoverNowButton }) button.IsEnabled = !busy;
        RpProgress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RpLog(string line) => Dispatcher.BeginInvoke(() =>
    {
        if (RestorePoints.IsModuleNoise(line)) return;
        if (RpOutput.Text.Length > 20000) RpOutput.Text = RpOutput.Text[^10000..];
        RpOutput.AppendText(line + "\n"); RpOutput.ScrollToEnd();
    });

    private async Task RpLoadAsync(bool verify)
    {
        try
        {
            var list = await RestorePoints.ListAsync(RpPath.Text.Trim(), verify);
            RpList.ItemsSource = list;
            RpEmpty.Visibility = list.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            RpOutput.Text = "";
            RefreshEnvStatus();
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException or System.ComponentModel.Win32Exception)
        {
            RpList.ItemsSource = null;
            RpEmpty.Visibility = Visibility.Visible;
            RpLogExpander.IsExpanded = true;
            RpOutput.Text = T("无法读取还原点：", "Unable to read restore points: ") + ex.Message;
        }
    }

    private async void RpRefreshClick(object sender, RoutedEventArgs e) { SetRestoreBusy(true); try { await RpLoadAsync(false); } finally { SetRestoreBusy(false); } }
    private async void RpVerifyClick(object sender, RoutedEventArgs e) { SetRestoreBusy(true); RpOutput.Text = T("正在校验…", "Verifying…"); try { await RpLoadAsync(true); } finally { SetRestoreBusy(false); } }

    private void RpBrowseClick(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog { Description = T("选择保存位置", "Choose a storage location"), UseDescriptionForTitle = true };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK) RpPath.Text = dialog.SelectedPath;
    }

    private async void RpCreateClick(object sender, RoutedEventArgs e)
    {
        var destination = RpPath.Text.Trim();
        if (!File.Exists(RestorePoints.WimlibPath)) { System.Windows.MessageBox.Show(this, T("缺少 wimlib（tools\\bin\\wimlib-imagex.exe）。请先点击“设置恢复环境”，软件会自动下载。", "wimlib (tools\\bin\\wimlib-imagex.exe) is missing. Click “Set up recovery” first; it is downloaded automatically."), "RestoreNest"); return; }
        if (System.Windows.MessageBox.Show(this, T($"将把 Windows 分区映像保存到 {destination}。耗时取决于数据量。继续吗？", $"The Windows partition will be imaged to {destination}. This can take a while. Continue?"), "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        SetRestoreBusy(true); RpLogExpander.IsExpanded = true; RpOutput.Text = T("正在创建还原点…\n", "Creating restore point…\n");
        try
        {
            var args = new List<string> { "-Destination", destination, "-WimlibPath", RestorePoints.WimlibPath, "-Verbose" };
            if (!string.IsNullOrWhiteSpace(RpName.Text)) { args.Add("-Name"); args.Add(RpName.Text.Trim()); }
            var result = await RestorePoints.RunScriptAsync("New-RestorePoint.ps1", args, RpLog);
            RpLog(result.ExitCode == 0 ? T("\n还原点已创建。", "\nRestore point created.") : T($"\n创建失败（退出代码 {result.ExitCode}）。", $"\nCreation failed (exit code {result.ExitCode})."));
            await RpLoadAsync(false);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { RpLog(ex.Message); }
        finally { SetRestoreBusy(false); }
    }

    private async void RpInstallBootClick(object sender, RoutedEventArgs e)
    {
        var root = RpPath.Text.Trim().TrimEnd('\\');
        if (AutoProtection.CheckDestination(root.Length == 2 ? root + "\\" : root) is { } problem) { System.Windows.MessageBox.Show(this, ScheduleProblemText("destination:" + problem), "RestoreNest"); return; }
        if (root.Length == 2) root += @"\RestoreNest";
        var message = T("将为“还原电脑”准备恢复环境：\n\n•  如果这台电脑上还没有，会从官方网站下载并安装 wimlib 和微软 Windows ADK。需要联网，下载约 1 到 3 GB，整个过程可能需要 20 到 60 分钟，请保持电脑接通电源。\n•  构建恢复环境，并在启动菜单里添加“RestoreNest Recovery”（默认系统和启动顺序不变，添加前会备份启动配置）。\n•  如果启用了 BitLocker，修改启动配置后下次启动可能要求输入恢复密钥，请先确认你有这个密钥。\n\n继续吗？",
            "Recovery will be prepared for “Restore your PC”:\n\n•  If this PC does not have them yet, wimlib and the Microsoft Windows ADK are downloaded from their official sites and installed. This needs internet, downloads about 1 to 3 GB and can take 20 to 60 minutes; keep the PC plugged in.\n•  The recovery environment is built and a “RestoreNest Recovery” entry is added to the boot menu (the default OS and boot order do not change; the boot configuration is backed up first).\n•  If BitLocker is on, the next boot may ask for the recovery key after the boot configuration changes; make sure you have it.\n\nContinue?");
        if (System.Windows.MessageBox.Show(this, message, "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        await RunPrepareAsync(root);
    }

    private async Task RunPrepareAsync(string root)
    {
        SetRestoreBusy(true); RpLogExpander.IsExpanded = true; RpOutput.Text = "";
        var failed = false;
        try
        {
            var result = await RestorePoints.RunScriptAsync("Prepare-Recovery.ps1", new[] { "-Root", root, "-Language", English ? "en" : "zh" }, line =>
            {
                RpLog(line);
                if (RestorePoints.ParseStep(line) is { } step) Dispatcher.BeginInvoke(() => RpEnvStatus.Text = RestorePoints.StepText(step, English));
            });
            failed = result.ExitCode != 0;
            RpLog(failed ? T($"\n没有完成（退出代码 {result.ExitCode}）。请查看上面的信息。", $"\nNot finished (exit code {result.ExitCode}). See the messages above.") : T("\n恢复环境已准备好。", "\nThe recovery environment is ready."));
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { failed = true; RpLog(ex.Message); }
        finally { SetRestoreBusy(false); RefreshEnvStatus(); }
        if (failed) System.Windows.MessageBox.Show(this, T("恢复环境没有准备好。详细信息在页面下方的“详细输出”里。", "The recovery environment could not be prepared. The details are in “Details” at the bottom of the page."), "RestoreNest", MessageBoxButton.OK, MessageBoxImage.Warning);
    }

    private void RefreshEnvStatus()
    {
        var root = RpPath.Text.Trim().TrimEnd('\\');
        if (root.Length == 2) root += @"\RestoreNest";
        var ready = root.Length > 2 && root[1] == ':' && File.Exists(Path.Combine(root, "boot", "bootentry.json")) && File.Exists(Path.Combine(root, "boot", "boot.wim"));
        RpRecoverNowButton.Visibility = ready ? Visibility.Visible : Visibility.Collapsed;
        RpInstallBootButton.Content = ready ? T("重新设置", "Set up again") : T("设置恢复环境", "Set up recovery");
        RpInstallBootButton.Style = ready ? null : (Style)FindResource("Primary");
        RpEnvStatus.Text = ready
            ? T("已准备好。系统出问题时，可以从启动菜单进入恢复环境。", "Ready. If Windows breaks, start it from the boot menu.")
            : T("还没有准备。点击“设置恢复环境”。没有它，系统起不来时就无法还原。", "Not set up yet. Click “Set up recovery”. Without it you cannot restore when Windows will not start.");
    }

    // The recovery screen shows the language chosen in this app; keep it in step when the language is switched later.
    private void SyncBootLanguage()
    {
        try
        {
            var root = RpPath.Text.Trim().TrimEnd('\\');
            if (root.Length == 2) root += @"\RestoreNest";
            var boot = Path.Combine(root, "boot");
            if (File.Exists(Path.Combine(boot, "bootentry.json"))) File.WriteAllText(Path.Combine(boot, "language.txt"), English ? "en" : "zh");
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException) { }
    }

    private async void RpRemoveBootClick(object sender, RoutedEventArgs e)
    {
        var root = RpPath.Text.Trim().TrimEnd('\\');
        if (root.Length == 2) root += @"\RestoreNest";
        await RunBootScriptAsync(new[] { "-Root", root, "-Remove" });
    }

    private async Task RunBootScriptAsync(string[] args)
    {
        SetRestoreBusy(true); RpOutput.Text = "";
        try
        {
            var result = await RestorePoints.RunScriptAsync("Install-BootEntry.ps1", args, RpLog);
            RpLog(result.ExitCode == 0 ? T("\n完成。", "\nDone.") : T($"\n失败（退出代码 {result.ExitCode}）。", $"\nFailed (exit code {result.ExitCode})."));
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or System.ComponentModel.Win32Exception) { RpLog(ex.Message); }
        finally { SetRestoreBusy(false); RefreshEnvStatus(); }
    }
}
