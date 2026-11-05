<#
.SYNOPSIS
  Full-screen recovery screen for the RestoreNest WinPE: pick a point in time, confirm in plain words, watch the progress.
.DESCRIPTION
  A thin front end over Restore.ps1: it lists the restore points, asks for the BitLocker recovery password when the Windows
  partition is locked, and then runs `Restore.ps1 -Execute` and shows its progress. It contains no restore logic of its own.
  Exit codes: 0 finished (or the user restarted), 2 the user asked for the command line, anything else means the screen could
  not start and the caller should fall back to the text version (.\Restore.ps1).
  -Demo uses made-up restore points and a fake restore; -SnapshotDir renders every screen to PNG files (used for checking the layout).
#>
[CmdletBinding()]
param([string]$WimlibPath, [ValidateSet('', 'zh', 'en')][string]$Language = '', [switch]$Demo, [string]$SnapshotDir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# An error in any event handler would otherwise open the .NET "Unhandled exception" dialog (Details/Continue/Quit) in the recovery
# environment. A handler added below closes the screen with exit code 2 instead, and startnet.cmd then opens the text restore.
# (This has to run before the first control exists.)
[Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException)
. (Join-Path $PSScriptRoot 'RestorePoint.Common.ps1')
. (Join-Path $PSScriptRoot 'RestorePlan.Common.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- restore points
function Get-GuiRoots {
    if ($Demo) { return @('D:\RestoreNest') }
    @(Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -eq 'NTFS' } | ForEach-Object { "$($_.DriveLetter):\RestoreNest" } | Where-Object { Test-Path -LiteralPath $_ })
}
function Get-GuiPoints {
    if ($Demo) {
        return @(
            [pscustomobject]@{ Root = 'D:\RestoreNest'; Id = '20261103-143000'; Name = 'Auto 2026-11-03'; GiB = 5.4 },
            [pscustomobject]@{ Root = 'D:\RestoreNest'; Id = '20261027-020000'; Name = 'Auto 2026-10-27'; GiB = 5.1 },
            [pscustomobject]@{ Root = 'D:\RestoreNest'; Id = '20261020-094512'; Name = 'before driver update'; GiB = 4.9 })
    }
    $found = @()
    foreach ($root in Get-GuiRoots) { foreach ($p in @(Get-RnRestorePoints -Root $root)) { $found += [pscustomobject]@{ Root = $root; Id = $p.Id; Name = [string]$p.Meta.name; GiB = [math]::Round($p.Meta.wim.sizeBytes / 1GB, 1) } } }
    @($found | Sort-Object Id -Descending)
}
# The id is the capture time in the PC's own clock; the UTC time in meta.json cannot be shown because WinPE does not know the time zone.
function ConvertTo-GuiTime($id) { [datetime]::ParseExact($id, 'yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture) }

if (-not $Language) {
    $Language = 'en'
    foreach ($root in Get-GuiRoots) {
        $file = Join-Path $root 'boot\language.txt'
        if (Test-Path -LiteralPath $file) { $text = (Get-Content -LiteralPath $file -Raw).Trim(); if ($text -in 'zh', 'en') { $Language = $text; break } }
    }
}

# ---------------------------------------------------------------- texts
$text = @{
    zh = @{
        title = '还原电脑'; sub = '选择要回到的时间点。只有 Windows 所在的分区会被还原，其他磁盘分区里的文件不会改变。'
        colTime = '时间点'; colSize = '大小'; colName = '名称'
        restore = '还原到所选时间点'; reboot = '不还原，重新启动'; advanced = '高级（命令行）'
        noPoints = '没有找到还原点。请确认保存还原点的磁盘已经连接，然后点击“重新查找”。'; rescan = '重新查找'
        confirmTitle = '确认还原'
        confirmBody = "Windows 所在的 C: 盘将回到 {0} 的状态。`r`n`r`n•  这个时间之后，在 C: 盘上新建或修改的内容都会丢失，包括桌面、文档、下载文件夹，以及之后安装的软件。`r`n•  其他分区里的文件（例如保存还原点的 {1}: 盘）不会改变。`r`n•  还原需要一段时间，请保持电脑接通电源。`r`n•  此操作无法撤销。"
        confirmCheck = '我已了解以上内容，确认要还原'; confirmGo = '开始还原'; back = '返回'
        keyTitle = '需要 BitLocker 恢复密码'
        keyBody = "这台电脑的系统盘已加密，需要先解锁才能还原。`r`n`r`n恢复密码是 48 位数字（8 组，每组 6 位）。它通常保存在：你的微软账户里（在另一台设备上打开 aka.ms/myrecoverykey 登录查看）、打印出来的纸上，或者一个 U 盘里。"
        keyBad = '恢复密码需要 48 位数字，请检查后重新输入。'; keyFail = '这个恢复密码没有解开系统盘，请核对后重新输入。'; keyGo = '解锁并还原'
        progTitle = '正在还原…'; progWarn = '请不要关闭电源，也不要拔掉保存还原点的磁盘。'
        phaseVerify = '正在检查还原点是否完好…'; phaseUnlock = '正在解锁系统盘…'; phasePrepare = '正在准备…'; phaseWrite = '正在写入系统文件…'; phaseBoot = '正在设置启动项…'
        doneTitle = '还原完成'; doneBody = '请点击“重新启动”。电脑启动后如果一切正常，就可以继续使用了。'
        failTitle = '还原没有完成'; failClean = '还原在开始写入之前就停止了，电脑上的内容没有被改动。下面是详细信息。你可以重试，或者重新启动回到 Windows。'; failWritten = '还原在中途停止了，C: 盘现在可能不完整。请先点“重试”，不要直接重启进入 Windows。你的还原点本身没有被改动。下面是详细信息。'; retry = '重试'
    }
    en = @{
        title = 'Restore your PC'; sub = 'Choose the point in time to go back to. Only the Windows partition is restored; files on your other partitions are not changed.'
        colTime = 'Point in time'; colSize = 'Size'; colName = 'Name'
        restore = 'Restore to the selected time'; reboot = 'Restart without restoring'; advanced = 'Advanced (command line)'
        noPoints = 'No restore points were found. Make sure the drive that holds them is connected, then click "Look again".'; rescan = 'Look again'
        confirmTitle = 'Confirm the restore'
        confirmBody = "The Windows drive (C:) will go back to how it was on {0}.`r`n`r`n•  Anything created or changed on C: after that time is lost: desktop, documents, downloads and software installed since.`r`n•  Files on other partitions (for example drive {1}: that holds the restore points) are not changed.`r`n•  This takes a while; keep the PC plugged in.`r`n•  It cannot be undone."
        confirmCheck = 'I understand and want to restore'; confirmGo = 'Start the restore'; back = 'Back'
        keyTitle = 'BitLocker recovery password needed'
        keyBody = "The system drive of this PC is encrypted and must be unlocked before it can be restored.`r`n`r`nThe recovery password has 48 digits (8 groups of 6). You can usually find it in your Microsoft account (sign in at aka.ms/myrecoverykey on another device), on a printout, or on a USB drive."
        keyBad = 'The recovery password has 48 digits. Please check it and try again.'; keyFail = 'This recovery password did not unlock the drive. Please check it and try again.'; keyGo = 'Unlock and restore'
        progTitle = 'Restoring...'; progWarn = 'Do not switch the PC off or unplug the drive that holds the restore points.'
        phaseVerify = 'Checking that the restore point is intact...'; phaseUnlock = 'Unlocking the system drive...'; phasePrepare = 'Preparing...'; phaseWrite = 'Writing the system files...'; phaseBoot = 'Setting up the startup files...'
        doneTitle = 'Restore finished'; doneBody = 'Click "Restart". If the PC starts normally you can keep using it.'
        failTitle = 'The restore did not finish'; failClean = 'The restore stopped before anything was written, so your PC has not been changed. Details are below. You can try again or restart into Windows.'; failWritten = 'The restore stopped part-way and the C: drive may now be incomplete. Please click "Try again" first and do not restart into Windows yet. Your restore points themselves were not changed. Details are below.'; retry = 'Try again'
    }
}
function T($key) { $text[$Language][$key] }
function Format-GuiTime($id) { $t = ConvertTo-GuiTime $id; if ($Language -eq 'zh') { $t.ToString('yyyy年M月d日 HH:mm') } else { $t.ToString('MMMM d, yyyy HH:mm', [Globalization.CultureInfo]::GetCultureInfo('en-US')) } }

# ---------------------------------------------------------------- look
$cInk = [Drawing.Color]::FromArgb(27, 36, 51); $cSoft = [Drawing.Color]::FromArgb(107, 117, 135); $cAccent = [Drawing.Color]::FromArgb(47, 107, 255)
$cPage = [Drawing.Color]::FromArgb(245, 247, 251); $cDanger = [Drawing.Color]::FromArgb(200, 50, 50)
$families = (New-Object Drawing.Text.InstalledFontCollection).Families | ForEach-Object Name
$fontName = if ($Language -eq 'zh' -and $families -contains 'Microsoft YaHei UI') { 'Microsoft YaHei UI' } elseif ($families -contains 'Segoe UI') { 'Segoe UI' } else { 'Arial' }
function New-Font($size, [Drawing.FontStyle]$style = [Drawing.FontStyle]::Regular) { New-Object Drawing.Font($fontName, [single]$size, $style) }

function New-Label($textValue, $size, $color, [switch]$Bold) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $textValue; $l.ForeColor = $color; $l.AutoSize = $false; $l.BackColor = [Drawing.Color]::Transparent
    $l.Font = New-Font $size $(if ($Bold) { [Drawing.FontStyle]::Bold } else { [Drawing.FontStyle]::Regular })
    $l
}
function New-Button($textValue, [switch]$Primary, [switch]$Danger, $width = 280) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $textValue; $b.Width = $width; $b.Height = 58; $b.FlatStyle = 'Flat'; $b.Font = New-Font 15 ([Drawing.FontStyle]::Bold); $b.Cursor = 'Hand'
    if ($Primary) { $b.BackColor = $cAccent; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0 }
    elseif ($Danger) { $b.BackColor = $cDanger; $b.ForeColor = [Drawing.Color]::White; $b.FlatAppearance.BorderSize = 0 }
    else { $b.BackColor = [Drawing.Color]::White; $b.ForeColor = $cInk; $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(208, 214, 226) }
    $b
}

$form = New-Object Windows.Forms.Form
$form.Text = 'RestoreNest'; $form.BackColor = $cPage; $form.ForeColor = $cInk; $form.Font = New-Font 14; $form.KeyPreview = $true
if ($SnapshotDir) { $form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-3000, -3000); $form.ClientSize = New-Object Drawing.Size(1280, 720); $form.FormBorderStyle = 'None' }
else { $form.FormBorderStyle = 'None'; $form.WindowState = 'Maximized'; $form.TopMost = $true }

