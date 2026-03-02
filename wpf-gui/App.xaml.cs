using System.Windows;

namespace RatAnalyzer.Desktop;

public partial class App : Application
{
    protected override void OnExit(ExitEventArgs e)
    {
        // Ao fechar o WPF, limpar backend gerido e cache local de jobs.
        ShutdownManager.CleanupOnExit();
        base.OnExit(e);
    }
}

