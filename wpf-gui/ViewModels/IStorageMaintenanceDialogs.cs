namespace RatAnalyzer.Desktop.ViewModels;

/// <summary>Confirmações modais da janela de manutenção de armazenamento.</summary>
public interface IStorageMaintenanceDialogs
{
    bool Confirm(string message, string title, bool warningIcon = false);

    void ShowWarning(string message, string title = "Manutenção");
}
