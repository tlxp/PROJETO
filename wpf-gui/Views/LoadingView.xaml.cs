using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

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
        AddLog("[INFO] A iniciar backend em http://localhost:8000 ...");
        await Task.Delay(1000);

        AddLog("[INFO] A verificar estado da VM de sandbox (Hyper-V / Proxmox)...");
        await Task.Delay(1000);

        AddLog("[INFO] A criar/restaurar snapshot limpo da VM...");
        await Task.Delay(1200);

        AddLog("[INFO] A arrancar VM e a aguardar vm-agent...");
        await Task.Delay(1200);

        AddLog("[OK] Ambiente de sandbox pronto. Pode enviar ficheiros para análise.");
        await Task.Delay(600);

        LoadingCompleted?.Invoke(this, EventArgs.Empty);
    }

    private void AddLog(string message)
    {
        Application.Current.Dispatcher.Invoke(() => SystemLogs.Add(message));
    }
}

