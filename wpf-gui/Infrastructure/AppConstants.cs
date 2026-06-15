namespace RatAnalyzer.Desktop.Infrastructure;

using System;
using System.Net.Http;

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
}
