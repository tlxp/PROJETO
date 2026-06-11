using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RatAnalyzer.Desktop.Services;

/// <summary>Cliente HTTP para análise estática via backend FastAPI.</summary>
public sealed class StaticAnalysisService
{
    private static readonly JsonSerializerOptions JsonInsensitive = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly JsonSerializerOptions JsonCamelCase = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public async Task<string> RunAndPublishAsync(
        string filePath,
        IProgress<string>? progress,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(filePath))
            throw new InvalidOperationException("O ficheiro selecionado já não existe no disco.");

        using var client = CreateClient();
        await EnsureBackendRunningAsync(client, progress, cancellationToken).ConfigureAwait(false);

        progress?.Report("A enviar ficheiro para análise estática...");

        using var form = new MultipartFormDataContent();
        await using var stream = File.OpenRead(filePath);
        var fileContent = new StreamContent(stream);
        form.Add(fileContent, "file", Path.GetFileName(filePath));

        HttpResponseMessage analyzeResponse;
        try
        {
            analyzeResponse = await client.PostAsync($"{AppConstants.ApiBaseUrl}/api/analyze", form, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                $"Não foi possível contactar o backend em {AppConstants.ApiBaseUrl}, mesmo depois de tentar arrancar o servidor.\n\n" +
                "Tente iniciar manualmente a partir da pasta 'backend' com:\n" +
                "uvicorn api:app --reload --host 127.0.0.1 --port 8000");
        }

        if (!analyzeResponse.IsSuccessStatusCode)
        {
            var body = await analyzeResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException(
                $"Falha ao executar análise estática (HTTP {(int)analyzeResponse.StatusCode}).\n\n{body}");
        }

        var analyzeJson = await analyzeResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        var analyze = JsonSerializer.Deserialize<AnalyzeResponse>(analyzeJson, JsonInsensitive);
        if (analyze is null)
            throw new InvalidOperationException("Resposta inesperada do backend ao executar a análise estática.");

        progress?.Report("A publicar resultados no backend...");

        var uploadPayload = new StaticUploadPayload
        {
            FileName = analyze.FileName ?? Path.GetFileName(filePath),
            Report = analyze.Report ?? string.Empty,
            CCode = analyze.CCode ?? string.Empty,
            IlCode = analyze.IlCode ?? string.Empty,
            RiskScore = analyze.RiskScore,
            RiskLevel = analyze.RiskLevel ?? string.Empty,
            FlaggedIndicators = analyze.FlaggedIndicators ?? Array.Empty<string>(),
            FlaggedFunctions = analyze.FlaggedFunctions ?? Array.Empty<object>()
        };

        var jsonPayload = JsonSerializer.Serialize(uploadPayload, JsonCamelCase);
        using var uploadContent = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

        HttpResponseMessage uploadResponse;
        try
        {
            uploadResponse = await client.PostAsync(
                    $"{AppConstants.ApiBaseUrl}/api/analysis/upload_static",
                    uploadContent,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                "Não foi possível publicar o resultado da análise estática no backend.");
        }

        if (!uploadResponse.IsSuccessStatusCode)
        {
            var body = await uploadResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException(
                $"Falha ao registar resultado estático no backend (HTTP {(int)uploadResponse.StatusCode}).\n\n{body}");
        }

        var uploadJson = await uploadResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        var submit = JsonSerializer.Deserialize<SubmitResponse>(uploadJson, JsonInsensitive);
        if (submit is null || string.IsNullOrWhiteSpace(submit.JobId))
            throw new InvalidOperationException("Resposta inesperada ao publicar o resultado estático (jobId em falta).");

        progress?.Report("Análise estática concluída e registada no backend.");
        return submit.JobId;
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        AppConstants.ApplyAdminToken(client);
        return client;
    }

    private static async Task EnsureBackendRunningAsync(
        HttpClient client,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
        if (await IsBackendUpAsync(client, cancellationToken).ConfigureAwait(false))
            return;

        progress?.Report("A iniciar servidor backend (uvicorn)...");
        await StartupSequence.StartBackendAsync(client).ConfigureAwait(false);
    }

    private static async Task<bool> IsBackendUpAsync(HttpClient client, CancellationToken cancellationToken)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            cts.CancelAfter(TimeSpan.FromSeconds(2));
            var response = await client.GetAsync($"{AppConstants.ApiBaseUrl}/api/health", cts.Token)
                .ConfigureAwait(false);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    private sealed class SubmitResponse
    {
        public string? JobId { get; set; }
    }

    private sealed class AnalyzeResponse
    {
        public string? Report { get; set; }
        public string? CCode { get; set; }
        public string? IlCode { get; set; }
        public string? FileName { get; set; }
        public int RiskScore { get; set; }
        public string? RiskLevel { get; set; }
        public string[]? FlaggedIndicators { get; set; }
        public object[]? FlaggedFunctions { get; set; }
    }

    private sealed class StaticUploadPayload
    {
        public string FileName { get; set; } = string.Empty;
        public string Report { get; set; } = string.Empty;
        public string CCode { get; set; } = string.Empty;
        public string IlCode { get; set; } = string.Empty;
        public int RiskScore { get; set; }
        public string RiskLevel { get; set; } = string.Empty;
        public string[]? FlaggedIndicators { get; set; }
        public object[]? FlaggedFunctions { get; set; }
    }
}
