// --- Módulo: LoadingView.xaml.cs ---
// Ecrã de arranque com sequência de dependências e serviços.
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;



namespace RatAnalyzer.Desktop.Views;



// --- Ecrã de arranque: dependências, backend e frontend ---
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



    // --- Inicia sequência de arranque ao carregar o controlo ---
    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        _ = RunStartupSequenceAsync();
    }



    // --- Corre StartupSequence e notifica conclusão (sucesso ou erro) ---
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



    // --- Adiciona linha ao log visível (thread-safe via Dispatcher) ---
    private void AddLog(string message)
    {
        Application.Current.Dispatcher.Invoke(() =>
            SystemLogs.Add(ProcessOutputEncoding.NormalizeForDisplay(message)));
    }
}

