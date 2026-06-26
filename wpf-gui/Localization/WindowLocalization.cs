// --- Módulo: WindowLocalization.cs ---
// Extensões para localizar títulos e controlos de janelas WPF.
using System;
using System.Windows;



namespace RatAnalyzer.Desktop.Localization;



// --- Liga título de janela ao idioma activo ---
public static class WindowLocalization
{
    // --- Atualiza Title quando o idioma muda e remove handler ao fechar ---
    public static void BindTitle(Window window, Func<string> getTitle)
    {
        void Apply() => window.Title = getTitle();
        Apply();
        LocalizationManager.LanguageChanged += OnLanguageChanged;



        window.Closed += (_, _) => LocalizationManager.LanguageChanged -= OnLanguageChanged;
        return;



        void OnLanguageChanged(object? sender, EventArgs e) => Apply();
    }
}