$stage = New-Object Windows.Forms.Panel
$stage.Dock = 'Fill'; $stage.Padding = New-Object Windows.Forms.Padding(80, 56, 80, 40)
$form.Controls.Add($stage)

function New-Page { $p = New-Object Windows.Forms.Panel; $p.Dock = 'Fill'; $p.Visible = $false; $p.BackColor = $cPage; $stage.Controls.Add($p); $p }
function Add-Row($cPage, $control, $top, $height) { $control.Left = 0; $control.Top = $top; $control.Height = $height; $control.Anchor = 'Top,Left,Right'; $control.Width = $cPage.ClientSize.Width; $cPage.Controls.Add($control); $control }
function Show-Page($p) { foreach ($c in $stage.Controls) { $c.Visible = ($c -eq $p) } }

# ---------------------------------------------------------------- page: list
$pList = New-Page
$lblTitle = Add-Row $pList (New-Label (T 'title') 30 $cInk -Bold) 0 56
$lblSub = Add-Row $pList (New-Label (T 'sub') 14 $cSoft) 60 56
$list = New-Object Windows.Forms.ListView
$list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $false; $list.HideSelection = $false; $list.Font = New-Font 17; $list.BorderStyle = 'FixedSingle'; $list.GridLines = $false
$null = $list.Columns.Add((T 'colTime'), 460); $null = $list.Columns.Add((T 'colSize'), 150); $null = $list.Columns.Add((T 'colName'), 400)
$rowHeight = New-Object Windows.Forms.ImageList; $rowHeight.ImageSize = New-Object Drawing.Size(1, 46); $list.SmallImageList = $rowHeight
$null = Add-Row $pList $list 124 330
$lblNone = Add-Row $pList (New-Label (T 'noPoints') 15 $cDanger) 124 120
$lblNone.Visible = $false
$btnRestore = New-Button (T 'restore') -Primary -width 340; $btnRescan = New-Button (T 'rescan') -width 200; $btnReboot = New-Button (T 'reboot') -width 300; $btnAdvanced = New-Button (T 'advanced') -width 340

