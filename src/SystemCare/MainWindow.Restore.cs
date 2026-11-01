using System.IO;
using System.Windows;

namespace SystemCare;

public partial class MainWindow
{
    private bool restoreBusy;

    private void RefreshRestoreText()
    {
        RestorePointsTab.Header = T("还原点", "Restore points");
        RpTitle.Text = T("创建与管理还原点", "Create and manage restore points");
        RpPathLabel.Text = T("保存位置（非 Windows 分区的盘符或文件夹，可与 C 盘在同一块物理磁盘上）", "Storage location (a non-Windows drive or folder; may share the physical disk with C:)");
        RpName.ToolTip = T("还原点名称（可选）", "Restore point name (optional)");
        RpCreateButton.Content = T("创建还原点", "Create restore point"); RpRefreshButton.Content = T("刷新列表", "Refresh");
        RpVerifyButton.Content = T("校验全部", "Verify all"); RpInstallBootButton.Content = T("安装启动菜单项…", "Install boot menu entry…"); RpRemoveBootButton.Content = T("移除启动菜单项", "Remove boot menu entry");
        RpIdColumn.Header = T("编号", "Id"); RpNameColumn.Header = T("名称", "Name"); RpCreatedColumn.Header = T("创建时间", "Created"); RpSizeColumn.Header = T("大小", "Size"); RpStatusColumn.Header = T("状态", "Status");
        RpNotice.Text = T("实验性：创建使用 VSS 快照加 WIM 映像。还原需在启动菜单“RestoreNest Recovery”（WinPE）中执行，尚未在虚拟机中完整验证，请勿依赖其保护重要数据。需要 tools\\bin\\wimlib-imagex.exe。",
            "Experimental: creation uses a VSS snapshot and a WIM image. Restoring runs from the 'RestoreNest Recovery' (WinPE) boot entry and is not yet fully validated in a VM; do not rely on it for important data. Requires tools\\bin\\wimlib-imagex.exe.");
    }

    private void SetRestoreBusy(bool busy)
    {
        restoreBusy = busy;
        foreach (var button in new[] { RpCreateButton, RpRefreshButton, RpVerifyButton, RpInstallBootButton, RpRemoveBootButton }) button.IsEnabled = !busy;
        RpProgress.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RpLog(string line) => Dispatcher.BeginInvoke(() =>
    {
        if (RpOutput.Text.Length > 20000) RpOutput.Text = RpOutput.Text[^10000..];
        RpOutput.AppendText(line + "\n"); RpOutput.ScrollToEnd();
    });

    private async Task RpLoadAsync(bool verify)
    {
        try
        {
            var list = await RestorePoints.ListAsync(RpPath.Text.Trim(), verify);
            RpList.ItemsSource = list;
            RpOutput.Text = list.Count == 0 ? T("此位置没有还原点。", "No restore points at this location.") : "";
        }
        catch (Exception ex) when (ex is InvalidOperationException or IOException or System.ComponentModel.Win32Exception)
        {
            RpList.ItemsSource = null;
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
        if (!File.Exists(RestorePoints.WimlibPath)) { System.Windows.MessageBox.Show(this, T("缺少 tools\\bin\\wimlib-imagex.exe。", "tools\\bin\\wimlib-imagex.exe is missing."), "RestoreNest"); return; }
        if (System.Windows.MessageBox.Show(this, T($"将把 Windows 分区映像保存到 {destination}。耗时取决于数据量。继续吗？", $"The Windows partition will be imaged to {destination}. This can take a while. Continue?"), "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        SetRestoreBusy(true); RpOutput.Text = T("正在创建还原点…\n", "Creating restore point…\n");
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
        var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "boot.wim|boot.wim", Title = T("选择 Build-WinPE.ps1 生成的 boot.wim（同目录需有 boot.sdi）", "Choose the boot.wim built by Build-WinPE.ps1 (boot.sdi must sit beside it)") };
        if (dialog.ShowDialog(this) != true) return;
        var sdi = Path.Combine(Path.GetDirectoryName(dialog.FileName)!, "boot.sdi");
        var root = RpPath.Text.Trim().TrimEnd('\\');
        if (root.Length == 2) root += @"\RestoreNest";
        if (System.Windows.MessageBox.Show(this, T("将向启动菜单添加“RestoreNest Recovery”项（不改变默认系统），并先导出 BCD 备份。若启用了 BitLocker，下次启动可能要求恢复密钥。继续吗？", "A 'RestoreNest Recovery' entry will be added to the boot menu (default OS unchanged) after exporting a BCD backup. With BitLocker on, the next boot may ask for the recovery key. Continue?"), "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        await RunBootScriptAsync(new[] { "-Root", root, "-BootWim", dialog.FileName, "-BootSdi", sdi });
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
        finally { SetRestoreBusy(false); }
    }
}
