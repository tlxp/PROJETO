namespace RatAnalyzer.Desktop.ViewModels;

/// <summary>Diálogos e navegação do dashboard principal — implementado pela view WPF.</summary>
public interface IMainDashboardDialogs
{
    string? PickAnalysisFile();

    void ShowInfo(string message, string title = "RAT Analyzer");

    void ShowError(string message, string title);

    void ShowWarning(string message, string title);

    bool IsAdministrator();

    void ShowAdministratorRequired();

    void OpenVmAnalysis(string samplePath, bool runFirstTimeSetup);

    void OpenStorageMaintenance();

    void OpenBrowserUrl(string url);
}