# ---------------------------------------------------------------- page: confirm
$pConfirm = New-Page
$lblConfirmTitle = Add-Row $pConfirm (New-Label (T 'confirmTitle') 30 $cInk -Bold) 0 56
$lblConfirmBody = Add-Row $pConfirm (New-Label '' 16 $cInk) 72 230
$chkSure = New-Object Windows.Forms.CheckBox
$chkSure.Text = T 'confirmCheck'; $chkSure.Font = New-Font 16 ([Drawing.FontStyle]::Bold); $chkSure.AutoSize = $true; $chkSure.Left = 0; $chkSure.Top = 330; $pConfirm.Controls.Add($chkSure)
$btnConfirmGo = New-Button (T 'confirmGo') -Danger -width 300; $btnConfirmBack = New-Button (T 'back') -width 200
$btnConfirmGo.BackColor = [Drawing.Color]::FromArgb(205, 210, 220)

# ---------------------------------------------------------------- page: BitLocker key
$pKey = New-Page
$null = Add-Row $pKey (New-Label (T 'keyTitle') 30 $cInk -Bold) 0 56
$null = Add-Row $pKey (New-Label (T 'keyBody') 15 $cInk) 72 190
$txtKey = New-Object Windows.Forms.TextBox
$txtKey.Font = New-Object Drawing.Font('Consolas', 22); $txtKey.MaxLength = 55; $txtKey.Left = 0; $txtKey.Top = 280; $txtKey.Width = 900; $pKey.Controls.Add($txtKey)
$lblKeyError = Add-Row $pKey (New-Label '' 14 $cDanger) 336 36
$btnKeyGo = New-Button (T 'keyGo') -Primary -width 320; $btnKeyBack = New-Button (T 'back') -width 200

