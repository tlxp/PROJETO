using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Localization;

namespace RatAnalyzer.Desktop;

public partial class App : Application
{
    public App()
    {
        SessionEnding += (_, _) => ShutdownManager.CleanupOnExit();
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        if (!IsRunningAsAdministrator())
        {
            var settings = Infrastructure.UserSettingsStore.Load();
            LocalizationManager.Initialize(settings);
            MessageBox.Show(
                LocalizationManager.Get(LocKeys.MsgElevationRequired),
                LocalizationManager.Get(LocKeys.MsgAdminRequiredTitle),
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            Shutdown();
            return;
        }

        base.OnStartup(e);
    }

    private static bool IsRunningAsAdministrator()
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

    protected override void OnExit(ExitEventArgs e)
    {
        // Ao fechar o WPF, limpar backend gerido e cache local de jobs.
        ShutdownManager.CleanupOnExit();
        base.OnExit(e);
    }
}

