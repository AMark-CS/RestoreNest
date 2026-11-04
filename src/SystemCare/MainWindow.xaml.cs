using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace SystemCare;

public partial class MainWindow : Window
{
    private List<AppChoice> apps = new();
    private bool English;
    private string T(string zh, string en) => English ? en : zh;

    public MainWindow()
    {
        InitializeComponent();
        InitSchedule();
        RefreshText();
        RefreshDisks();
        _ = LoadAppsAsync();
        _ = RpLoadAsync(false);
        _ = RefreshScheduleStatusAsync();
        _ = LoadBitLockerAsync();
    }

    private void LanguageClick(object sender, RoutedEventArgs e)
    {
        English = !English;
        RefreshText(); RefreshDisks();
        SyncBootLanguage();
    }

    private void NavChanged(object sender, RoutedEventArgs e)
    {
        if (!IsInitialized) return;
        RestorePage.Visibility = NavRestore.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        AppsPage.Visibility = NavApps.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        DisksPage.Visibility = NavDisks.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshText()
    {
        LanguageButton.Content = English ? "简体中文" : "English";
        Tagline.Text = T("系统维护与恢复", "Maintenance & recovery");
        VersionText.Text = "v" + (System.Reflection.Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0") + T(" · 预览版", " · preview");
        NavRestore.Content = T("还原点", "Restore points"); NavApps.Content = T("软件管理", "Apps"); NavDisks.Content = T("磁盘概览", "Disks");
        RefreshRestoreText();

        AppsTitle.Text = T("软件管理", "Apps");
        AppsSubtitle.Text = T("勾选要卸载的软件。卸载前会尝试创建系统还原点；卸载后列出残留候选，由你确认再删除。", "Tick the apps to remove. A system restore point is attempted first; leftover candidates are listed for you to confirm.");
        Search.ToolTip = T("按名称或发布者搜索", "Search by name or publisher");
        Search.Tag = T("搜索软件名称或发布者", "Search apps by name or publisher");
        NameColumn.Header = T("名称", "Name"); PublisherColumn.Header = T("发布者", "Publisher"); VersionColumn.Header = T("版本", "Version"); SizeColumn.Header = T("大小", "Size");
        UninstallButton.Content = T("卸载所选软件", "Uninstall selected"); ReviewButton.Content = T("检查所选软件", "Review selection");

        DisksTitle.Text = T("磁盘概览", "Disks"); DisksSubtitle.Text = T("各磁盘的已用空间与剩余空间", "Used and free space of each drive");
        RefreshDisksButton.Content = T("刷新", "Refresh");
        DiskVolume.FreeWord = T("可用", "free");
        DiskWords.System = T("Windows 系统盘", "Windows");
        DiskWords.Removable = T("可移动", "Removable"); DiskWords.Network = T("网络", "Network");
        DiskWords.RestoreFormat = T("{0} 个还原点 · {1}", "{0} restore points · {1}");
        DiskWords.DiskFormat = T("磁盘 {0}", "Disk {0}");
        DiskWords.UsageFormat = T("已用 {0}（{1}%），共 {2}", "{0} used ({1}%) of {2}");
        SumTotalLabel.Text = T("总容量", "Total capacity"); SumUsedLabel.Text = T("已使用", "Used"); SumFreeLabel.Text = T("剩余", "Free");
        UpdateSelectionCount();
    }

    private void SearchChanged(object sender, TextChangedEventArgs e) { if (IsInitialized) FilterApps(); }
    private void FilterApps()
    {
        var query = Search.Text.Trim();
        AppList.ItemsSource = apps.Where(a => (a.App.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase) || a.App.Publisher.Contains(query, StringComparison.CurrentCultureIgnoreCase))).ToList();
    }

    private void SelectionChanged(object sender, RoutedEventArgs e)
    {
        if (IsInitialized) Dispatcher.BeginInvoke(UpdateSelectionCount);
    }

    private void UpdateSelectionCount()
    {
        var count = apps.Count(choice => choice.IsSelected);
        SelectionCount.Text = T($"已勾选 {count} 项", $"{count} selected");
        if (!apps.Any()) return;
        AppsNotice.Text = T($"共 {apps.Count} 个软件（已勾选项目不受搜索过滤影响）", $"{apps.Count} apps (selection is kept while you search)");
    }

    private void ReviewClick(object sender, RoutedEventArgs e)
    {
        var selected = apps.Where(choice => choice.IsSelected).Select(choice => choice.App).ToList();
        if (selected.Count == 0)
        {
            System.Windows.MessageBox.Show(this, T("请先选择软件。", "Select one or more apps first."), "RestoreNest");
            return;
        }
        var protectedPaths = ProtectedTrees(); var protectedRoots = ProtectedRoots();
        var report = new System.Text.StringBuilder();
        foreach (var app in selected)
        {
            var status = RemovalReview.Assess(app.Location, apps.Select(choice => choice.App).Where(other => !ReferenceEquals(app, other)).Select(other => other.Location), protectedPaths, protectedRoots);
            var message = status switch
            {
                "unknown" => T("安装位置未知或格式无效", "Location unknown or invalid"),
                "root" => T("磁盘根目录，禁止直接删除", "Drive root; direct deletion prohibited"),
                "protected" => T("位于系统或受保护目录，禁止直接删除", "System or protected path; direct deletion prohibited"),
                "shared" => T("与其他软件的安装位置重叠", "Location overlaps another app"),
                _ => T("归属尚未验证，不可直接删除", "Ownership unverified; do not delete directly")
            };
            report.AppendLine(app.Name).AppendLine(string.IsNullOrWhiteSpace(app.Location) ? "—" : app.Location).AppendLine(message).AppendLine();
        }
        report.Append(T("此检查仅供审查，不会删除任何文件。", "Review only; no files will be deleted."));
        System.Windows.MessageBox.Show(this, report.ToString(), T("软件位置检查", "App location review"));
    }
}
