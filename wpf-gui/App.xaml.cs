using System;
using System.Diagnostics;
using System.Windows;

namespace RatAnalyzer.Desktop;

public partial class App : Application
{
    public App()
    {
        SessionEnding += (_, _) => ShutdownManager.CleanupOnExit();
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        // A análise dinâmica (Hyper-V) requer privilégios de administrador.
        // A elevação UAC é pedida apenas ao iniciar essa análise (VmAnalysisWindow / MainDashboardView),
        // não no arranque global — evita correr sempre como admin.
        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        // Ao fechar o WPF, limpar backend gerido e cache local de jobs.
        ShutdownManager.CleanupOnExit();
        base.OnExit(e);
    }
}

