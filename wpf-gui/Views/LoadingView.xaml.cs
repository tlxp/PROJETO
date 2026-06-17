using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;

namespace RatAnalyzer.Desktop.Views;

public partial class LoadingView : UserControl
{
    public event EventHandler? LoadingCompleted;

    public ObservableCollection<string> SystemLogs { get; } = new();

    public LoadingView()
    {
        InitializeComponent();
        DataContext = this;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _ = RunStartupSequenceAsync();
    }

    private async Task RunStartupSequenceAsync()
    {
        try
        {
            await StartupSequence.RunFullStartupSequenceAsync(AddLog);
        }
        catch (Exception ex)
        {
            AddLog(LocalizationManager.Get(LocKeys.MsgStartupFailed));
            AddLog(ex.Message);
            MessageBox.Show(
                LocalizationManager.Format(LocKeys.MsgStartupFailedDetail, ex.Message),
                LocalizationManager.Get(LocKeys.MsgStartupFailedTitle),
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        LoadingCompleted?.Invoke(this, EventArgs.Empty);
    }

    private void AddLog(string message)
    {
        Application.Current.Dispatcher.Invoke(() =>
            SystemLogs.Add(ProcessOutputEncoding.NormalizeForDisplay(message)));
    }
}

