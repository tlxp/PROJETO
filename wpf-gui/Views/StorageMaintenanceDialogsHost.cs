// --- Módulo: StorageMaintenanceDialogsHost.cs ---
// Implementação WPF dos diálogos de manutenção.
using System.Windows;
using RatAnalyzer.Desktop.ViewModels;



namespace RatAnalyzer.Desktop.Views;



// --- Diálogos de confirmação da janela de manutenção ---
internal sealed class StorageMaintenanceDialogsHost : IStorageMaintenanceDialogs
{
    private readonly Window _owner;



    public StorageMaintenanceDialogsHost(Window owner) => _owner = owner;



    // --- Confirm ---
    public bool Confirm(string message, string title, bool warningIcon = false) =>
        MessageBox.Show(
            _owner,
            message,
            title,
            MessageBoxButton.YesNo,
            warningIcon ? MessageBoxImage.Warning : MessageBoxImage.Question) == MessageBoxResult.Yes;



    // --- Exibe Warning ---
    public void ShowWarning(string message, string title = "Manutenção") =>
        MessageBox.Show(_owner, message, title, MessageBoxButton.OK, MessageBoxImage.Warning);
}

