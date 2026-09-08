using System.Diagnostics;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;
using Windows.Storage.Pickers;

namespace DriveBatteryHealthViewer.Modern;

public sealed partial class MainWindow : Window
{
    private const string Version = "1.0.6";
    private readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true };
    private readonly NavigationView Nav = new()
    {
        PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
        OpenPaneLength = 260,
        IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
        IsSettingsVisible = false
    };
    private readonly Frame ContentFrame = new();
    private readonly NavigationViewItem OverviewItem = new() { Content = "概览", Tag = "overview" };
    private CoreEnvelope? _state;
    private string _page = "overview";
    private bool _busy;

    public MainWindow()
    {
        InitializeComponent();
        BuildNavigationShell();
        Title = $"硬盘与电池健康查看器 v{Version}";
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var appWindow = AppWindow.GetFromWindowId(Win32Interop.GetWindowIdFromWindow(hwnd));
        appWindow.Resize(new SizeInt32(1480, 920));
        appWindow.SetIcon(System.IO.Path.Combine(AppContext.BaseDirectory, "..", "app.ico"));
        Nav.SelectedItem = OverviewItem;
        Activated += async (_, _) =>
        {
            if (_state is null) await RefreshAsync();
        };
    }

    private void BuildNavigationShell()
    {
        Nav.PaneHeader = new StackPanel
        {
            Margin = new Thickness(8, 10, 8, 18),
            Children =
            {
                new TextBlock { Text = "硬盘与电池健康查看器", FontSize = 18, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold },
                new TextBlock { Text = $"v{Version}", Margin = new Thickness(0, 4, 0, 0), Opacity = .72 }
            }
        };
        OverviewItem.Icon = new FontIcon { Glyph = "\uE80F" };
        Nav.MenuItems.Add(OverviewItem);
        Nav.MenuItems.Add(NavigationItem("历史记录", "history", "\uE81C"));
        Nav.MenuItems.Add(NavigationItem("设置", "settings", "\uE713"));
        Nav.MenuItems.Add(NavigationItem("关于", "about", "\uE946"));
        Nav.Content = ContentFrame;
        Nav.SelectionChanged += NavigationChanged;
        Content = Nav;
    }

    private static NavigationViewItem NavigationItem(string content, string tag, string glyph) => new()
    {
        Content = content,
        Tag = tag,
        Icon = new FontIcon { Glyph = glyph }
    };

    private string L(string key) => UiText.Get(_state?.Settings.Language, key);

    private async void NavigationChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag) return;
        _page = tag;
        await ShowCurrentPageAsync();
    }

    private async Task ShowCurrentPageAsync()
    {
        switch (_page)
        {
            case "history": await ShowHistoryAsync(); break;
            case "settings": ShowSettings(); break;
            case "about": ShowAbout(); break;
            default: ShowOverview(); break;
        }
    }

    private void LocalizeNavigation()
    {
        if (Nav.MenuItems[0] is NavigationViewItem a) a.Content = L("overview");
        if (Nav.MenuItems[1] is NavigationViewItem b) b.Content = L("history");
        if (Nav.MenuItems[2] is NavigationViewItem c) c.Content = L("settings");
        if (Nav.MenuItems[3] is NavigationViewItem d) d.Content = L("about");
    }

    private async Task<CoreEnvelope> RunCoreAsync(string command, object? input = null)
    {
        string engine = System.IO.Path.GetFullPath(System.IO.Path.Combine(AppContext.BaseDirectory, "..", "DriveBatteryHealthViewer.Legacy.exe"));
        var start = new ProcessStartInfo(engine, command)
        {
            WorkingDirectory = System.IO.Path.GetDirectoryName(engine)!,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = input is not null,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Cannot start the shared engine.");
        if (input is not null)
        {
            await process.StandardInput.WriteAsync(JsonSerializer.Serialize(input, _json));
            process.StandardInput.Close();
        }
        string output = await process.StandardOutput.ReadToEndAsync();
        string error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0 || string.IsNullOrWhiteSpace(output))
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? $"Engine exited with {process.ExitCode}." : error.Trim());
        return JsonSerializer.Deserialize<CoreEnvelope>(output, _json) ?? throw new InvalidOperationException("Invalid engine response.");
    }

    private async Task RefreshAsync()
    {
        if (_busy) return;
        _busy = true;
        ContentFrame.Content = BusyPage(L("scanning"));
        try
        {
            _state = await RunCoreAsync("--core-scan-json");
            LocalizeNavigation();
            await ShowCurrentPageAsync();
        }
        catch (Exception ex)
        {
            ContentFrame.Content = ErrorPage(ex.Message);
        }
        finally { _busy = false; }
    }

    private static FrameworkElement BusyPage(string text) => new Grid
    {
        Children =
        {
            new StackPanel
            {
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Spacing = 14,
                Children = { new ProgressRing { IsActive = true, Width = 40, Height = 40 }, new TextBlock { Text = text, FontSize = 16 } }
            }
        }
    };

    private FrameworkElement ErrorPage(string error)
    {
        var retry = new Button { Content = L("retry"), HorizontalAlignment = HorizontalAlignment.Left };
        retry.Click += async (_, _) => await RefreshAsync();
        return new StackPanel { Margin = new Thickness(36), Spacing = 14, Children = { Heading(L("error")), new TextBlock { Text = error, TextWrapping = TextWrapping.Wrap }, retry } };
    }

    private void ShowOverview()
    {
        if (_state is null) return;
        var root = new Grid { Padding = new Thickness(32, 24, 28, 24) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition());
        var header = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = new StackPanel { Spacing = 4 };
        title.Children.Add(Heading(L("overview")));
        title.Children.Add(new TextBlock { Text = string.Format(L("scanComplete"), _state.Disks.Count, _state.Batteries.Count), FontSize = 15 });
        header.Children.Add(title);
        var commands = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        commands.Children.Add(CommandButton("\uE72C", L("refresh"), async () => await RefreshAsync()));
        commands.Children.Add(CommandButton("\uE74E", L("save"), SaveReportAsync));
        commands.Children.Add(CommandButton("\uE8C8", L("copy"), () => { CopyReport(); return Task.CompletedTask; }));
        commands.Children.Add(CommandButton(_state.Settings.HideSerial ? "\uED1A" : "\uE890", L("hideSerial"), ToggleSerialAsync, _state.Settings.HideSerial));
        Grid.SetColumn(commands, 1);
        header.Children.Add(commands);
        root.Children.Add(header);

        var stack = new StackPanel { Spacing = 20 };
        stack.Children.Add(ComputerHeader());
        if (_state.Disks.Count > 0)
        {
            stack.Children.Add(SectionTitle("\uE7F1", L("drives"), _state.Disks.Count));
            foreach (var disk in _state.Disks) stack.Children.Add(DiskCard(disk));
        }
        if (_state.Batteries.Count > 0)
        {
            stack.Children.Add(SectionTitle("\uE83F", L("battery"), _state.Batteries.Count));
            foreach (var battery in _state.Batteries) stack.Children.Add(BatteryCard(battery));
        }
        var scroll = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
        ContentFrame.Content = root;
    }

    private FrameworkElement ComputerHeader()
    {
        var icon = new Border
        {
            Width = 54, Height = 54, CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 231, 250, 237)),
            Child = new FontIcon { Glyph = "\uE73E", FontSize = 24, Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 16, 160, 72)) }
        };
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 2 };
        text.Children.Add(new TextBlock { Text = _state!.Computer, FontSize = 25, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        text.Children.Add(new TextBlock { Text = string.Format(L("updated"), _state.GeneratedAt.LocalDateTime), Opacity = .65, FontSize = 14 });
        return new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Margin = new Thickness(10, 0, 0, 4), Children = { icon, text } };
    }

    private FrameworkElement DiskCard(CoreDisk d)
    {
        var fields = new (string, string)[]
        {
            (L("capacity"),d.Capacity),(L("interface"),d.Interface),(L("serial"),d.Serial),(L("temperature"),d.Temperature),
            (L("firmware"),d.Firmware),(L("powerCycles"),d.PowerCycles),(L("powerOnTime"),d.PowerOnTime),(L("totalWritten"),d.TotalWritten),
            (L("totalRead"),d.TotalRead),(L("status"),d.Status),(L("unsafeShutdowns"),d.UnsafeShutdowns),(L("errorLogEntries"),d.ErrorLogEntries)
        };
        return HealthCard(d.Model, d.Device, d.HealthPercent, d.Status, d.StatusGood, fields);
    }

    private FrameworkElement BatteryCard(CoreBattery b)
    {
        var fields = new (string, string)[]
        {
            (L("manufacturer"),b.Manufacturer),(L("chemistry"),b.Chemistry),(L("serial"),b.Serial),(L("cycleCount"),b.CycleCount),
            (L("designCapacity"),b.DesignCapacity),(L("fullCapacity"),b.FullCapacity),(L("batteryHealth"),b.HealthPercent is null ? L("unknown") : $"{b.HealthPercent:0.0}%"),(L("status"),b.Status)
        };
        return HealthCard(b.Name, "", b.HealthPercent, b.Status, b.StatusGood, fields);
    }

    private FrameworkElement HealthCard(string name, string subtitle, double? percent, string status, bool good, IEnumerable<(string Label, string Value)> fields)
    {
        var grid = new Grid { ColumnSpacing = 26 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.Children.Add(HealthRing(percent));
        var body = new StackPanel { Spacing = 12 };
        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition()); top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var names = new StackPanel { Spacing = 4 };
        names.Children.Add(new TextBlock { Text = string.IsNullOrWhiteSpace(name) ? L("unknown") : name, FontSize = 19, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        if (!string.IsNullOrWhiteSpace(subtitle)) names.Children.Add(new TextBlock { Text = subtitle, Opacity = .60 });
        top.Children.Add(names);
        var badge = new Border { Padding = new Thickness(18, 7, 18, 7), CornerRadius = new CornerRadius(8), Background = new SolidColorBrush(good ? Windows.UI.Color.FromArgb(255, 232, 250, 237) : Windows.UI.Color.FromArgb(255, 239, 241, 244)), Child = new TextBlock { Text = status, Foreground = new SolidColorBrush(good ? Windows.UI.Color.FromArgb(255, 16, 124, 16) : Windows.UI.Color.FromArgb(255, 86, 94, 106)) } };
        Grid.SetColumn(badge, 1); top.Children.Add(badge); body.Children.Add(top);
        body.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 230, 233, 237)) });
        var fieldGrid = new Grid { RowSpacing = 10, ColumnSpacing = 52 };
        fieldGrid.ColumnDefinitions.Add(new ColumnDefinition()); fieldGrid.ColumnDefinitions.Add(new ColumnDefinition());
        int index = 0;
        foreach (var f in fields)
        {
            int row = index / 2, col = index % 2;
            while (fieldGrid.RowDefinitions.Count <= row) fieldGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var item = new StackPanel { Spacing = 1 };
            item.Children.Add(new TextBlock { Text = f.Label, Opacity = .58, FontSize = 13 });
            item.Children.Add(new TextBlock { Text = string.IsNullOrWhiteSpace(f.Value) ? L("unknown") : f.Value, FontSize = 15, TextWrapping = TextWrapping.Wrap });
            Grid.SetRow(item, row); Grid.SetColumn(item, col); fieldGrid.Children.Add(item); index++;
        }
        body.Children.Add(fieldGrid); Grid.SetColumn(body, 1); grid.Children.Add(body);
        return new Border { Background = new SolidColorBrush(Colors.White), BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 224, 228, 234)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(10), Padding = new Thickness(20), Child = grid };
    }

    private FrameworkElement HealthRing(double? percent)
    {
        double value = Math.Clamp(percent ?? 0, 0, 100);
        var grid = new Grid { Width = 140, Height = 160, HorizontalAlignment = HorizontalAlignment.Center };
        var ring = new Grid { Width = 122, Height = 122, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 3, 0, 0) };
        var track = new Ellipse
        {
            Width = 110, Height = 110, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Stroke = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 226, 229, 234)), StrokeThickness = 8
        };
        ring.Children.Add(track);
        var green = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 34, 197, 94));
        if (value >= 99.95)
        {
            ring.Children.Add(new Ellipse
            {
                Width = 110, Height = 110, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                Stroke = green, StrokeThickness = 8
            });
        }
        else if (value > 0)
        {
            const double center = 61;
            const double radius = 55;
            double endAngle = (value / 100d * Math.PI * 2d) - (Math.PI / 2d);
            var figure = new PathFigure
            {
                StartPoint = new Windows.Foundation.Point(center, center - radius),
                IsClosed = false,
                Segments =
                {
                    new ArcSegment
                    {
                        Point = new Windows.Foundation.Point(center + radius * Math.Cos(endAngle), center + radius * Math.Sin(endAngle)),
                        Size = new Windows.Foundation.Size(radius, radius),
                        SweepDirection = SweepDirection.Clockwise,
                        IsLargeArc = value > 50
                    }
                }
            };
            ring.Children.Add(new Microsoft.UI.Xaml.Shapes.Path
            {
                Data = new PathGeometry { Figures = { figure } }, Stroke = green, StrokeThickness = 8,
                StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round
            });
        }
        ring.Children.Add(new TextBlock { Text = percent is null ? "—" : $"{value:0}%", FontSize = 29, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        grid.Children.Add(ring);
        grid.Children.Add(new TextBlock { Text = L("health"), Opacity = .65, FontSize = 14, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 4) });
        return grid;
    }

    private FrameworkElement SectionTitle(string glyph, string text, int count)
    {
        var badge = new Border { Background = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 235, 238, 243)), CornerRadius = new CornerRadius(7), Padding = new Thickness(10, 4, 10, 4), Child = new TextBlock { Text = count.ToString() } };
        return new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Children = { new FontIcon { Glyph = glyph, FontSize = 20 }, new TextBlock { Text = text, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, FontSize = 18, VerticalAlignment = VerticalAlignment.Center }, badge } };
    }

    private Button CommandButton(string glyph, string tooltip, Func<Task> action, bool selected = false)
    {
        var button = new Button { Width = 50, Height = 50, Padding = new Thickness(0), Content = new FontIcon { Glyph = glyph, FontSize = 20 }, Background = selected ? new SolidColorBrush(Windows.UI.Color.FromArgb(255, 221, 235, 255)) : null };
        ToolTipService.SetToolTip(button, tooltip);
        button.Click += async (_, _) => await action();
        return button;
    }

    private async Task SaveReportAsync()
    {
        if (_state is null) return;
        var picker = new FileSavePicker { SuggestedFileName = $"DBHV_{_state.Computer}_{DateTime.Now:yyyyMMdd_HHmmss}" };
        picker.FileTypeChoices.Add(L("textReport"), new List<string> { ".txt" });
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var file = await picker.PickSaveFileAsync();
        if (file is not null) await Windows.Storage.FileIO.WriteTextAsync(file, _state.Report);
    }

    private void CopyReport()
    {
        if (_state is null) return;
        var package = new DataPackage(); package.SetText(_state.Report); Clipboard.SetContent(package); Clipboard.Flush();
    }

    private async Task ToggleSerialAsync()
    {
        if (_state is null) return;
        _state = await RunCoreAsync("--core-update-settings-json", new { hideSerial = !_state.Settings.HideSerial });
        await RefreshAsync();
    }

    private async Task ShowHistoryAsync()
    {
        if (_state is null) return;
        _state = await RunCoreAsync("--core-state-json");
        var root = new Grid { Padding = new Thickness(32, 24, 28, 24) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); root.RowDefinitions.Add(new RowDefinition());
        var list = new ListView { SelectionMode = ListViewSelectionMode.Single };
        var preview = new TextBox { IsReadOnly = true, AcceptsReturn = true, TextWrapping = TextWrapping.NoWrap, FontFamily = new FontFamily("Consolas"), FontSize = Math.Max(13, _state.Settings.FontSize + 3), BorderThickness = new Thickness(0), VerticalAlignment = VerticalAlignment.Stretch, HorizontalAlignment = HorizontalAlignment.Stretch };
        var header = new Grid { Margin = new Thickness(0, 0, 0, 18) };
        header.ColumnDefinitions.Add(new ColumnDefinition()); header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var leftHeader = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Children = { Heading(L("history")) } };
        var select = new Button { Content = L("select") };
        var selectionCommands = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Visibility = Visibility.Collapsed };
        var selectAll = new CheckBox { Content = L("selectAll"), VerticalAlignment = VerticalAlignment.Center };
        var export = new Button { Content = L("exportSelected"), IsEnabled = false };
        var delete = new Button { Content = L("deleteSelected"), IsEnabled = false };
        selectionCommands.Children.Add(selectAll); selectionCommands.Children.Add(export); selectionCommands.Children.Add(delete);
        leftHeader.Children.Add(select); leftHeader.Children.Add(selectionCommands); header.Children.Add(leftHeader);
        var location = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, VerticalAlignment = VerticalAlignment.Center };
        var path = new HyperlinkButton { Content = _state.HistoryDir, Padding = new Thickness(4) };
        path.Click += (_, _) => OpenPath(_state.HistoryDir);
        var change = new Button { Content = L("changeHistoryLocation"), MinWidth = 190 };
        change.Click += async (_, _) => await ChangeHistoryLocationAsync();
        location.Children.Add(path); location.Children.Add(change); Grid.SetColumn(location, 1); header.Children.Add(location); root.Children.Add(header);

        var body = new Grid { ColumnSpacing = 0 };
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32, GridUnitType.Star), MinWidth = 280 });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(68, GridUnitType.Star), MinWidth = 420 });
        foreach (var item in _state.History)
        {
            var panel = new StackPanel { Spacing = 4, Padding = new Thickness(8) };
            panel.Children.Add(new TextBlock { Text = item.GeneratedAt.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"), FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, FontSize = 15 });
            panel.Children.Add(new TextBlock { Text = $"{item.Computer} · {L(item.Source == "refresh" ? "autoSaved" : "exported")}", Opacity = .62, FontSize = 12 });
            list.Items.Add(new ListViewItem { Content = panel, Tag = item });
        }
        list.SelectionChanged += (_, _) =>
        {
            if (list.SelectionMode == ListViewSelectionMode.Single && list.SelectedItem is ListViewItem li && li.Tag is CoreHistoryItem item)
                preview.Text = item.Report;
            int count = list.SelectedItems.Count;
            export.IsEnabled = count > 0;
            delete.IsEnabled = count > 0;
            selectAll.IsChecked = list.Items.Count > 0 && count == list.Items.Count;
        };
        select.Click += (_, _) =>
        {
            bool selecting = list.SelectionMode == ListViewSelectionMode.Single;
            list.SelectedItems.Clear();
            list.SelectionMode = selecting ? ListViewSelectionMode.Multiple : ListViewSelectionMode.Single;
            selectionCommands.Visibility = selecting ? Visibility.Visible : Visibility.Collapsed;
            select.Content = L(selecting ? "done" : "select");
            if (!selecting && list.Items.Count > 0) list.SelectedIndex = 0;
        };
        selectAll.Click += (_, _) =>
        {
            list.SelectedItems.Clear();
            if (selectAll.IsChecked == true)
                foreach (var item in list.Items) list.SelectedItems.Add(item);
        };
        export.Click += async (_, _) => await ExportHistoryAsync(list.SelectedItems.OfType<ListViewItem>().Select(x => x.Tag).OfType<CoreHistoryItem>());
        delete.Click += async (_, _) => await DeleteHistoryAsync(list.SelectedItems.OfType<ListViewItem>().Select(x => x.Tag).OfType<CoreHistoryItem>());
        var left = new Grid(); left.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); left.RowDefinitions.Add(new RowDefinition());
        var listTitle = new TextBlock { Text = L("records"), FontSize = 16, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Padding = new Thickness(12, 10, 12, 10) }; left.Children.Add(listTitle); Grid.SetRow(list, 1); left.Children.Add(list);
        body.Children.Add(left);
        var right = new Grid { BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 222, 226, 232)), BorderThickness = new Thickness(1, 0, 0, 0) };
        right.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); right.RowDefinitions.Add(new RowDefinition());
        right.Children.Add(new TextBlock { Text = L("reportPreview"), FontSize = 16, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Padding = new Thickness(12, 10, 12, 10) }); Grid.SetRow(preview, 1); right.Children.Add(preview); Grid.SetColumn(right, 1); body.Children.Add(right);
        if (list.Items.Count > 0) list.SelectedIndex = 0;
        Grid.SetRow(body, 1); root.Children.Add(body); ContentFrame.Content = root;
    }

    private async Task ExportHistoryAsync(IEnumerable<CoreHistoryItem> selected)
    {
        var items = selected.ToList();
        if (items.Count == 0) return;
        var picker = new FolderPicker(); picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync();
        if (folder is null) return;
        foreach (var item in items)
        {
            string computer = string.Concat(item.Computer.Select(c => System.IO.Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
            var file = await folder.CreateFileAsync($"DBHV_{computer}_{item.GeneratedAt.LocalDateTime:yyyyMMdd_HHmmss}.txt", Windows.Storage.CreationCollisionOption.GenerateUniqueName);
            await Windows.Storage.FileIO.WriteTextAsync(file, item.Report);
        }
    }

    private async Task DeleteHistoryAsync(IEnumerable<CoreHistoryItem> selected)
    {
        var items = selected.ToList();
        if (items.Count == 0) return;
        var deleteExternal = new CheckBox { Content = L("deleteAssociated"), IsChecked = true };
        var dialog = new ContentDialog
        {
            Title = string.Format(L("confirmDelete"), items.Count), Content = deleteExternal,
            PrimaryButtonText = L("delete"), CloseButtonText = L("cancel"),
            DefaultButton = ContentDialogButton.Close, XamlRoot = Nav.XamlRoot
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _state = await RunCoreAsync("--core-delete-history-json", new { ids = items.Select(x => x.ID).ToArray(), deleteExternal = deleteExternal.IsChecked == true });
        await ShowHistoryAsync();
    }

    private async Task ChangeHistoryLocationAsync()
    {
        var picker = new FolderPicker(); picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
        var folder = await picker.PickSingleFolderAsync();
        if (folder is null) return;
        _state = await RunCoreAsync("--core-update-settings-json", new { historyDir = folder.Path });
        await ShowHistoryAsync();
    }

    private void ShowSettings()
    {
        if (_state is null) return;
        var stack = new StackPanel { Spacing = 18, MaxWidth = 960, HorizontalAlignment = HorizontalAlignment.Center };
        stack.Children.Add(Heading(L("settings")));
        stack.Children.Add(new TextBlock { Text = L("appearancePrivacy"), FontSize = 18, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        var appearance = SettingsCard();
        var language = new ComboBox { MinWidth = 230, HorizontalAlignment = HorizontalAlignment.Right };
        var languages = new[] { ("system", L("followSystem")), ("zh-CN", "简体中文"), ("en-US", "English"), ("ru-RU", "Русский"), ("fr-FR", "Français"), ("de-DE", "Deutsch"), ("ko-KR", "한국어"), ("ja-JP", "日本語") };
        foreach (var item in languages) language.Items.Add(new ComboBoxItem { Content = item.Item2, Tag = item.Item1 });
        language.SelectedIndex = Array.FindIndex(languages, x => x.Item1 == _state.Settings.Language); if (language.SelectedIndex < 0) language.SelectedIndex = 0;
        language.SelectionChanged += async (_, _) =>
        {
            if (language.SelectedItem is ComboBoxItem item && item.Tag is string code)
            {
                _state = await RunCoreAsync("--core-update-settings-json", new { language = code });
                LocalizeNavigation(); ShowSettings();
            }
        };
        appearance.Children.Add(SettingRow(L("language"), language));
        var hide = new CheckBox { Content = L("hideSerial"), IsChecked = _state.Settings.HideSerial };
        hide.Click += async (_, _) => { _state = await RunCoreAsync("--core-update-settings-json", new { hideSerial = hide.IsChecked == true }); };
        appearance.Children.Add(SettingRow("", hide));
        appearance.Children.Add(new TextBlock { Text = L("hideSerialHelp"), Opacity = .62, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, -8, 0, 4) });
        var font = new NumberBox { Minimum = 8, Maximum = 24, Value = _state.Settings.FontSize, SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact, Width = 150 };
        font.ValueChanged += async (_, e) => { if (!double.IsNaN(e.NewValue)) _state = await RunCoreAsync("--core-update-settings-json", new { fontSize = (int)e.NewValue }); };
        appearance.Children.Add(SettingRow(L("reportFontSize"), font)); stack.Children.Add(appearance);

        stack.Children.Add(new TextBlock { Text = L("historyStorage"), FontSize = 18, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        var history = SettingsCard();
        var mode = new ComboBox { MinWidth = 230, HorizontalAlignment = HorizontalAlignment.Right, Items = { L("afterRefresh"), L("onExport") }, SelectedIndex = _state.Settings.HistoryMode == "export" ? 1 : 0 };
        mode.SelectionChanged += async (_, _) => _state = await RunCoreAsync("--core-update-settings-json", new { historyMode = mode.SelectedIndex == 1 ? "export" : "refresh" });
        history.Children.Add(SettingRow(L("saveReports"), mode));
        var change = new Button { Content = L("changeHistoryLocation"), MinWidth = 230 }; change.Click += async (_, _) => await ChangeHistoryLocationAsync();
        var pathPanel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, HorizontalAlignment = HorizontalAlignment.Right, Children = { new HyperlinkButton { Content = _state.HistoryDir }, change } };
        if (pathPanel.Children[0] is HyperlinkButton link) link.Click += (_, _) => OpenPath(_state.HistoryDir);
        history.Children.Add(SettingRow(L("historyLocation"), pathPanel)); stack.Children.Add(history);
        stack.Children.Add(new TextBlock { Text = L("notes"), FontSize = 18, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        var note = new Border { Background = new SolidColorBrush(Colors.White), BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 224, 228, 234)), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(8), Padding = new Thickness(18), Child = new TextBlock { Text = L("readOnlyNote"), TextWrapping = TextWrapping.Wrap, LineHeight = 24 } }; stack.Children.Add(note);
        ContentFrame.Content = new ScrollViewer { Content = stack, Padding = new Thickness(32, 24, 28, 24) };
    }

    private StackPanel SettingsCard() => new() { Spacing = 14, Background = new SolidColorBrush(Colors.White), Padding = new Thickness(18) };
    private FrameworkElement SettingRow(string label, FrameworkElement control)
    {
        var grid = new Grid { MinHeight = 42 }; grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (!string.IsNullOrWhiteSpace(label)) grid.Children.Add(new TextBlock { Text = label, FontSize = 15, VerticalAlignment = VerticalAlignment.Center }); Grid.SetColumn(control, 1); grid.Children.Add(control); return grid;
    }

    private void ShowAbout()
    {
        var stack = new StackPanel { Spacing = 16, MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Center };
        stack.Children.Add(Heading(L("about")));
        stack.Children.Add(new FontIcon { Glyph = "\uE9D9", FontSize = 76, Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 120, 212)), HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 20, 0, 4) });
        stack.Children.Add(new TextBlock { Text = L("appName"), FontSize = 28, FontWeight = Microsoft.UI.Text.FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(new TextBlock { Text = string.Format(L("version"), Version), Opacity = .62, HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(new TextBlock { Text = L("summary"), TextWrapping = TextWrapping.Wrap, TextAlignment = TextAlignment.Center, Opacity = .68, FontSize = 16, Margin = new Thickness(40, 6, 40, 12) });
        var card = SettingsCard();
        card.Children.Add(AboutRow("\uE77B", L("developer"), "程心 ChengXin", null));
        card.Children.Add(AboutRow("\uE943", L("projectHome"), "GitHub", "https://github.com/xincheng1237/drive-battery-health-viewer"));
        card.Children.Add(AboutRow("\uE90F", L("feedback"), "GitHub Issues", "https://github.com/xincheng1237/drive-battery-health-viewer/issues"));
        card.Children.Add(AboutRow("\uE895", L("changelog"), L("view"), "changelog"));
        card.Children.Add(AboutRow("\uE777", L("license"), "GNU GPL v3", "https://www.gnu.org/licenses/gpl-3.0.html"));
        card.Children.Add(AboutRow("\uE789", L("checkUpdates"), L("checkNow"), "update"));
        stack.Children.Add(card);
        stack.Children.Add(new TextBlock { Text = "© 2026 程心 ChengXin", Opacity = .45, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 16) });
        ContentFrame.Content = new ScrollViewer { Content = stack, Padding = new Thickness(32, 24, 28, 24) };
    }

    private FrameworkElement AboutRow(string glyph, string label, string value, string? action)
    {
        var button = new Button { HorizontalContentAlignment = HorizontalAlignment.Stretch, Background = new SolidColorBrush(Colors.Transparent), BorderThickness = new Thickness(0), Padding = new Thickness(10, 9, 10, 9) };
        var grid = new Grid(); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(36) }); grid.ColumnDefinitions.Add(new ColumnDefinition()); grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new FontIcon { Glyph = glyph, Foreground = new SolidColorBrush(Windows.UI.Color.FromArgb(255, 0, 120, 212)), VerticalAlignment = VerticalAlignment.Center });
        var text = new TextBlock { Text = label, FontSize = 15, VerticalAlignment = VerticalAlignment.Center }; Grid.SetColumn(text, 1); grid.Children.Add(text);
        var detail = new TextBlock { Text = value, Opacity = .62, VerticalAlignment = VerticalAlignment.Center }; Grid.SetColumn(detail, 2); grid.Children.Add(detail); button.Content = grid;
        button.Click += async (_, _) =>
        {
            if (action == "changelog") await ShowChangelogAsync(); else if (action == "update") await CheckUpdatesAsync(button); else if (action is not null) OpenPath(action);
        };
        return button;
    }

    private async Task ShowChangelogAsync()
    {
        var dialog = new ContentDialog { Title = L("changelog"), CloseButtonText = L("done"), XamlRoot = Nav.XamlRoot, DefaultButton = ContentDialogButton.Close, Content = new ScrollViewer { MaxHeight = 560, Content = new TextBlock { Text = L("changelogBody"), TextWrapping = TextWrapping.Wrap, LineHeight = 24 } } };
        await dialog.ShowAsync();
    }

    private async Task CheckUpdatesAsync(Button sender)
    {
        sender.IsEnabled = false;
        try
        {
            using var http = new HttpClient(); http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("DriveBatteryHealthViewer", Version));
            string json = await http.GetStringAsync("https://api.github.com/repos/xincheng1237/drive-battery-health-viewer/releases/latest");
            using var doc = JsonDocument.Parse(json); string latest = doc.RootElement.GetProperty("tag_name").GetString()?.TrimStart('v') ?? Version;
            var dialog = new ContentDialog { Title = L("checkUpdates"), Content = latest == Version ? L("upToDate") : string.Format(L("newVersion"), latest), CloseButtonText = L("done"), XamlRoot = Nav.XamlRoot };
            if (latest != Version) { dialog.PrimaryButtonText = L("download"); dialog.PrimaryButtonClick += (_, _) => OpenPath("https://github.com/xincheng1237/drive-battery-health-viewer/releases/latest"); }
            await dialog.ShowAsync();
        }
        catch (Exception ex) { await new ContentDialog { Title = L("checkUpdates"), Content = ex.Message, CloseButtonText = L("done"), XamlRoot = Nav.XamlRoot }.ShowAsync(); }
        finally { sender.IsEnabled = true; }
    }

    private static void OpenPath(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
    }

    private static TextBlock Heading(string text) => new() { Text = text, FontSize = 29, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold };
}

