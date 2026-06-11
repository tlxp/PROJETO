using System.Threading.Tasks;
using System.Windows;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

public partial class StorageMaintenanceWindow : Window
{
    private readonly StorageMaintenanceViewModel _viewModel;

    public StorageMaintenanceWindow()
    {
        InitializeComponent();
        _viewModel = new StorageMaintenanceViewModel(new StorageMaintenanceDialogsHost(this));
        _viewModel.RequestClose += Close;
        DataContext = _viewModel;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e) =>
        await _viewModel.RefreshOnLoadAsync();
}
