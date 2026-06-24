// --- Módulo: StorageMaintenanceWindow.xaml.cs ---
using System.Threading.Tasks;
using System.Windows;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

// --- Janela modal de manutenção e limpeza de armazenamento ---
public partial class StorageMaintenanceWindow : Window
{
    private readonly StorageMaintenanceViewModel _viewModel;

    public StorageMaintenanceWindow()
    {
        InitializeComponent();
        WindowLocalization.BindTitle(this, () => UiStrings.Instance.StorageWindowTitle);
        _viewModel = new StorageMaintenanceViewModel(new StorageMaintenanceDialogsHost(this));
        _viewModel.RequestClose += Close;
        DataContext = _viewModel;
        Loaded += OnLoaded;
    }

    // --- Carrega estimativa de espaço ao abrir ---
    private async void OnLoaded(object sender, RoutedEventArgs e) =>
        await _viewModel.RefreshOnLoadAsync();
}
