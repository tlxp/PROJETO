using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace RatAnalyzer.Desktop.Views;

public partial class FileDropPage : Page
{
    private string? _currentFilePath;

    public FileDropPage()
    {
        InitializeComponent();
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            e.Effects = DragDropEffects.Copy;
        }
        else
        {
            e.Effects = DragDropEffects.None;
        }

        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            return;
        }

        if (e.Data.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0)
        {
            return;
        }

        _currentFilePath = files[0];

        SelectedFileText.Text = _currentFilePath;
        AnalysisOptionsPanel.Visibility = Visibility.Visible;
    }

    private void OnStaticAnalysisClicked(object sender, RoutedEventArgs e)
    {
        if (_currentFilePath is null)
        {
            MessageBox.Show("Nenhum ficheiro selecionado.", "RAT Analyzer", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        MessageBox.Show(
            $"(Placeholder)\n\nAqui seria iniciada a ANÁLISE ESTÁTICA para:\n{_currentFilePath}\n\nMais tarde isto irá chamar o backend /api/analyze_stream ou /api/analysis?analysis_type=static.",
            "Análise estática",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void OnDynamicAnalysisClicked(object sender, RoutedEventArgs e)
    {
        if (_currentFilePath is null)
        {
            MessageBox.Show("Nenhum ficheiro selecionado.", "RAT Analyzer", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        MessageBox.Show(
            $"(Placeholder)\n\nAqui seria iniciada a ANÁLISE COMPORTAMENTAL/DINÂMICA em VM para:\n{_currentFilePath}\n\nMais tarde isto irá criar um job dinâmico com o driver de sandbox.",
            "Análise comportamental",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }
}

