// --- Módulo: AppNavigation.cs ---
// Callbacks de navegação global da aplicação WPF.
using System;



namespace RatAnalyzer.Desktop.Localization;



// --- Callbacks de navegação global (definidos pela MainWindow) ---
public static class AppNavigation
{
    public static Action? RequestLanguagePicker { get; set; }
}

