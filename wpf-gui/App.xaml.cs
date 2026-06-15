using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

using RatAnalyzer.Desktop.Bootstrap;

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
            MessageBox.Show(
                "O RAT Analyzer deve ser executado como Administrador (Hyper-V, scripts PowerShell e outras funcionalidades).\n\n" +
                "Clique direito em RatAnalyzer.Desktop.exe → \"Executar como administrador\"\n" +
                "ou abra o PowerShell como Administrador e execute: dotnet run",
                "Elevação necessária",
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

