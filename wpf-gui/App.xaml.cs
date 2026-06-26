// --- Módulo: App.xaml.cs ---
// Ponto de entrada WPF com verificação de privilégios de administrador.
using System;
using System.Diagnostics;
using System.Security.Principal;
using System.Windows;



using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Localization;



namespace RatAnalyzer.Desktop;



// --- Classe de aplicação WPF (ponto de entrada) ---
public partial class App : Application
{
    // --- Construtor: regista limpeza ao terminar sessão Windows ---
    public App()
    {
        SessionEnding += (_, _) => ShutdownManager.CleanupOnExit();
    }



    // --- Arranque: exige elevação de administrador ---
    protected override void OnStartup(StartupEventArgs e)
    {
        if (!IsRunningAsAdministrator())
        {
            // *Sem admin: mostra aviso localizado e encerra*
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



    // --- Verifica se o processo corre com privilégios de administrador ---
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



    // --- Saída: limpa backend, frontend e artefatos temporários ---
    protected override void OnExit(ExitEventArgs e)
    {
        ShutdownManager.CleanupOnExit();
        base.OnExit(e);
    }
}

