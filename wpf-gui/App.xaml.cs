using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;

namespace RatAnalyzer.Desktop;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        // Hyper-V cmdlets e scripts requerem privilégios de Administrador.
        // Se a app não estiver elevada, relança com UAC (runas) para permitir logs/streaming normal.
        try
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            var isAdmin = principal.IsInRole(WindowsBuiltInRole.Administrator);
            if (!isAdmin)
            {
                var exe = Process.GetCurrentProcess().MainModule?.FileName;
                if (!string.IsNullOrWhiteSpace(exe))
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = exe,
                        UseShellExecute = true,
                        Verb = "runas",
                        Arguments = string.Join(" ", e.Args ?? Array.Empty<string>())
                    };
                    Process.Start(psi);
                    Shutdown();
                    return;
                }
            }
        }
        catch
        {
            // Se falhar a relançar, deixa a app continuar (scripts vão falhar e mostrar erro).
        }

        base.OnStartup(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        // Ao fechar o WPF, limpar backend gerido e cache local de jobs.
        ShutdownManager.CleanupOnExit();
        base.OnExit(e);
    }
}

