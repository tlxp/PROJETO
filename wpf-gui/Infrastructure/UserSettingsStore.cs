// --- Módulo: UserSettingsStore.cs ---
// Persistência de preferências de idioma em %LOCALAPPDATA%\RatAnalyzer.
using System;
using System.IO;
using System.Text.Json;
namespace RatAnalyzer.Desktop.Infrastructure;
// --- Modelo de preferências do utilizador ---
public sealed class UserSettings
{
    public string? Language { get; set; }
    public bool HasChosenLanguage { get; set; }
}
// --- Persistência de definições da UI em %LOCALAPPDATA%\RatAnalyzer ---
public static class UserSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static string SettingsPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RatAnalyzer",
            "ui-settings.json");
    // --- Carrega definições ou devolve valores por omissão ---
    public static UserSettings Load()
    {
        try
        {
            if (!File.Exists(SettingsPath))
                return new UserSettings();
            var json = File.ReadAllText(SettingsPath);
            return JsonSerializer.Deserialize<UserSettings>(json) ?? new UserSettings();
        }
        catch
        {
            return new UserSettings();
        }
    }
    // --- Grava idioma escolhido e marca HasChosenLanguage ---
    public static void SaveLanguage(string languageCode)
    {
        var settings = Load();
        settings.Language = languageCode;
        settings.HasChosenLanguage = true;
        var dir = Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(dir);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, JsonOptions));
    }
}
