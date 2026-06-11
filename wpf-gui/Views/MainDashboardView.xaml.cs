using System.Windows;
using System.Windows.Controls;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

public partial class MainDashboardView : UserControl
{
    private readonly MainDashboardViewModel _viewModel;

    public MainDashboardView()
    {
        InitializeComponent();
        _viewModel = new MainDashboardViewModel(new MainDashboardDialogsHost(this));
        DataContext = _viewModel;
    }

    private void FileDropArea_Drop(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop))
            return;

        if (e.Data.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0)
            return;

        _viewModel.OnFileSelected(files[0]);
    }
}
