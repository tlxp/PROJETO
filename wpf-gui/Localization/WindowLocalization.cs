using System;
using System.Windows;

namespace RatAnalyzer.Desktop.Localization;

public static class WindowLocalization
{
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
