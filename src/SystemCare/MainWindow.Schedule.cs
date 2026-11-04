using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace SystemCare;

// The "automatic restore points" card: how often, at what time and how many to keep. The scheduling itself is done by a Task
// Scheduler job (tools\Set-RestoreSchedule.ps1); this only edits tools\..\schedule.json and registers it.
public partial class MainWindow
{
    private static readonly int[] KeepChoices = { 1, 2, 3, 4, 5, 7, 10, 15, 20, 30 };
    private ScheduleSettings schedule = ScheduleSettings.Default;
    private ScheduleStatus? scheduleStatus;
    private List<int> keepValues = new();
    private bool scheduleFilling, scheduleBusy;

    private void InitSchedule()
    {
        schedule = AutoProtection.Load();
        if (schedule.Enabled && schedule.Destination.Length > 0) RpPath.Text = schedule.Destination;
        AutoEnabled.IsChecked = schedule.Enabled;
    }

    private void RefreshScheduleText()
    {
        AutoEnabled.Content = T("自动创建还原点", "Create restore points automatically");
        AutoHint.Text = T("到时间会在后台自动创建，期间可以照常使用电脑。超过保留个数的最旧还原点会被自动删除；磁盘空间不够时也会先删最旧的，但始终保留最新的一个。保存在上面“保存位置”所选的磁盘。",
            "At the chosen time a restore point is created in the background; you can keep using the PC. Restore points beyond the number to keep are deleted, oldest first; when the drive is too full the oldest are deleted too, but the newest one is always kept. They are stored in the location chosen above.");
        AutoFrequencyLabel.Text = T("多久一次", "How often");
        AutoDayLabel.Text = T("星期几", "Day of the week");
        AutoMonthLabel.Text = T("每月几号", "Day of the month");
        AutoTimeLabel.Text = T("几点开始", "Start time");
        AutoKeepLabel.Text = T("保留", "Keep");
        AutoOnlyAc.Content = T("仅在接通电源时运行（笔记本建议勾选）", "Only when plugged in (recommended for laptops)");
        AutoSaveButton.Content = T("保存设置", "Save settings");
        FillScheduleCombos(keepSelection: AutoFrequency.Items.Count > 0);
        AutoStatus.Text = AutoProtection.Describe(schedule, scheduleStatus, English);
    }

