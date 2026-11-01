using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace SystemCare;

public partial class MainWindow
{
    private async Task LoadAppsAsync()
    {
        AppsNotice.Text = T("正在读取软件列表…", "Loading installed apps…");
        var list = await Task.Run(InstalledApps.Get);
        list.AddRange(await AppxApps.GetAsync());
        apps = list.OrderBy(x => x.Name, StringComparer.CurrentCultureIgnoreCase).Select(app => new AppChoice(app)).ToList();
        RefreshText();
        FilterApps();
    }

    private void RefreshDisks() => DiskList.ItemsSource = DiskOverview.Get();
    private void RefreshDisksClick(object sender, RoutedEventArgs e) => RefreshDisks();

    private static string[] ProtectedTrees() => new[] { Environment.GetFolderPath(Environment.SpecialFolder.Windows) }.Where(p => !string.IsNullOrEmpty(p)).ToArray();

    // Folders where apps and their data legitimately live: the folder itself (and its parents) is protected, its children are not.
    private static string[] ProtectedRoots() => new[]
    {
        Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData)
    }.Where(p => !string.IsNullOrEmpty(p)).ToArray();

    private async void UninstallClick(object sender, RoutedEventArgs e)
    {
        var selected = apps.Where(choice => choice.IsSelected).Select(choice => choice.App).ToList();
        if (selected.Count == 0) { System.Windows.MessageBox.Show(this, T("请先选择软件。", "Select one or more apps first."), "RestoreNest"); return; }
        var names = string.Join("\n", selected.Select(a => "• " + a.Name));
        if (System.Windows.MessageBox.Show(this, T($"将依次卸载：\n{names}\n\n部分卸载程序会弹出自己的窗口。继续吗？", $"These will be uninstalled one by one:\n{names}\n\nSome uninstallers show their own windows. Continue?"), "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        UninstallButton.IsEnabled = false; ReviewButton.IsEnabled = false;
        try
        {
            AppsNotice.Text = T("正在创建系统还原点…", "Creating a restore point…");
            var point = await Uninstaller.CreateRestorePointAsync("before uninstall");
            if (!point.Ok && System.Windows.MessageBox.Show(this, T("未能创建系统还原点（可能被系统限流或已禁用）：\n", "Could not create a restore point (throttled or disabled):\n") + point.Message + T("\n\n仍要继续卸载吗？", "\n\nContinue without it?"), "RestoreNest", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
            var report = new System.Text.StringBuilder();
            foreach (var app in selected)
            {
                AppsNotice.Text = T($"正在卸载 {app.Name}…", $"Uninstalling {app.Name}…");
                try
                {
                    int exit;
                    if (app.AppxPackage.Length > 0) exit = await AppxApps.RemoveAsync(app.AppxPackage);
                    else
                    {
                        var plan = Uninstaller.Plan(app);
                        if (plan is null) { report.AppendLine($"{app.Name}: " + T("没有可用的卸载命令", "no usable uninstall command")); continue; }
                        exit = await Uninstaller.RunAsync(plan);
                    }
                    report.AppendLine($"{app.Name}: " + (exit is 0 or 3010 or 1641 ? T("完成", "done") : T($"退出代码 {exit}", $"exit code {exit}")));
                }
                catch (Exception ex) when (ex is IOException or InvalidOperationException or ArgumentException or System.ComponentModel.Win32Exception)
                {
                    report.AppendLine($"{app.Name}: " + ex.Message);
                }
            }
            System.Windows.MessageBox.Show(this, report.ToString(), T("卸载结果", "Uninstall results"));
            await LoadAppsAsync();
            var gone = selected.Where(a => !apps.Any(c => c.App.Name == a.Name && c.App.UninstallString == a.UninstallString && c.App.AppxPackage == a.AppxPackage)).ToList();
            ShowLeftovers(gone);
        }
        finally { UninstallButton.IsEnabled = true; ReviewButton.IsEnabled = true; UpdateSelectionCount(); }
    }

    private void ShowLeftovers(List<InstalledApp> removed)
    {
        var others = apps.Select(c => c.App.Location).ToList();
        var candidates = removed.SelectMany(a => LeftoverScanner.Scan(a, others, ProtectedTrees(), ProtectedRoots())).ToList();
        if (candidates.Count == 0) return;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock { Text = T("以下目录可能是卸载后的残留，勾选后删除（默认不勾选）：", "These folders may be leftovers. Tick the ones to delete (none are ticked by default):"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) });
        var boxes = candidates.Select(c => new System.Windows.Controls.CheckBox { Content = c.Path, Tag = c, Margin = new Thickness(0, 2, 0, 2) }).ToList();
        foreach (var box in boxes) panel.Children.Add(box);
        var ok = new System.Windows.Controls.Button { Content = T("删除所选", "Delete selected"), Padding = new Thickness(14, 6, 14, 6), Margin = new Thickness(0, 12, 0, 0), HorizontalAlignment = System.Windows.HorizontalAlignment.Left };
        var window = new Window { Title = T("残留文件", "Leftovers"), Content = new ScrollViewer { Content = panel }, Width = 640, Height = 380, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        ok.Click += (_, _) =>
        {
            var failed = new List<string>();
            foreach (var box in boxes.Where(b => b.IsChecked == true))
            {
                try { LeftoverScanner.Delete((Leftover)box.Tag); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { failed.Add(box.Content + ": " + ex.Message); }
            }
            if (failed.Count > 0) System.Windows.MessageBox.Show(window, string.Join("\n", failed), "RestoreNest");
            window.Close();
        };
        panel.Children.Add(ok);
        window.ShowDialog();
    }
}
