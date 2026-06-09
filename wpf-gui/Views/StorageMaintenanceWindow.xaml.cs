using System;
using System.Globalization;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using RatAnalyzer.Desktop;

namespace RatAnalyzer.Desktop.Views;

public partial class StorageMaintenanceWindow : Window
{
    private const string ApiBaseUrl = "http://localhost:8000";

    public StorageMaintenanceWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await RefreshEstimateAsync();
    }

    private async Task RefreshEstimateAsync()
    {
        StatusText.Text = "A obter estimativa...";
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var json = await client.GetStringAsync($"{ApiBaseUrl}/api/storage/estimate");
            var resp = JsonSerializer.Deserialize<EstimateResponse>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
            if (resp == null)
            {
                StatusText.Text = "Resposta inesperada do backend ao pedir estimativa.";
                return;
            }

            var localEstimate = LocalArtifactCleanup.EstimateLocalArtifacts();
            EstimateText.Text =
                $"Total: {FormatBytes(resp.Bytes.Total)}\n" +
                $"- sandbox_jobs: {FormatBytes(resp.Bytes.SandboxJobs)}\n" +
                $"- reports: {FormatBytes(resp.Bytes.Reports)}\n" +
                $"- decompiled: {FormatBytes(resp.Bytes.Decompiled)}\n" +
                $"- python cache: {FormatBytes(resp.Bytes.PythonCache)}\n" +
                $"- wpf build (bin/obj): {FormatBytes(resp.Bytes.WpfBuild)}\n" +
                $"- frontend dist: {FormatBytes(resp.Bytes.FrontendDist)}\n" +
                $"- temp local de análise: {FormatBytes(localEstimate.TempAnalysisBytes)} ({localEstimate.TempAnalysisDirectories} pastas)";

            PathsText.Text =
                $"DataDir: {resp.Paths.DataDir}\n" +
                $"sandbox_jobs: {resp.Paths.SandboxJobsDir}\n" +
                $"reports: {resp.Paths.ReportsDir}\n" +
                $"decompiled: {resp.Paths.DecompiledDir}\n" +
                $"temp local: {localEstimate.TempPath}";

            StatusText.Text = "Estimativa atualizada.";
        }
        catch (Exception ex)
        {
            StatusText.Text = "Falha ao obter estimativa: " + ex.Message;
        }
    }

    private async void RefreshEstimateButton_Click(object sender, RoutedEventArgs e)
        => await RefreshEstimateAsync();

    private async void RunCleanupButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryParseInt(KeepMostRecentBox.Text, 1, 1000000, out var keepMostRecent) ||
            !TryParseInt(RetentionDaysBox.Text, 0, 36500, out var retentionDays))
        {
            MessageBox.Show("Valores inválidos (retenção/dias).", "Manutenção", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var confirm = MessageBox.Show(
            "Isto remove artefactos antigos em disco para jobs concluídos/falhados (mantém a base de dados), " +
            "apaga pastas temporárias de análise em %TEMP% e remove amostras .exe/.dll guardadas em sandbox_jobs.\n\nContinuar?",
            "Confirmar limpeza",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        if (confirm != MessageBoxResult.Yes)
            return;

        StatusText.Text = "A executar limpeza...";
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
            var payload = JsonSerializer.Serialize(new { retentionDays, keepMostRecent }, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            using var content = new StringContent(payload, Encoding.UTF8, "application/json");
            var res = await client.PostAsync($"{ApiBaseUrl}/api/storage/cleanup", content);
            var body = await res.Content.ReadAsStringAsync();
            if (!res.IsSuccessStatusCode)
                throw new InvalidOperationException($"HTTP {(int)res.StatusCode}: {body}");

            var localSummary = LocalArtifactCleanup.CleanupTempAnalysisDirectories();
            localSummary = MergeCleanup(localSummary, LocalArtifactCleanup.CleanupSandboxJobArtifacts());

            StatusText.Text =
                $"Limpeza concluída. Temp removido: {localSummary.TempDirectoriesRemoved}; " +
                $"jobs locais processados: {localSummary.SandboxJobDirectoriesProcessed}; " +
                $"ficheiros removidos: {localSummary.SandboxFilesRemoved}; " +
                $"espaço libertado (local): {FormatBytes(localSummary.BytesFreed)}.";
            await RefreshEstimateAsync();
        }
        catch (Exception ex)
        {
            StatusText.Text = "Falha na limpeza: " + ex.Message;
        }
    }

    private async void RunArchiveButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryParseInt(ArchiveDaysBox.Text, 1, 36500, out var olderThanDays))
        {
            MessageBox.Show("Valor inválido (dias para arquivo).", "Manutenção", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var confirm = MessageBox.Show(
            "Isto vai zipar out/ (out.zip) para jobs antigos e remover a pasta out/ original.\n\nContinuar?",
            "Confirmar arquivo frio",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        if (confirm != MessageBoxResult.Yes)
            return;

        StatusText.Text = "A arquivar jobs antigos...";
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(120) };
            var payload = JsonSerializer.Serialize(new { olderThanDays }, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            using var content = new StringContent(payload, Encoding.UTF8, "application/json");
            var res = await client.PostAsync($"{ApiBaseUrl}/api/storage/archive", content);
            var body = await res.Content.ReadAsStringAsync();
            if (!res.IsSuccessStatusCode)
                throw new InvalidOperationException($"HTTP {(int)res.StatusCode}: {body}");

            StatusText.Text = "Arquivo concluído.";
            await RefreshEstimateAsync();
        }
        catch (Exception ex)
        {
            StatusText.Text = "Falha no arquivo: " + ex.Message;
        }
    }

    private async void RunFullPurgeButton_Click(object sender, RoutedEventArgs e)
    {
        var confirm = MessageBox.Show(
            "Isto vai eliminar todo o histórico local de análises, amostras guardadas, relatórios, " +
            "descompilados, pastas temporárias de análise em %TEMP% e os dados em %LOCALAPPDATA%\\RatAnalyzer " +
            "(mantém a pasta Ghidra, se existir).\n\n" +
            "A ação é irreversível. Continuar?",
            "Confirmar limpeza completa",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);
        if (confirm != MessageBoxResult.Yes)
            return;

        SetMaintenanceActionsEnabled(false);
        StatusText.Text = "A executar limpeza completa...";
        try
        {
            long backendFreed = 0;
            try
            {
                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(120) };
                var res = await client.PostAsync($"{ApiBaseUrl}/api/storage/purge", null);
                var body = await res.Content.ReadAsStringAsync();
                if (res.IsSuccessStatusCode)
                {
                    var purge = JsonSerializer.Deserialize<PurgeResponse>(body, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });
                    backendFreed = purge?.Result?.FreedBytes ?? 0;
                }
            }
            catch { /* ignorar */ }

            var localSummary = LocalArtifactCleanup.CleanupEverything();
            StatusText.Text =
                $"Limpeza completa concluída. Temp removido: {localSummary.TempDirectoriesRemoved}; " +
                $"pastas de dados removidas: {localSummary.DataPathsRemoved}; " +
                $"espaço libertado (local): {FormatBytes(localSummary.BytesFreed)}; " +
                $"espaço libertado (backend): {FormatBytes(backendFreed)}.";
            await RefreshEstimateAsync();
        }
        catch (Exception ex)
        {
            StatusText.Text = "Falha na limpeza completa: " + ex.Message;
        }
        finally
        {
            SetMaintenanceActionsEnabled(true);
        }
    }

    private void SetMaintenanceActionsEnabled(bool enabled)
    {
        RefreshEstimateButton.IsEnabled = enabled;
        RunCleanupButton.IsEnabled = enabled;
        RunArchiveButton.IsEnabled = enabled;
        RunFullPurgeButton.IsEnabled = enabled;
    }

    private static bool TryParseInt(string? text, int min, int max, out int value)
    {
        if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
            return value >= min && value <= max;
        return false;
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
        LocalArtifactCleanup.CleanupSummary right)
    {
        return new LocalArtifactCleanup.CleanupSummary
        {
            TempDirectoriesRemoved = left.TempDirectoriesRemoved + right.TempDirectoriesRemoved,
            SandboxJobDirectoriesProcessed = left.SandboxJobDirectoriesProcessed + right.SandboxJobDirectoriesProcessed,
            SandboxFilesRemoved = left.SandboxFilesRemoved + right.SandboxFilesRemoved,
            DataPathsRemoved = left.DataPathsRemoved + right.DataPathsRemoved,
            BytesFreed = left.BytesFreed + right.BytesFreed
        };
    }

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

    private void CloseButton_Click(object sender, RoutedEventArgs e)
        => Close();
}