# ---------------------------------------------------------------- page: progress
$pProgress = New-Page
$null = Add-Row $pProgress (New-Label (T 'progTitle') 30 $cInk -Bold) 0 56
$lblPhase = Add-Row $pProgress (New-Label '' 18 $cInk -Bold) 110 44
$bar = New-Object Windows.Forms.ProgressBar
$bar.Style = 'Marquee'; $bar.Left = 0; $bar.Top = 170; $bar.Height = 30; $bar.Anchor = 'Top,Left,Right'; $bar.Width = $pProgress.ClientSize.Width; $pProgress.Controls.Add($bar)
$lblPercent = Add-Row $pProgress (New-Label '' 14 $cSoft) 210 36
$null = Add-Row $pProgress (New-Label (T 'progWarn') 15 $cDanger) 280 40

# ---------------------------------------------------------------- page: done / failed
$pDone = New-Page
$lblDoneTitle = Add-Row $pDone (New-Label '' 30 $cInk -Bold) 0 56
$lblDoneBody = Add-Row $pDone (New-Label '' 16 $cInk) 72 64
$txtDetail = New-Object Windows.Forms.TextBox
$txtDetail.Multiline = $true; $txtDetail.ReadOnly = $true; $txtDetail.ScrollBars = 'Vertical'; $txtDetail.Font = New-Object Drawing.Font('Consolas', 11); $txtDetail.Left = 0; $txtDetail.Top = 140; $txtDetail.Height = 300
$txtDetail.Anchor = 'Top,Left,Right'; $txtDetail.Width = $pDone.ClientSize.Width; $pDone.Controls.Add($txtDetail)
$btnDoneReboot = New-Button (T 'reboot') -width 260; $btnRetry = New-Button (T 'retry') -Primary -width 200; $btnDoneAdvanced = New-Button (T 'advanced') -width 340

