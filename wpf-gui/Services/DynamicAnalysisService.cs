// --- Módulo: DynamicAnalysisService.cs ---
// Cliente HTTP para análise dinâmica no backend.
using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;
namespace RatAnalyzer.Desktop.Services;
// --- Publica relatórios de análise dinâmica (VM Hyper-V) no backend FastAPI ---
public sealed class DynamicAnalysisService
{
    private static readonly JsonSerializerOptions JsonInsensitive = new()
    {
        PropertyNameCaseInsensitive = true
    };
    private static readonly JsonSerializerOptions JsonCamelCase = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };
    // --- Marca um job existente (ou cria um novo) como análise dinâmica em curso ---
    public async Task<string> MarkRunningAsync(
        string? linkedJobId,
        string fileName,
        string? runId,
        IProgress<string>? progress,
        CancellationToken cancellationToken = default)
    {
        using var client = CreateClient();
        await EnsureBackendRunningAsync(client, progress, cancellationToken).ConfigureAwait(false);
        progress?.Report(LocalizationManager.Get(LocKeys.LogDynamicRegister));
        var payload = new DynamicUploadPayload
        {
            JobId = string.IsNullOrWhiteSpace(linkedJobId) ? null : linkedJobId,
            FileName = fileName,
            Report = string.Empty,
            RunId = runId,
            Status = "running"
        };
        return await PostUploadAsync(client, payload, cancellationToken).ConfigureAwait(false);
    }
    // --- Publica o relatório textual transferido da VM e devolve o jobId associado ---
    public async Task<string> PublishReportAsync(
        string? linkedJobId,
        string reportPath,
        string fileName,
        string? runId,
        IProgress<string>? progress,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(reportPath))
            throw new InvalidOperationException($"Relatório da VM não encontrado: {reportPath}");
        var reportText = await File.ReadAllTextAsync(reportPath, cancellationToken).ConfigureAwait(false);
        using var client = CreateClient();
        await EnsureBackendRunningAsync(client, progress, cancellationToken).ConfigureAwait(false);
        progress?.Report(LocalizationManager.Get(LocKeys.LogDynamicPublish));
        var payload = new DynamicUploadPayload
        {
            JobId = string.IsNullOrWhiteSpace(linkedJobId) ? null : linkedJobId,
            FileName = fileName,
            Report = reportText,
            RunId = runId,
            Status = "completed"
        };
        return await PostUploadAsync(client, payload, cancellationToken).ConfigureAwait(false);
    }
    // --- pós upload  ---
    private static async Task<string> PostUploadAsync(
        HttpClient client,
        DynamicUploadPayload payload,
        CancellationToken cancellationToken)
    {
        var jsonPayload = JsonSerializer.Serialize(payload, JsonCamelCase);
        using var uploadContent = new StringContent(jsonPayload, Encoding.UTF8, "application/json");
        HttpResponseMessage uploadResponse;
        try
        {
            uploadResponse = await client.PostAsync(
                    $"{AppConstants.ApiBaseUrl}/api/analysis/upload_dynamic",
                    uploadContent,
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                "Não foi possível publicar o resultado da análise dinâmica no backend.");
        }
        if (!uploadResponse.IsSuccessStatusCode)
        {
            var body = await uploadResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            throw new InvalidOperationException(
                $"Falha ao registar resultado dinâmico no backend (HTTP {(int)uploadResponse.StatusCode}).\n\n{body}");
        }
        var uploadJson = await uploadResponse.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        var submit = JsonSerializer.Deserialize<SubmitResponse>(uploadJson, JsonInsensitive);
        if (submit is null || string.IsNullOrWhiteSpace(submit.JobId))
            throw new InvalidOperationException("Resposta inesperada ao publicar resultado dinâmico (jobId em falta).");
        return submit.JobId;
    }
    // --- Cria Client ---
    private static HttpClient CreateClient()
    {
        var client = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
        AppConstants.ApplyAdminToken(client);
        AppConstants.ApplyLanguageHeader(client);
        return client;
    }
    // --- Garante backend em execução ---
    private static async Task EnsureBackendRunningAsync(
        HttpClient client,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
        if (await IsBackendUpAsync(client, cancellationToken).ConfigureAwait(false))
            return;
        progress?.Report(LocalizationManager.Get(LocKeys.LogBackendServiceStart));
        await StartupSequence.StartBackendAsync(client).ConfigureAwait(false);
    }
    // --- Verifica se backend activo ---
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
    // --- Classe Submit Response ---
    private sealed class SubmitResponse
    {
        public string? JobId { get; set; }
    }
    // --- Classe dinâmica upload Payload ---
    private sealed class DynamicUploadPayload
    {
        public string? JobId { get; set; }
        public string FileName { get; set; } = string.Empty;
        public string Report { get; set; } = string.Empty;
        public string? RunId { get; set; }
        public string Status { get; set; } = "completed";
    }
}
