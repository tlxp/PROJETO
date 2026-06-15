using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using RatAnalyzer.Desktop.Bootstrap;

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
            AddLog("[ERRO] Falha no arranque do ambiente.");
            AddLog(ex.Message);
            MessageBox.Show(
                ex.Message + "\n\nPode iniciar manualmente o backend (pasta 'backend') e o frontend (pasta 'frontend').",
                "Erro ao iniciar ambiente",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        LoadingCompleted?.Invoke(this, EventArgs.Empty);
    }

    private void AddLog(string message)
    {
        Application.Current.Dispatcher.Invoke(() => SystemLogs.Add(message));
    }
}

