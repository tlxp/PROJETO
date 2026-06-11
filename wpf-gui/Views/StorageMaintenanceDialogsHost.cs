using System.Windows;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

internal sealed class StorageMaintenanceDialogsHost : IStorageMaintenanceDialogs
{
    private readonly Window _owner;

    public StorageMaintenanceDialogsHost(Window owner) => _owner = owner;

    public bool Confirm(string message, string title, bool warningIcon = false) =>
        MessageBox.Show(
            _owner,
            message,
            title,
            MessageBoxButton.YesNo,
            warningIcon ? MessageBoxImage.Warning : MessageBoxImage.Question) == MessageBoxResult.Yes;

    public void ShowWarning(string message, string title = "Manutenção") =>
        MessageBox.Show(_owner, message, title, MessageBoxButton.OK, MessageBoxImage.Warning);
}