    // Fills the drop-downs in the current language. The first time they take their values from the saved settings; later
    // (language switch) the current selection is kept.
    private void FillScheduleCombos(bool keepSelection)
    {
        scheduleFilling = true;
        int frequency = keepSelection ? AutoFrequency.SelectedIndex : Math.Max(0, Array.IndexOf(ScheduleSettings.Frequencies, schedule.Frequency));
        int day = keepSelection ? AutoDay.SelectedIndex : Math.Max(0, Array.IndexOf(ScheduleSettings.WeekDays, schedule.DayOfWeek));
        int month = keepSelection ? AutoMonthDay.SelectedIndex : schedule.DayOfMonth - 1;
        string time = keepSelection ? (AutoTime.SelectedItem as string ?? schedule.Time) : schedule.Time;
        int keep = keepSelection && AutoKeep.SelectedIndex >= 0 && AutoKeep.SelectedIndex < keepValues.Count ? keepValues[AutoKeep.SelectedIndex] : schedule.Keep;

        AutoFrequency.Items.Clear();
        foreach (var item in English ? new[] { "Daily", "Every 3 days", "Weekly", "Every 2 weeks", "Monthly" } : new[] { "每天", "每 3 天", "每周", "每两周", "每月" }) AutoFrequency.Items.Add(item);
        AutoDay.Items.Clear();
        foreach (var item in English ? new[] { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" } : new[] { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }) AutoDay.Items.Add(item);
        AutoMonthDay.Items.Clear();
        for (var d = 1; d <= 28; d++) AutoMonthDay.Items.Add(English ? $"Day {d}" : $"{d} 号");
        AutoTime.Items.Clear();
        for (var i = 0; i < 48; i++) AutoTime.Items.Add($"{i / 2:00}:{i % 2 * 30:00}");
        if (!AutoTime.Items.Contains(time)) AutoTime.Items.Add(time);   // a value saved by hand-editing the file
        keepValues = KeepChoices.ToList();
        if (!keepValues.Contains(keep)) { keepValues.Add(keep); keepValues.Sort(); }
        AutoKeep.Items.Clear();
        foreach (var n in keepValues) AutoKeep.Items.Add(English ? $"Latest {n}" : $"最近 {n} 个");

        AutoFrequency.SelectedIndex = Math.Clamp(frequency, 0, 4);
        AutoDay.SelectedIndex = Math.Clamp(day, 0, 6);
        AutoMonthDay.SelectedIndex = Math.Clamp(month, 0, 27);
        AutoTime.SelectedItem = time;
        AutoKeep.SelectedIndex = keepValues.IndexOf(keep);
        AutoOnlyAc.IsChecked = keepSelection ? AutoOnlyAc.IsChecked : schedule.OnlyOnAC;
        scheduleFilling = false;
        UpdateSchedulePanels();
    }

    private void UpdateSchedulePanels()
    {
        var frequency = Math.Max(0, AutoFrequency.SelectedIndex);
        AutoDayPanel.Visibility = frequency is 2 or 3 ? Visibility.Visible : Visibility.Collapsed;
        AutoMonthPanel.Visibility = frequency == 4 ? Visibility.Visible : Visibility.Collapsed;
        AutoOptions.IsEnabled = AutoEnabled.IsChecked == true;
    }

    private void AutoEnabledChanged(object sender, RoutedEventArgs e) { if (IsInitialized) { UpdateSchedulePanels(); ShowScheduleDirty(); } }
    private void AutoFrequencyChanged(object sender, SelectionChangedEventArgs e) { if (IsInitialized && !scheduleFilling) { UpdateSchedulePanels(); ShowScheduleDirty(); } }
    private void AutoOptionChanged(object sender, RoutedEventArgs e) { if (IsInitialized && !scheduleFilling) ShowScheduleDirty(); }

    // Until "Save settings" is clicked nothing changes in Task Scheduler; say so instead of describing the old state.
    private void ShowScheduleDirty()
    {
        if (AutoStatus is null || AutoFrequency.Items.Count == 0) return;
        var now = ReadSchedule();
        var changed = now.Enabled != schedule.Enabled || (now.Enabled && now != schedule);
        AutoStatus.Text = changed
            ? T("有未保存的更改，点击“保存设置”后才会生效。", "Unsaved changes. Click “Save settings” to apply them.")
            : AutoProtection.Describe(schedule, scheduleStatus, English);
    }

    private ScheduleSettings ReadSchedule() => new(
        AutoEnabled.IsChecked == true,
        ScheduleSettings.Frequencies[Math.Clamp(AutoFrequency.SelectedIndex, 0, 4)],
        AutoTime.SelectedItem as string ?? "02:00",
        ScheduleSettings.WeekDays[Math.Clamp(AutoDay.SelectedIndex, 0, 6)],
        Math.Clamp(AutoMonthDay.SelectedIndex + 1, 1, 28),
        AutoKeep.SelectedIndex >= 0 && AutoKeep.SelectedIndex < keepValues.Count ? keepValues[AutoKeep.SelectedIndex] : 3,
        RpPath.Text.Trim(),
        AutoOnlyAc.IsChecked == true);

    private string ScheduleProblemText(string problem) => problem switch
    {
        "destination:format" => T("请先在上方“保存位置”填写本地盘符，例如 D:\\。", "Enter a local drive such as D:\\ in “Storage location” above first."),
        "destination:windows-drive" => T("保存位置不能在 Windows 所在的分区，请选择其他分区。", "The storage location cannot be on the Windows partition."),
        "destination:not-ready" => T("所选磁盘不可用，请确认已连接。", "The selected drive is unavailable; make sure it is connected."),
        "destination:not-ntfs" => T("保存位置必须是 NTFS 格式的磁盘。", "The storage location must be an NTFS drive."),
        _ => T("设置不正确，请检查后重试。", "The settings are not valid; please check them.")
    };

    private async void AutoSaveClick(object sender, RoutedEventArgs e)
    {
        if (scheduleBusy) return;
        var wanted = ReadSchedule();
        if (wanted.Validate() is { } problem) { System.Windows.MessageBox.Show(this, ScheduleProblemText(problem), "RestoreNest"); return; }
        if (wanted.Enabled && !File.Exists(RestorePoints.WimlibPath))
        {
            System.Windows.MessageBox.Show(this, T("缺少 wimlib，无法自动创建还原点。请先点击下方列表上的“设置恢复环境”，软件会自动下载。", "wimlib is missing, so restore points cannot be created automatically. Click “Set up recovery” above the list first; it is downloaded automatically."), "RestoreNest");
            return;
        }
        scheduleBusy = true; AutoSaveButton.IsEnabled = false; AutoStatus.Text = T("正在保存…", "Saving…");
        try
        {
            var result = await AutoProtection.ApplyAsync(wanted);
            if (result.Ok) schedule = wanted;
            else System.Windows.MessageBox.Show(this, T("保存失败：", "Could not save: ") + result.Message, "RestoreNest");
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception)
        {
            System.Windows.MessageBox.Show(this, T("保存失败：", "Could not save: ") + ex.Message, "RestoreNest");
        }
        finally { scheduleBusy = false; AutoSaveButton.IsEnabled = true; }
        await RefreshScheduleStatusAsync();
    }

    private async Task RefreshScheduleStatusAsync()
    {
        try
        {
            var status = await AutoProtection.GetStatusAsync();
            // The app (and so the scripts) was moved or updated: point the task at this copy again.
            if (status is not null && schedule.Enabled && AutoProtection.TaskPointsElsewhere(status))
            {
                await AutoProtection.ApplyAsync(schedule);
                status = await AutoProtection.GetStatusAsync();
            }
            scheduleStatus = status;
            AutoStatus.Text = AutoProtection.Describe(schedule, status, English);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException or UnauthorizedAccessException or System.ComponentModel.Win32Exception) { AutoStatus.Text = ex.Message; }
    }
}