# A button bar per page: the flow layout places the buttons side by side and skips hidden ones.
function Add-ButtonBar($targetPage, $buttons) {
    $bar = New-Object Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Bottom'; $bar.Height = 76; $bar.FlowDirection = 'LeftToRight'; $bar.WrapContents = $false; $bar.BackColor = [Drawing.Color]::Transparent
    foreach ($b in $buttons) { $b.Margin = New-Object Windows.Forms.Padding(0, 6, 16, 6); $bar.Controls.Add($b) }
    $targetPage.Controls.Add($bar)
}
Add-ButtonBar $pList @($btnRestore, $btnRescan, $btnReboot, $btnAdvanced)
Add-ButtonBar $pConfirm @($btnConfirmGo, $btnConfirmBack)
Add-ButtonBar $pKey @($btnKeyGo, $btnKeyBack)
Add-ButtonBar $pDone @($btnDoneReboot, $btnRetry, $btnDoneAdvanced)

# ---------------------------------------------------------------- behaviour
$script:points = @(); $script:selected = $null; $script:key = ''; $script:exitCode = 0; $script:process = $null; $script:logFile = $null; $script:demoTick = 0

function Update-List {
    $script:points = @(Get-GuiPoints)
    $list.Items.Clear()
    foreach ($p in $script:points) {
        $item = New-Object Windows.Forms.ListViewItem((Format-GuiTime $p.Id))
        $null = $item.SubItems.Add(('{0:N1} GB' -f $p.GiB)); $null = $item.SubItems.Add($p.Name); $item.Tag = $p
        $null = $list.Items.Add($item)
    }
    $has = $script:points.Count -gt 0
    $list.Visible = $has; $lblNone.Visible = -not $has; $btnRestore.Enabled = $has; $btnRescan.Visible = -not $has
    if ($has) { $list.Items[0].Selected = $true }
}
function Invoke-Reboot { if ($Demo -or $SnapshotDir) { $form.Close() } else { Start-Process -FilePath 'wpeutil.exe' -ArgumentList 'reboot' -WindowStyle Hidden; $form.Close() } }

function Show-Confirm {
    $script:selected = $list.SelectedItems[0].Tag
    $letter = $script:selected.Root.Substring(0, 1)
    $lblConfirmBody.Text = ((T 'confirmBody') -f (Format-GuiTime $script:selected.Id), $letter)
    $chkSure.Checked = $false; $btnConfirmGo.BackColor = [Drawing.Color]::FromArgb(205, 210, 220)
    Show-Page $pConfirm
}

function Test-NeedsKey {
    if ($Demo) { return $script:demoNeedsKey }
    $point = @(Get-RnRestorePoints -Root $script:selected.Root | Where-Object Id -eq $script:selected.Id)[0]
    $null -ne (Find-RnLockedTarget -Meta $point.Meta -Partitions (Get-RnPartitionList))
}

function Start-Restore {
    $lblPhase.Text = T 'phaseVerify'; $bar.Style = 'Marquee'; $lblPercent.Text = ''
    Show-Page $pProgress
    $script:startedAt = Get-Date
    if ($Demo) { $script:demoTick = 0; return }
    $script:logFile = Join-Path $env:TEMP 'rn-restore-gui.log'; $errFile = "$script:logFile.err"
    Remove-Item $script:logFile, $errFile -Force -ErrorAction SilentlyContinue
    $arguments = Get-RnRestoreProcessArguments -ScriptPath (Join-Path $PSScriptRoot 'Restore.ps1') -Root $script:selected.Root -Id $script:selected.Id -WimlibPath $WimlibPath -RecoveryPassword $script:key
    $script:process = Start-RnProcess -FilePath 'powershell.exe' -ArgumentList $arguments -StdOut $script:logFile -StdErr $errFile
}

