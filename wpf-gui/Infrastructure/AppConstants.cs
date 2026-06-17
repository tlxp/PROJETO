namespace RatAnalyzer.Desktop.Infrastructure;

using System;
using System.Net.Http;
using RatAnalyzer.Desktop.Localization;

/// <summary>URLs e caminhos partilhados pela aplicação desktop.</summary>
internal static class AppConstants
{
    public const string ApiBaseUrl = "http://127.0.0.1:8000";
    public const string FrontendUrl = "http://localhost:8080";

    /// <summary>Token opcional para endpoints de administração do backend (env RATANALYZER_API_TOKEN).</summary>
    public static string? BackendApiToken =>
        Environment.GetEnvironmentVariable("RATANALYZER_API_TOKEN");

    public static void ApplyAdminToken(HttpClient client)
    {
        var token = BackendApiToken;
        if (!string.IsNullOrWhiteSpace(token))
            client.DefaultRequestHeaders.Add("X-API-Token", token);
    }

    public static void ApplyLanguageHeader(HttpClient client)
    {
        client.DefaultRequestHeaders.Remove("Accept-Language");
        client.DefaultRequestHeaders.Add("Accept-Language", LocalizationManager.GetAcceptLanguage());
    }

    /// <summary>URL do frontend com parâmetro <c>?lang=</c> para sincronizar i18n web.</summary>
    public static string BuildFrontendUrl(string? pathAndQuery = null)
    {
        var lang = LocalizationManager.LanguageCode;
        var baseUrl = FrontendUrl.TrimEnd('/');
        if (string.IsNullOrWhiteSpace(pathAndQuery))
            return $"{baseUrl}/?lang={lang}";

        var path = pathAndQuery.StartsWith('/') ? pathAndQuery : "/" + pathAndQuery;
        var sep = path.Contains('?', StringComparison.Ordinal) ? '&' : '?';
        return $"{baseUrl}{path}{sep}lang={lang}";
    }

    public static void PropagateLanguageEnvironment(System.Diagnostics.ProcessStartInfo psi)
    {
        psi.Environment["RATANALYZER_LANG"] = LocalizationManager.LanguageCode;
        psi.Environment["VITE_DEFAULT_LOCALE"] = LocalizationManager.LanguageCode;
    }
}
