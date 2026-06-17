using System;
using System.IO;
using System.Text.Json;

namespace RatAnalyzer.Desktop.Infrastructure;

public sealed class UserSettings
{
    public string? Language { get; set; }
    public bool HasChosenLanguage { get; set; }
}

public static class UserSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private static string SettingsPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RatAnalyzer",
            "ui-settings.json");

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