function Read-LogTail($path, $bytes = 6000) {
    try {
        $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try { $len = $fs.Length; $start = [math]::Max(0, $len - $bytes); [void]$fs.Seek($start, 'Begin'); $buf = New-Object byte[] ($len - $start); [void]$fs.Read($buf, 0, $buf.Length); [Text.Encoding]::UTF8.GetString($buf) } finally { $fs.Dispose() }
    } catch { '' }
}

# Progress phases from the wording of Restore.ps1 / wimlib; the percent is the last "(NN%)" wimlib printed for the current step.
function Get-Progress($log) {
    $phase = 'verify'; $percent = $null; $overall = $null
    if ($log -match 'is locked by BitLocker') { $phase = 'unlock' }
    if ($log -match '\nPLAN') { $phase = 'prepare' }
    $last = [regex]::Matches($log, '(Creating files|Extracting file data|Applying metadata[^:]*): [^\r\n]*?\((\d+)%\)')
    if ($last.Count -gt 0) {
        $phase = 'write'; $step = $last[$last.Count - 1].Groups[1].Value; $percent = [int]$last[$last.Count - 1].Groups[2].Value
        $overall = switch -Wildcard ($step) { 'Creating*' { [int]($percent * 0.15) } 'Extracting*' { 15 + [int]($percent * 0.70) } default { 85 + [int]($percent * 0.13) } }
    }
    if ($log -match 'Boot files successfully created') { $phase = 'boot'; $overall = 99 }
    [pscustomobject]@{ Phase = $phase; Overall = $overall }
}

function Show-Result($ok, $detail, $written = $false) {
    if ($ok) { $lblDoneTitle.Text = T 'doneTitle'; $lblDoneTitle.ForeColor = $cInk; $lblDoneBody.Text = T 'doneBody'; $txtDetail.Visible = $false; $btnRetry.Visible = $false; $btnDoneAdvanced.Visible = $false }
    else { $lblDoneTitle.Text = T 'failTitle'; $lblDoneTitle.ForeColor = $cDanger; $lblDoneBody.Text = $(if ($written) { T 'failWritten' } else { T 'failClean' }); $txtDetail.Text = $detail; $txtDetail.Visible = $true; $btnRetry.Visible = $true; $btnDoneAdvanced.Visible = $true }
    Show-Page $pDone
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
    if ($pProgress.Visible -ne $true) { return }
    if ($Demo) {
        $script:demoTick++
        if ($script:demoTick -lt 3) { $lblPhase.Text = T 'phaseVerify'; return }
        $bar.Style = 'Continuous'; $bar.Value = [math]::Min(100, ($script:demoTick - 3) * 4); $lblPhase.Text = T 'phaseWrite'; $lblPercent.Text = "$($bar.Value) %"
        if ($bar.Value -ge 100) { Show-Result $true '' }
        return
    }
    $log = (Read-LogTail $script:logFile)
    $info = Get-Progress $log
    $lblPhase.Text = switch ($info.Phase) { 'unlock' { T 'phaseUnlock' } 'prepare' { T 'phasePrepare' } 'write' { T 'phaseWrite' } 'boot' { T 'phaseBoot' } default { T 'phaseVerify' } }
    if ($null -ne $info.Overall) { $bar.Style = 'Continuous'; $bar.Value = [math]::Min(100, [math]::Max(0, $info.Overall)); $lblPercent.Text = "$($bar.Value) %" }
    if ($script:process.HasExited) {
        $full = Get-Content -LiteralPath $script:logFile -Raw -ErrorAction SilentlyContinue; $err = Get-Content -LiteralPath "$script:logFile.err" -Raw -ErrorAction SilentlyContinue
        if ($script:process.ExitCode -eq 0 -and $full -match 'Restore finished') { Show-Result $true '' }
        elseif ($full -match 'did not unlock the partition') { $lblKeyError.Text = T 'keyFail'; Show-Page $pKey; $txtKey.Focus() }
        else {
            $written = [bool]($full -match '(Creating files|Extracting file data)'); $tail = (($full -split "`r?`n") | Where-Object { $_ -and $_ -notmatch '^(Creating files|Extracting file data|Applying metadata)' } | Select-Object -Last 14) -join "`r`n"; Show-Result $false ($tail + "`r`n" + $err) $written }
    }
})

