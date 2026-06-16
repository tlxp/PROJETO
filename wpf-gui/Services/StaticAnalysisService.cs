using System;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.Services;

/// <summary>Cliente HTTP para análise estática via backend FastAPI (streaming + job unificado).</summary>
public sealed class StaticAnalysisService
{
    private const string GhidraProgressPrefix = "[GHIDRA_PROGRESS]";

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
        string? linkedJobId,
        IProgress<string>? progress,
        IProgress<double>? progressPercent,
        Action<string>? onJobIdKnown = null,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(filePath))
            throw new InvalidOperationException("O ficheiro selecionado já não existe no disco.");

        using var client = CreateClient();
        await EnsureBackendRunningAsync(client, progress, cancellationToken).ConfigureAwait(false);

        var fileName = Path.GetFileName(filePath);
        var jobId = linkedJobId;

        progress?.Report("A registar análise estática em curso no backend...");
        jobId = await MarkStaticRunningAsync(client, jobId, fileName, 0, progress, cancellationToken)
            .ConfigureAwait(false);
        onJobIdKnown?.Invoke(jobId);

        progress?.Report("A analisar ficheiro (Ghidra / YARA / IL)...");

        var lastReportedProgress = -1.0;
        var analyze = await RunAnalyzeStreamAsync(
            client,
            filePath,
            msg => progress?.Report(msg),
            pct =>
            {
                progressPercent?.Report(pct);
                if (pct - lastReportedProgress >= 4.0 || (pct >= 99.0 && lastReportedProgress < 99.0))
                {
                    lastReportedProgress = pct;
                    _ = TryUpdateStaticProgressAsync(client, jobId, fileName, pct, cancellationToken);
                }
            },
            cancellationToken).ConfigureAwait(false);

        progress?.Report("A publicar resultados no backend...");

        jobId = await PublishStaticCompletedAsync(client, jobId, fileName, analyze, cancellationToken)
            .ConfigureAwait(false);

        progress?.Report("Análise estática concluída e registada no backend.");
        return jobId;
    }

    private static async Task<string> MarkStaticRunningAsync(
        HttpClient client,
        string? jobId,
        string fileName,
        double staticProgress,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
        var payload = new StaticUploadPayload
        {
            JobId = string.IsNullOrWhiteSpace(jobId) ? null : jobId,
            FileName = fileName,
            Status = "running",
            StaticProgress = staticProgress
        };
        return await PostStaticUploadAsync(client, payload, progress, cancellationToken).ConfigureAwait(false);
    }

    private static async Task TryUpdateStaticProgressAsync(
        HttpClient client,
        string jobId,
        string fileName,
        double staticProgress,
        CancellationToken cancellationToken)
    {
        try
        {
            var payload = new StaticUploadPayload
            {
                JobId = jobId,
                FileName = fileName,
                Status = "running",
                StaticProgress = staticProgress
            };
            await PostStaticUploadAsync(client, payload, progress: null, cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            /* progresso é best-effort */
        }
    }

    private static async Task<AnalyzeResponse> RunAnalyzeStreamAsync(
        HttpClient client,
        string filePath,
        Action<string>? onLog,
        Action<double>? onGhidraProgress,
        CancellationToken cancellationToken)
    {
        using var form = new MultipartFormDataContent();
        await using var stream = File.OpenRead(filePath);
        var fileContent = new StreamContent(stream);
        fileContent.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
        form.Add(fileContent, "file", Path.GetFileName(filePath));

        using var request = new HttpRequestMessage(HttpMethod.Post, $"{AppConstants.ApiBaseUrl}/api/analyze_stream")
        {
            Content = form
        };

        using var response = await client
            .SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);

        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException(
                $"Falha ao executar análise estática (HTTP {(int)response.StatusCode}).\n\n{body}");
        }

        await using var responseStream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var reader = new StreamReader(responseStream, Encoding.UTF8);

        AnalyzeResponse? result = null;
        while (true)
        {
            var line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false);
            if (line is null)
                break;
            if (string.IsNullOrWhiteSpace(line))
                continue;

            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;
            if (!root.TryGetProperty("type", out var typeProp))
                continue;

            var type = typeProp.GetString();
            switch (type)
            {
                case "log" when root.TryGetProperty("message", out var msgProp):
                {
                    var msg = msgProp.GetString() ?? "";
                    if (msg.StartsWith(GhidraProgressPrefix, StringComparison.Ordinal))
                    {
                        var rest = msg[GhidraProgressPrefix.Length..].Trim().TrimEnd('%');
                        if (double.TryParse(rest, NumberStyles.Float, CultureInfo.InvariantCulture, out var pct))
                            onGhidraProgress?.Invoke(Math.Clamp(pct, 0, 100));
                    }
                    else if (!string.IsNullOrWhiteSpace(msg))
                    {
                        onLog?.Invoke(msg);
                    }
                    break;
                }
                case "error" when root.TryGetProperty("message", out var errProp):
                    throw new InvalidOperationException(errProp.GetString() ?? "Erro na análise estática.");
                case "result":
                    result = JsonSerializer.Deserialize<AnalyzeResponse>(line, JsonInsensitive);
                    break;
            }
        }

        if (result is null)
            throw new InvalidOperationException("Resposta de streaming terminou sem resultado final.");

        return result;
    }

    private static async Task<string> PublishStaticCompletedAsync(
        HttpClient client,
        string jobId,
        string fileName,
        AnalyzeResponse analyze,
        CancellationToken cancellationToken)
    {
        var payload = new StaticUploadPayload
        {
            JobId = jobId,
            FileName = analyze.FileName ?? fileName,
            Report = analyze.Report ?? string.Empty,
            CCode = analyze.CCode ?? string.Empty,
            IlCode = analyze.IlCode ?? string.Empty,
            RiskScore = analyze.RiskScore,
            RiskLevel = analyze.RiskLevel ?? string.Empty,
            FlaggedIndicators = analyze.FlaggedIndicators ?? Array.Empty<string>(),
            FlaggedFunctions = analyze.FlaggedFunctions ?? Array.Empty<object>(),
            Status = "completed",
            StaticProgress = 100
        };
        return await PostStaticUploadAsync(client, payload, progress: null, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<string> PostStaticUploadAsync(
        HttpClient client,
        StaticUploadPayload payload,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
        var jsonPayload = JsonSerializer.Serialize(payload, JsonCamelCase);
        using var uploadContent = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

        HttpResponseMessage uploadResponse;
        try
        {
            uploadResponse = await client
                .PostAsync($"{AppConstants.ApiBaseUrl}/api/analysis/upload_static", uploadContent, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                "Não foi possível publicar o estado da análise estática no backend.");
        }

        if (!uploadResponse.IsSuccessStatusCode)
        {
            var body = await uploadResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException(
                $"Falha ao registar análise estática no backend (HTTP {(int)uploadResponse.StatusCode}).\n\n{body}");
        }

        var uploadJson = await uploadResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        var submit = JsonSerializer.Deserialize<SubmitResponse>(uploadJson, JsonInsensitive);
        if (submit is null || string.IsNullOrWhiteSpace(submit.JobId))
            throw new InvalidOperationException("Resposta inesperada ao publicar análise estática (jobId em falta).");

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
        public string? JobId { get; set; }
        public string FileName { get; set; } = string.Empty;
        public string Report { get; set; } = string.Empty;
        public string CCode { get; set; } = string.Empty;
        public string IlCode { get; set; } = string.Empty;
        public int RiskScore { get; set; }
        public string RiskLevel { get; set; } = string.Empty;
        public string[]? FlaggedIndicators { get; set; }
        public object[]? FlaggedFunctions { get; set; }
        public string Status { get; set; } = "completed";
        public double? StaticProgress { get; set; }
    }
}
