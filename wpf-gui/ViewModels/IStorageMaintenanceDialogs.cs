// --- Módulo: IStorageMaintenanceDialogs.cs ---
// Contrato de diálogos da manutenção de armazenamento.
namespace RatAnalyzer.Desktop.ViewModels;



// --- Confirmações modais da janela de manutenção de armazenamento ---
public interface IStorageMaintenanceDialogs
{
    bool Confirm(string message, string title, bool warningIcon = false);



    void ShowWarning(string message, string title = "Manutenção");
}