internal static class UiText
{
    private static readonly Dictionary<string, string> Zh = new()
    {
        ["overview"]="概览",["history"]="历史记录",["settings"]="设置",["about"]="关于",["scanning"]="正在读取硬盘与电池信息…",["retry"]="重试",["error"]="出现问题",
        ["scanComplete"]="读取完成：{0} 块物理硬盘，{1} 块电池。",["refresh"]="刷新",["save"]="保存报告",["copy"]="复制全部",["hideSerial"]="隐藏序列号",["updated"]="更新于 {0:yyyy-MM-dd HH:mm:ss}",
        ["drives"]="硬盘",["battery"]="电池",["capacity"]="容量",["interface"]="接口",["serial"]="序列号",["temperature"]="温度",["firmware"]="固件",["powerCycles"]="通电次数",["powerOnTime"]="通电时间",["totalWritten"]="主机总写入",["totalRead"]="主机总读取",["status"]="健康状态",["unsafeShutdowns"]="非正常关机",["errorLogEntries"]="错误日志条目",["manufacturer"]="制造商",["chemistry"]="化学体系",["cycleCount"]="循环次数",["designCapacity"]="设计容量",["fullCapacity"]="当前满充容量",["batteryHealth"]="电池健康度",["health"]="健康度",["unknown"]="未报告",
        ["textReport"]="文本报告",["select"]="选择…",["selectAll"]="全选",["exportSelected"]="导出",["deleteSelected"]="删除",["deleteAssociated"]="同时删除关联的本地导出报告",["confirmDelete"]="确定删除选中的 {0} 条历史记录吗？",["delete"]="删除",["cancel"]="取消",["changeHistoryLocation"]="更改历史保存位置",["records"]="检测记录",["reportPreview"]="报告预览",["autoSaved"]="刷新时自动保存",["exported"]="导出的报告",
        ["appearancePrivacy"]="外观与隐私",["language"]="语言",["followSystem"]="跟随系统",["hideSerialHelp"]="启用后，界面、复制内容、历史记录和导出报告中的硬盘与电池序列号都会被隐藏。",["reportFontSize"]="报告文字大小",["historyStorage"]="历史记录存储",["saveReports"]="保存报告",["afterRefresh"]="每次刷新后",["onExport"]="仅导出时",["historyLocation"]="历史记录位置",["notes"]="说明",["readOnlyNote"]="本应用只读取硬件信息，不会测速、写入、修复、擦除或更新固件。部分外接硬盘及厂商专用数据可能受到 Windows、控制器或 USB 硬盘盒限制。",
        ["appName"]="硬盘与电池健康查看器",["version"]="版本 {0}",["summary"]="一款查看硬盘状态与电池健康情况的轻量级工具，支持保存检测报告并了解健康状态随时间的变化。",["developer"]="开发者",["projectHome"]="项目主页",["feedback"]="问题反馈",["changelog"]="更新日志",["license"]="许可证",["checkUpdates"]="检查更新",["view"]="查看",["checkNow"]="立即检查",["done"]="完成",["upToDate"]="当前已安装最新版本。",["newVersion"]="发现新版本 {0}。",["download"]="下载",["changelogBody"]="版本 1.0.6\n\n• 现代界面与兼容界面共用同一检测核心、设置和历史记录。\n• 完善硬盘与外接存储设备信息读取。\n• 优化响应式布局、隐私开关、历史记录与更新检查。"
    };
    private static readonly Dictionary<string, string> En = new(Zh)
    {
        ["overview"]="Overview",["history"]="History",["settings"]="Settings",["about"]="About",["scanning"]="Reading drive and battery information…",["retry"]="Retry",["error"]="Something went wrong",["scanComplete"]="Complete: {0} physical drive(s), {1} battery/batteries.",["refresh"]="Refresh",["save"]="Save report",["copy"]="Copy all",["hideSerial"]="Hide serial numbers",["updated"]="Updated {0:yyyy-MM-dd HH:mm:ss}",["drives"]="Drives",["battery"]="Battery",["capacity"]="Capacity",["interface"]="Interface",["serial"]="Serial number",["temperature"]="Temperature",["firmware"]="Firmware",["powerCycles"]="Power cycles",["powerOnTime"]="Power-on time",["totalWritten"]="Total host writes",["totalRead"]="Total host reads",["status"]="Health status",["unsafeShutdowns"]="Unsafe shutdowns",["errorLogEntries"]="Error log entries",["manufacturer"]="Manufacturer",["chemistry"]="Chemistry",["cycleCount"]="Cycle count",["designCapacity"]="Design capacity",["fullCapacity"]="Full-charge capacity",["batteryHealth"]="Battery health",["health"]="Health",["unknown"]="Not reported",["textReport"]="Text report",["select"]="Select…",["selectAll"]="Select all",["exportSelected"]="Export",["deleteSelected"]="Delete",["deleteAssociated"]="Also delete associated local export files",["confirmDelete"]="Delete the selected {0} history record(s)?",["delete"]="Delete",["cancel"]="Cancel",["changeHistoryLocation"]="Change history location",["records"]="Scan history",["reportPreview"]="Report preview",["autoSaved"]="Auto-saved after refresh",["exported"]="Exported report",["appearancePrivacy"]="Appearance & privacy",["language"]="Language",["followSystem"]="Follow system",["hideSerialHelp"]="Hides drive and battery serial numbers in the interface, clipboard, history, and exported reports.",["reportFontSize"]="Report text size",["historyStorage"]="History storage",["saveReports"]="Save reports",["afterRefresh"]="After each refresh",["onExport"]="Only when exported",["historyLocation"]="History location",["notes"]="Notes",["readOnlyNote"]="This application only reads hardware information. It does not benchmark, write, repair, erase, or update firmware. Some external-drive and vendor-specific data may be limited by Windows, the controller, or a USB enclosure.",["appName"]="Drive & Battery Health Viewer",["version"]="Version {0}",["summary"]="A lightweight utility for viewing drive status and battery health, saving scan reports, and following changes over time.",["developer"]="Developer",["projectHome"]="Project home",["feedback"]="Feedback",["changelog"]="Changelog",["license"]="License",["checkUpdates"]="Check for updates",["view"]="View",["checkNow"]="Check now",["done"]="Done",["upToDate"]="The latest version is installed.",["newVersion"]="Version {0} is available.",["download"]="Download",["changelogBody"]="Version 1.0.6\n\n• The modern and compatibility interfaces share one hardware engine, settings store, and history.\n• Improved drive and external-storage information reading.\n• Improved responsive layout, privacy controls, history, and update checks."
    };

    public static string Get(string? setting, string key)
    {
        string code = setting ?? "system";
        if (code == "system") code = CultureInfo.CurrentUICulture.Name;
        // Core data remains fully localized in all seven languages. The modern
        // shell falls back to English for any UI-only label not yet translated.
        var dict = code.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? Zh : En;
        return dict.TryGetValue(key, out var value) ? value : key;
    }
}
