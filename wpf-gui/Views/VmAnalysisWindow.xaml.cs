// --- Módulo: VmAnalysisWindow.xaml.cs ---
using System;
using System.ComponentModel;
using System.Threading.Tasks;
using System.Windows;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.Services;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

// --- Janela de análise comportamental em VM com log em tempo real ---
public partial class VmAnalysisWindow : Window
{
    private readonly VmAnalysisViewModel _viewModel;

    public VmAnalysisWindow(
        string samplePath,
        bool runFirstTimeSetup,
        int sampleTimeoutSeconds,
        bool waitForSampleExit,
        VmGuestCredentials guestCredentials,
        string? linkedJobId = null,
        Action<string>? openBrowserUrl = null,
        Action<string>? onJobIdKnown = null)
    {
        InitializeComponent();
        WindowLocalization.BindTitle(this, () => UiStrings.Instance.VmWindowTitle);

        _viewModel = new VmAnalysisViewModel(
            samplePath,
            runFirstTimeSetup,
            sampleTimeoutSeconds,
            waitForSampleExit,
            guestCredentials,
            new VmAnalysisDialogsHost(this),
            linkedJobId,
            openBrowserUrl,
            onJobIdKnown: onJobIdKnown);
        _viewModel.RequestClose += Close;
        DataContext = _viewModel;

        _viewModel.PropertyChanged += OnViewModelPropertyChanged;

        Loaded += OnLoaded;
        Closing += (_, e) =>
        {
            // *Impede fecho acidental enquanto análise decorre*
            if (!_viewModel.TryCancelClose())
                e.Cancel = true;
        };
    }

    // --- Arranca pipeline VM ao carregar a janela ---
    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await _viewModel.RunAsync();
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(VmAnalysisViewModel.LogText))
            ScrollLogToEnd();
    }

    // --- Auto-scroll do terminal para a última linha ---
    private void ScrollLogToEnd()
    {
        if (TerminalScrollViewer == null)
            return;

        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(ScrollLogToEnd);
            return;
        }

        TerminalScrollViewer.ScrollToVerticalOffset(TerminalScrollViewer.ScrollableHeight);
    }
}
