// --- Módulo: AppConstants.cs ---
// URLs, tokens e utilitários HTTP partilhados pela aplicação.
namespace RatAnalyzer.Desktop.Infrastructure;



using System;
using System.Net.Http;
using RatAnalyzer.Desktop.Localization;



// --- URLs, tokens e utilitários HTTP partilhados ---
internal static class AppConstants
{
    public const string AppDisplayName = "Rat Analyzer";
    public const string ExeFileName = "Rat Analyzer.exe";



    // --- Constantes de URL ---
    public const string ApiBaseUrl = "http://127.0.0.1:8000";
    public const string FrontendUrl = "http://localhost:8080";



    // --- Token de API opcional (variável RATANALYZER_API_TOKEN) ---
    public static string? BackendApiToken =>
        Environment.GetEnvironmentVariable("RATANALYZER_API_TOKEN");



    // --- Adiciona cabeçalho X-API-Token ao HttpClient ---
    public static void ApplyAdminToken(HttpClient client)
    {
        var token = BackendApiToken;
        if (!string.IsNullOrWhiteSpace(token))
            client.DefaultRequestHeaders.Add("X-API-Token", token);
    }



    // --- Define Accept-Language conforme idioma da UI ---
    public static void ApplyLanguageHeader(HttpClient client)
    {
        client.DefaultRequestHeaders.Remove("Accept-Language");
        client.DefaultRequestHeaders.Add("Accept-Language", LocalizationManager.GetAcceptLanguage());
    }



    // --- Constrói URL do frontend com parâmetro lang para i18n web ---
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



    // --- Propaga idioma para processos filhos (backend/frontend) ---
    public static void PropagateLanguageEnvironment(System.Diagnostics.ProcessStartInfo psi)
    {
        psi.Environment["RATANALYZER_LANG"] = LocalizationManager.LanguageCode;
        psi.Environment["VITE_DEFAULT_LOCALE"] = LocalizationManager.LanguageCode;
    }
}