# ---------------------------------------------------------------- wiring
$list.Add_DoubleClick({ if ($list.SelectedItems.Count -eq 1) { Show-Confirm } })
$list.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Return' -and $list.SelectedItems.Count -eq 1) { $e.Handled = $true; Show-Confirm } })
$form.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape' -and $pConfirm.Visible) { $e.Handled = $true; Show-Page $pList } })
$btnRestore.Add_Click({ if ($list.SelectedItems.Count -eq 1) { Show-Confirm } })
$btnRescan.Add_Click({ Update-List })
$btnReboot.Add_Click({ Invoke-Reboot })
$btnDoneReboot.Add_Click({ Invoke-Reboot })
$btnAdvanced.Add_Click({ $script:exitCode = 2; $form.Close() })
$btnDoneAdvanced.Add_Click({ $script:exitCode = 2; $form.Close() })
$chkSure.Add_CheckedChanged({ $btnConfirmGo.BackColor = $(if ($chkSure.Checked) { $cDanger } else { [Drawing.Color]::FromArgb(205, 210, 220) }) })
$btnConfirmBack.Add_Click({ Show-Page $pList })
$btnConfirmGo.Add_Click({
    if (-not $chkSure.Checked) { return }
    $script:key = ''
    if (Test-NeedsKey) { $txtKey.Text = ''; $lblKeyError.Text = ''; Show-Page $pKey; $txtKey.Focus() } else { Start-Restore }
})
$btnKeyBack.Add_Click({ Show-Page $pConfirm })
$script:formatting = $false
$txtKey.Add_TextChanged({
    if ($script:formatting) { return }
    $script:formatting = $true
    $digits = ($txtKey.Text -replace '\D', ''); if ($digits.Length -gt 48) { $digits = $digits.Substring(0, 48) }
    $txtKey.Text = ($digits -split '(?<=\G\d{6})(?=\d)') -join '-'; $txtKey.SelectionStart = $txtKey.Text.Length
    $script:formatting = $false
})
$btnKeyGo.Add_Click({
    if (-not (Test-RnRecoveryPassword $txtKey.Text)) { $lblKeyError.Text = T 'keyBad'; return }
    $script:key = $txtKey.Text
    Start-Restore
})
$btnRetry.Add_Click({ Update-List; Show-Page $pList })
$form.Add_Shown({ $timer.Start() })
$form.Add_FormClosing({ $timer.Stop() })

[Windows.Forms.Application]::add_ThreadException({ param($s, $e) $script:exitCode = 2; try { $form.Close() } catch { } })

$script:demoNeedsKey = $false
Update-List
Show-Page $pList

if ($SnapshotDir) {
    # Layout check: draw each screen to a PNG and leave.
    New-Item -ItemType Directory -Force -Path $SnapshotDir | Out-Null
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    function Save-Snapshot($name) { [Windows.Forms.Application]::DoEvents(); $bmp = New-Object Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height); $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height))); $bmp.Save((Join-Path $SnapshotDir "$Language-$name.png")); $bmp.Dispose() }
    Save-Snapshot 'list'
    $list.Items[0].Selected = $true; Show-Confirm; Save-Snapshot 'confirm'
    $txtKey.Text = '123456789012345678'; Show-Page $pKey; Save-Snapshot 'key'
    $bar.Style = 'Continuous'; $bar.Value = 42; $lblPhase.Text = T 'phaseWrite'; $lblPercent.Text = '42 %'; Show-Page $pProgress; Save-Snapshot 'progress'
    Show-Result $true ''; Save-Snapshot 'done'
    Show-Result $false "wimlib apply failed (2).`r`nThe target partition is now incomplete; boot RestoreNest Recovery again and retry." $true; Save-Snapshot 'failed'
    Show-Result $false "No valid restore point was found." $false; Save-Snapshot 'failed-clean'
    $list.Items.Clear(); $list.Visible = $false; $lblNone.Visible = $true; Show-Page $pList; Save-Snapshot 'nopoints'
    $form.Close(); exit 0
}

[void]$form.ShowDialog()
exit $script:exitCode
