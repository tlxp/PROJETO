using System.Threading.Tasks;

namespace RatAnalyzer.Desktop.ViewModels;

/// <summary>Diálogos modais da análise VM — implementado pela janela WPF.</summary>
public interface IVmAnalysisDialogs
{
    Task<bool> ConfirmYesNoAsync(string title, string message, bool warningIcon = false);

    Task<bool> ConfirmAdkInstallAsync();

    void ShowIsoMissingDialog(string? configuredIsoPath);
}
