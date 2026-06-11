using System;
using System.Globalization;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RatAnalyzer.Desktop.Services;

/// <summary>Operações de estimativa/limpeza no backend e artefactos locais.</summary>
public sealed class StorageMaintenanceService
{
    private static readonly JsonSerializerOptions JsonInsensitive = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private static readonly JsonSerializerOptions JsonCamelCase = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public async Task<StorageEstimateView> GetEstimateAsync(CancellationToken cancellationToken = default)
    {
        using var client = CreateClient(TimeSpan.FromSeconds(10));
        var json = await client.GetStringAsync($"{AppConstants.ApiBaseUrl}/api/storage/estimate", cancellationToken)
            .ConfigureAwait(false);
        var resp = JsonSerializer.Deserialize<EstimateResponse>(json, JsonInsensitive);
        if (resp is null)
            throw new InvalidOperationException("Resposta inesperada do backend ao pedir estimativa.");

        var localEstimate = LocalArtifactCleanup.EstimateLocalArtifacts();
        return new StorageEstimateView
        {
            EstimateText =
                $"Total: {FormatBytes(resp.Bytes.Total)}\n" +
                $"- sandbox_jobs: {FormatBytes(resp.Bytes.SandboxJobs)}\n" +
                $"- reports: {FormatBytes(resp.Bytes.Reports)}\n" +
                $"- decompiled: {FormatBytes(resp.Bytes.Decompiled)}\n" +
                $"- python cache: {FormatBytes(resp.Bytes.PythonCache)}\n" +
                $"- wpf build (bin/obj): {FormatBytes(resp.Bytes.WpfBuild)}\n" +
                $"- frontend dist: {FormatBytes(resp.Bytes.FrontendDist)}\n" +
                $"- temp local de análise: {FormatBytes(localEstimate.TempAnalysisBytes)} ({localEstimate.TempAnalysisDirectories} pastas)",
            PathsText =
                $"DataDir: {resp.Paths.DataDir}\n" +
                $"sandbox_jobs: {resp.Paths.SandboxJobsDir}\n" +
                $"reports: {resp.Paths.ReportsDir}\n" +
                $"decompiled: {resp.Paths.DecompiledDir}\n" +
                $"temp local: {localEstimate.TempPath}"
        };
    }

    public async Task<string> RunCleanupAsync(int retentionDays, int keepMostRecent, CancellationToken cancellationToken = default)
    {
        using var client = CreateClient(TimeSpan.FromSeconds(60));
        var payload = JsonSerializer.Serialize(new { retentionDays, keepMostRecent }, JsonCamelCase);
        using var content = new StringContent(payload, Encoding.UTF8, "application/json");
        var res = await client.PostAsync($"{AppConstants.ApiBaseUrl}/api/storage/cleanup", content, cancellationToken)
            .ConfigureAwait(false);
        var body = await res.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!res.IsSuccessStatusCode)
            throw new InvalidOperationException($"HTTP {(int)res.StatusCode}: {body}");

        var localSummary = LocalArtifactCleanup.CleanupTempAnalysisDirectories();
        localSummary = MergeCleanup(localSummary, LocalArtifactCleanup.CleanupSandboxJobArtifacts());

