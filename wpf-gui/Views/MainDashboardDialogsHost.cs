using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;
using System.Windows.Controls;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.Services;
using RatAnalyzer.Desktop.ViewModels;

namespace RatAnalyzer.Desktop.Views;

internal sealed class MainDashboardDialogsHost : IMainDashboardDialogs
{
    private readonly UserControl _view;

    public MainDashboardDialogsHost(UserControl view) => _view = view;

    private Window? Owner => Window.GetWindow(_view);

    public string? PickAnalysisFile()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = LocalizationManager.Get(LocKeys.DialogPickFileTitle),
            Filter = LocalizationManager.Get(LocKeys.DialogPickFileFilter),
            FilterIndex = 1
        };
        return dialog.ShowDialog() == true ? dialog.FileName : null;
    }

    public void ShowInfo(string message, string? title = null) =>
        MessageBox.Show(Owner, message, title ?? LocalizationManager.Get(LocKeys.AppTitle), MessageBoxButton.OK, MessageBoxImage.Information);

    public void ShowError(string message, string title) =>
        MessageBox.Show(Owner, message, title, MessageBoxButton.OK, MessageBoxImage.Error);

    public void ShowWarning(string message, string title) =>
        MessageBox.Show(Owner, message, title, MessageBoxButton.OK, MessageBoxImage.Warning);

    public bool IsAdministrator()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    public void ShowAdministratorRequired() =>
        ShowWarning(
            LocalizationManager.Get(LocKeys.MsgAdminRequired),
            LocalizationManager.Get(LocKeys.MsgAdminRequiredTitle));

    public void OpenVmAnalysis(
        string samplePath,
        bool runFirstTimeSetup,
        int sampleTimeoutSeconds,
        bool waitForSampleExit,
        string? linkedJobId = null,
        Action<string>? onJobIdKnown = null)
    {
        var credentials = ResolveGuestCredentials();
        if (credentials == null)
            return;

        var vmWindow = new VmAnalysisWindow(
            samplePath,
            runFirstTimeSetup,
            sampleTimeoutSeconds,
            waitForSampleExit,
            credentials,
            linkedJobId,
            OpenBrowserUrl,
            onJobIdKnown) { Owner = Owner };
        vmWindow.Show();
    }

    private VmGuestCredentials? ResolveGuestCredentials()
    {
        var fromEnv = VmGuestCredentialStore.TryFromEnvironment();
        if (fromEnv != null)
            return fromEnv;

        var fromSession = VmGuestCredentialStore.TryGetSession();
        if (fromSession != null)
            return fromSession;

        var dialog = new VmGuestCredentialsWindow("analyst") { Owner = Owner };
        if (dialog.ShowDialog() != true)
            return null;

        var credentials = new VmGuestCredentials(dialog.GuestUser.Trim(), dialog.GuestPassword);
        if (dialog.RememberForSession)
            VmGuestCredentialStore.SetSession(credentials);

        return credentials;
    }

    public void OpenStorageMaintenance()
    {
        var w = new StorageMaintenanceWindow { Owner = Owner };
        w.ShowDialog();
    }

    public void OpenBrowserUrl(string url) =>
        Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
}
