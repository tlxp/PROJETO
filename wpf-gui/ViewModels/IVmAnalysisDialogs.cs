// --- Módulo: IVmAnalysisDialogs.cs ---
// Contrato de diálogos da janela de análise VM.
using System.Threading.Tasks;



namespace RatAnalyzer.Desktop.ViewModels;



// --- Diálogos modais da análise VM — implementado pela janela WPF ---
public interface IVmAnalysisDialogs
{
    Task<bool> ConfirmYesNoAsync(string title, string message, bool warningIcon = false);



    Task<bool> ConfirmAdkInstallAsync();



    void ShowIsoMissingDialog(string? configuredIsoPath);
}