        return
            $"Limpeza concluída. Temp removido: {localSummary.TempDirectoriesRemoved}; " +
            $"jobs locais processados: {localSummary.SandboxJobDirectoriesProcessed}; " +
            $"ficheiros removidos: {localSummary.SandboxFilesRemoved}; " +
            $"espaço libertado (local): {FormatBytes(localSummary.BytesFreed)}.";
    }

    public async Task<string> RunArchiveAsync(int olderThanDays, CancellationToken cancellationToken = default)
    {
        using var client = CreateClient(TimeSpan.FromSeconds(120));
        var payload = JsonSerializer.Serialize(new { olderThanDays }, JsonCamelCase);
        using var content = new StringContent(payload, Encoding.UTF8, "application/json");
        var res = await client.PostAsync($"{AppConstants.ApiBaseUrl}/api/storage/archive", content, cancellationToken)
            .ConfigureAwait(false);
        var body = await res.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
        if (!res.IsSuccessStatusCode)
            throw new InvalidOperationException($"HTTP {(int)res.StatusCode}: {body}");

        return "Arquivo concluído.";
    }

    public async Task<string> RunFullPurgeAsync(CancellationToken cancellationToken = default)
    {
        long backendFreed = 0;
        try
        {
            using var client = CreateClient(TimeSpan.FromSeconds(120));
            var res = await client.PostAsync($"{AppConstants.ApiBaseUrl}/api/storage/purge", null, cancellationToken)
                .ConfigureAwait(false);
            var body = await res.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            if (res.IsSuccessStatusCode)
            {
                var purge = JsonSerializer.Deserialize<PurgeResponse>(body, JsonInsensitive);
                backendFreed = purge?.Result?.FreedBytes ?? 0;
            }
        }
        catch
        {
            /* backend opcional */
        }

        var localSummary = LocalArtifactCleanup.CleanupEverything();
        return
            $"Limpeza completa concluída. Temp removido: {localSummary.TempDirectoriesRemoved}; " +
            $"pastas de dados removidas: {localSummary.DataPathsRemoved}; " +
            $"espaço libertado (local): {FormatBytes(localSummary.BytesFreed)}; " +
            $"espaço libertado (backend): {FormatBytes(backendFreed)}.";
    }

    public static bool TryParseInt(string? text, int min, int max, out int value)
    {
        if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
            return value >= min && value <= max;
        return false;
    }

    private static HttpClient CreateClient(TimeSpan timeout)
    {
        var client = new HttpClient { Timeout = timeout };
        AppConstants.ApplyAdminToken(client);
        return client;
    }

    private static string FormatBytes(long bytes)
    {
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        double b = bytes;
        var idx = 0;
        while (b >= 1024 && idx < units.Length - 1)
        {
            b /= 1024;
            idx++;
        }
        return $"{b:0.##} {units[idx]}";
    }

    private static LocalArtifactCleanup.CleanupSummary MergeCleanup(
        LocalArtifactCleanup.CleanupSummary left,
        LocalArtifactCleanup.CleanupSummary right) =>
        new()
        {
            TempDirectoriesRemoved = left.TempDirectoriesRemoved + right.TempDirectoriesRemoved,
            SandboxJobDirectoriesProcessed = left.SandboxJobDirectoriesProcessed + right.SandboxJobDirectoriesProcessed,
            SandboxFilesRemoved = left.SandboxFilesRemoved + right.SandboxFilesRemoved,
            DataPathsRemoved = left.DataPathsRemoved + right.DataPathsRemoved,
            BytesFreed = left.BytesFreed + right.BytesFreed
        };

    private sealed class PurgeResponse
    {
        public PurgeResultObj Result { get; set; } = new();
    }

    private sealed class PurgeResultObj
    {
        public long FreedBytes { get; set; }
    }

    private sealed class EstimateResponse
    {
        public PathsObj Paths { get; set; } = new();
        public BytesObj Bytes { get; set; } = new();
    }

    private sealed class PathsObj
    {
        public string DataDir { get; set; } = "";
        public string SandboxJobsDir { get; set; } = "";
        public string ReportsDir { get; set; } = "";
        public string DecompiledDir { get; set; } = "";
    }

    private sealed class BytesObj
    {
        public long SandboxJobs { get; set; }
        public long Reports { get; set; }
        public long Decompiled { get; set; }
        public long PythonCache { get; set; }
        public long WpfBuild { get; set; }
        public long FrontendDist { get; set; }
        public long Total { get; set; }
    }
}

public sealed class StorageEstimateView
{
    public string EstimateText { get; init; } = "";
    public string PathsText { get; init; } = "";
}
