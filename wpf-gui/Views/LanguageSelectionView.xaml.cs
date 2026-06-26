// --- Módulo: LanguageSelectionView.xaml.cs ---
// Ecrã de escolha de idioma na primeira execução.
using System;
using System.Windows;
using System.Windows.Controls;
using RatAnalyzer.Desktop.Localization;
namespace RatAnalyzer.Desktop.Views;
// --- Ecrã de escolha de idioma (primeira execução ou alteração posterior) ---
public partial class LanguageSelectionView : UserControl
{
    public static readonly DependencyProperty ShowCancelProperty =
        DependencyProperty.Register(nameof(ShowCancel), typeof(bool), typeof(LanguageSelectionView),
            new PropertyMetadata(false));
    public event EventHandler<string>? LanguageConfirmed;
    public event EventHandler? Cancelled;
    private string? _selectedLanguage;
    public LanguageSelectionView()
    {
        InitializeComponent();
        DataContext = UiStrings.Instance;
        Loaded += (_, _) => SyncSelectionFromManager();
    }
    public bool ShowCancel
    {
        get => (bool)GetValue(ShowCancelProperty);
        set => SetValue(ShowCancelProperty, value);
    }
    // --- Sincroniza tabs com idioma atual do LocalizationManager ---
    private void SyncSelectionFromManager()
    {
        _selectedLanguage = LocalizationManager.LanguageCode;
        UpdateTabStyles();
        ContinueButton.IsEnabled = !string.IsNullOrEmpty(_selectedLanguage);
    }
    // --- português Tab Click ---
    private void PortugueseTab_Click(object sender, RoutedEventArgs e)
    {
        _selectedLanguage = LocalizationManager.Portuguese;
        UpdateTabStyles();
        ContinueButton.IsEnabled = true;
    }
    // --- inglês Tab Click ---
    private void EnglishTab_Click(object sender, RoutedEventArgs e)
    {
        _selectedLanguage = LocalizationManager.English;
        UpdateTabStyles();
        ContinueButton.IsEnabled = true;
    }
    // --- Atualiza estilos visuais das tabs conforme seleção ---
    private void UpdateTabStyles()
    {
        var selected = _selectedLanguage == LocalizationManager.English ? "en" : "pt";
        PortugueseTab.Style = selected == "pt"
            ? (Style)FindResource("LanguageTabSelectedStyle")
            : (Style)FindResource("LanguageTabStyle");
        EnglishTab.Style = selected == "en"
            ? (Style)FindResource("LanguageTabSelectedStyle")
            : (Style)FindResource("LanguageTabStyle");
    }
    // --- Persiste idioma e notifica confirmação ---
    private void ContinueButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_selectedLanguage))
            return;
        LocalizationManager.SetLanguage(_selectedLanguage);
        LanguageConfirmed?.Invoke(this, _selectedLanguage);
    }
    // --- cancelamento Button Click ---
    private void CancelButton_Click(object sender, RoutedEventArgs e) =>
        Cancelled?.Invoke(this, EventArgs.Empty);
}
