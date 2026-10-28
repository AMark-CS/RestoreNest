using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace SystemCare;

public partial class MainWindow : Window
{
    private readonly List<InstalledApp> apps;
    private bool English => LanguagePicker.SelectedIndex == 1;
    private string T(string zh, string en) => English ? en : zh;

    public MainWindow()
    {
        InitializeComponent();
        apps = InstalledApps.Get();
        RefreshText();
        FilterApps();
    }

    private void LanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (IsInitialized) RefreshText();
    }

    private void RefreshText()
    {
        Intro.Text = T("系统维护与恢复 · 开发预览版", "System maintenance and recovery · development preview");
        AppsTab.Header = T("软件管理", "Apps"); BackupTab.Header = T("系统备份", "Backup"); RecoveryTab.Header = T("恢复与启动", "Recovery & boot");
        NameColumn.Header = T("名称", "Name"); PublisherColumn.Header = T("发布者", "Publisher"); VersionColumn.Header = T("版本", "Version");
        AppsNotice.Text = T("目前仅提供软件清单。强制删除及 360 专项适配尚未完成，无法执行删除。", "Inventory only. Forced removal and 360-specific handling are not implemented; removal is unavailable.");
        BackupTitle.Text = T("选择备份位置", "Choose a backup location"); PathLabel.Text = T("保存目录", "Destination folder"); Browse.Content = T("浏览…", "Browse…");
        BackupNotice.Text = T("备份引擎尚未完成；此页面只检查路径，不会创建备份。请使用经过验证的备份工具保护重要数据。", "The backup engine is not implemented. This page only checks the path and does not create a backup. Use a verified backup tool for important data.");
        RecoveryNotice.Text = T("恢复引擎、启动菜单和 USB 恢复介质尚未实现，当前版本不能恢复系统。", "The recovery engine, boot menu and USB recovery media are not implemented. This version cannot restore a system.");
        CheckPath();
    }

    private void SearchChanged(object sender, TextChangedEventArgs e) { if (IsInitialized) FilterApps(); }
    private void FilterApps()
    {
        var query = Search.Text.Trim();
        AppList.ItemsSource = apps.Where(a => a.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase) || a.Publisher.Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToList();
    }

    private void PathChanged(object sender, TextChangedEventArgs e) { if (IsInitialized) CheckPath(); }
    private void CheckPath()
    {
        var path = BackupPath.Text.Trim();
        var error = BackupLocation.Validate(path, Path.GetPathRoot(Environment.GetFolderPath(Environment.SpecialFolder.Windows)) ?? @"C:\");
        PathStatus.Text = error switch
        {
            "system" => T("不能使用 Windows 所在分区。", "The Windows partition cannot be used."),
            "network" => T("当前不支持网络路径。", "Network paths are not supported."),
            "absolute" => T("请选择完整的本地路径。", "Choose an absolute local path."),
            _ when !Directory.Exists(Path.GetPathRoot(path)) => T("所选磁盘不可用。", "The selected drive is unavailable."),
            _ => T("路径格式有效。开始备份前仍需检查空间、权限和恢复范围。", "Path format is valid. Space, permissions and restore scope still require verification.")
        };
    }

    private void BrowseClick(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog { Description = T("选择备份文件夹", "Choose a backup folder"), UseDescriptionForTitle = true };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK) BackupPath.Text = dialog.SelectedPath;
    }
}
