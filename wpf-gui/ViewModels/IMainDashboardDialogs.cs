// --- Módulo: IMainDashboardDialogs.cs ---
using System;

using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.ViewModels;

// --- Diálogos e navegação do dashboard principal — implementado pela view WPF ---
public interface IMainDashboardDialogs
{
    string? PickAnalysisFile();

    void ShowInfo(string message, string title = AppConstants.AppDisplayName);

    void ShowError(string message, string title);

    void ShowWarning(string message, string title);

    bool IsAdministrator();

    void ShowAdministratorRequired();

    void OpenBrowserUrl(string url);

    void OpenVmAnalysis(
        string samplePath,
        bool runFirstTimeSetup,
        int sampleTimeoutSeconds,
        bool waitForSampleExit,
        string? linkedJobId = null,
        Action<string>? onJobIdKnown = null);

    void OpenStorageMaintenance();
}
