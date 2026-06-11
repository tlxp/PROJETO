using System.ComponentModel;
using System.Threading.Tasks;
using System.Windows;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

public partial class VmAnalysisWindow : Window
{
    private readonly VmAnalysisViewModel _viewModel;

    public VmAnalysisWindow(string samplePath, bool runFirstTimeSetup)
    {
        InitializeComponent();

        _viewModel = new VmAnalysisViewModel(samplePath, runFirstTimeSetup, new VmAnalysisDialogsHost(this));
        _viewModel.RequestClose += Close;
        DataContext = _viewModel;

        _viewModel.PropertyChanged += OnViewModelPropertyChanged;

        Loaded += OnLoaded;
        Closing += (_, e) =>
        {
            if (!_viewModel.TryCancelClose())
                e.Cancel = true;
        };
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await _viewModel.RunAsync();
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(VmAnalysisViewModel.LogText))
            ScrollLogToEnd();
    }

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
