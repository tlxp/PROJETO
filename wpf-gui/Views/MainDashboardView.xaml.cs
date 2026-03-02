using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

namespace RatAnalyzer.Desktop.Views;

public partial class MainDashboardView : UserControl
{
    public static readonly DependencyProperty ShowOptionsProperty =
        DependencyProperty.Register(nameof(ShowOptions), typeof(bool), typeof(MainDashboardView), new PropertyMetadata(false));

    private const string ApiBaseUrl = "http://localhost:8000";
    private const string FrontendUrl = "http://localhost:8080";

    public bool ShowOptions
    {
        get => (bool)GetValue(ShowOptionsProperty);
        set => SetValue(ShowOptionsProperty, value);
    }

    private string? _selectedFilePath;

    public MainDashboardView()
    {
        InitializeComponent();
    }

    private void FileDropArea_Drop(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            return;
        }

        if (e.Data.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0)
        {
            return;
        }

        _selectedFilePath = files[0];
        ShowOptions = true;
    }

    private async void StaticAnalysis_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            MessageBox.Show("Nenhum ficheiro selecionado.", "RAT Analyzer", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        StaticAnalysisButton.IsEnabled = false;
        DynamicAnalysisButton.IsEnabled = false;
        StaticAnalysisStatusText.Visibility = Visibility.Visible;
        StaticAnalysisStatusText.Text = "A preparar ambiente de análise estática...";
        StaticAnalysisProgressBar.Visibility = Visibility.Visible;
        StaticAnalysisProgressBar.IsIndeterminate = true;
        StaticAnalysisProgressBar.Value = 0;

        try
        {
            var jobId = await RunStaticAnalysisJobAsync(_selectedFilePath);

            StaticAnalysisStatusText.Text = "Análise estática concluída. A abrir resultados no navegador...";
            StaticAnalysisProgressBar.IsIndeterminate = false;
            StaticAnalysisProgressBar.Value = 100;

            try
            {
                var url = $"{FrontendUrl}/resultados?jobId={Uri.EscapeDataString(jobId)}";
                Process.Start(new ProcessStartInfo
                {
                    FileName = url,
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    $"Análise concluída, mas não foi possível abrir o navegador automaticamente.\n\n{ex.Message}",
                    "RAT Analyzer",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }
        catch (Exception ex)
        {
            StaticAnalysisStatusText.Text = "Falha na análise estática.";
            StaticAnalysisProgressBar.IsIndeterminate = false;
            StaticAnalysisProgressBar.Value = 0;

            MessageBox.Show(
                ex.Message,
                "Erro na análise estática",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
        finally
        {
            StaticAnalysisButton.IsEnabled = true;
            DynamicAnalysisButton.IsEnabled = true;
        }
    }

    private async Task<string> RunStaticAnalysisJobAsync(string filePath)
    {
        if (!File.Exists(filePath))
        {
            throw new InvalidOperationException("O ficheiro selecionado já não existe no disco.");
        }

        using var client = new HttpClient
        {
            // Análises podem demorar bem mais que 100s; não queremos cancelar pelo timeout default.
            Timeout = Timeout.InfiniteTimeSpan
        };

        // Garante que o backend (uvicorn) está a correr antes de submeter o pedido.
        await EnsureBackendRunningAsync(client);

        StaticAnalysisStatusText.Text = "A submeter job de análise estática...";

        using var form = new MultipartFormDataContent();
        await using var stream = File.OpenRead(filePath);
        var fileContent = new StreamContent(stream);
        form.Add(fileContent, "file", Path.GetFileName(filePath));

        HttpResponseMessage submitResponse;
        try
        {
            submitResponse = await client.PostAsync($"{ApiBaseUrl}/api/analysis?analysis_type=static", form);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                $"Não foi possível contactar o backend em {ApiBaseUrl}, mesmo depois de tentar arrancar o servidor.\n\n" +
                "Tente iniciar manualmente a partir da pasta 'backend' com:\n" +
                "uvicorn api:app --reload --host 0.0.0.0 --port 8000");
        }

        if (!submitResponse.IsSuccessStatusCode)
        {
            var body = await submitResponse.Content.ReadAsStringAsync();
            throw new InvalidOperationException(
                $"Falha ao submeter análise estática (HTTP {(int)submitResponse.StatusCode}).\n\n{body}");
        }

        var json = await submitResponse.Content.ReadAsStringAsync();
        var submit = JsonSerializer.Deserialize<SubmitResponse>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });

        if (submit is null || string.IsNullOrWhiteSpace(submit.JobId))
        {
            throw new InvalidOperationException("Resposta inesperada ao submeter a análise estática (jobId em falta).");
        }

        var jobId = submit.JobId;
        var jobSubmittedAt = DateTime.UtcNow;
        // Tempo mínimo em segundos antes de aceitar "completed" e abrir o browser (evita "scan instantâneo" e dá tempo ao backend persistir).
        const int minAnalysisSeconds = 3;

        // Atualiza estado visível para o utilizador com o ID do job.
        StaticAnalysisStatusText.Text = $"Job de análise criado ({jobId[..8]}...). A aguardar início...";
        StaticAnalysisProgressBar.IsIndeterminate = true;
        StaticAnalysisProgressBar.Value = 15;

        var attempts = 0;
        // ~30 minutos de espera máxima (1 s por tentativa)
        const int maxAttempts = 1800;

        while (attempts < maxAttempts)
        {
            attempts++;
            await Task.Delay(1000);

            HttpResponseMessage statusResponse;
            try
            {
                statusResponse = await client.GetAsync($"{ApiBaseUrl}/api/analysis/{jobId}");
            }
            catch (HttpRequestException)
            {
                throw new InvalidOperationException(
                    "Perdeu-se a ligação ao backend durante o acompanhamento da análise.");
            }

            if (!statusResponse.IsSuccessStatusCode)
            {
                if (statusResponse.StatusCode == System.Net.HttpStatusCode.NotFound)
                {
                    throw new InvalidOperationException("Job de análise não encontrado no backend.");
                }

                var errorBody = await statusResponse.Content.ReadAsStringAsync();
                throw new InvalidOperationException(
                    $"Falha ao obter estado da análise (HTTP {(int)statusResponse.StatusCode}).\n\n{errorBody}");
            }

            var statusJson = await statusResponse.Content.ReadAsStringAsync();
            var jobStatus = JsonSerializer.Deserialize<JobStatusPayload>(statusJson, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (jobStatus is null || string.IsNullOrWhiteSpace(jobStatus.Status))
            {
                StaticAnalysisStatusText.Text = "A aguardar resposta do backend...";
                continue;
            }

            var status = jobStatus.Status;
            if (string.Equals(status, "queued", StringComparison.OrdinalIgnoreCase))
            {
                StaticAnalysisStatusText.Text = $"Análise estática em fila no backend... (espera {attempts}s)";
                StaticAnalysisProgressBar.IsIndeterminate = true;
                StaticAnalysisProgressBar.Value = 25;
            }
            else if (string.Equals(status, "running", StringComparison.OrdinalIgnoreCase))
            {
                // Quando entra em running, passamos a barra para modo determinado e avançamos suavemente até ~90%.
                StaticAnalysisProgressBar.IsIndeterminate = false;
                var fraction = Math.Min(1.0, attempts / (double)maxAttempts);
                var value = 30 + fraction * 60; // 30% -> 90%
                StaticAnalysisProgressBar.Value = value;
                StaticAnalysisStatusText.Text = $"A executar análise estática... ({attempts}s decorridos)";
            }
            else if (string.Equals(status, "completed", StringComparison.OrdinalIgnoreCase))
            {
                var elapsedSec = (DateTime.UtcNow - jobSubmittedAt).TotalSeconds;
                var remaining = minAnalysisSeconds - elapsedSec;
                if (remaining > 0)
                {
                    StaticAnalysisStatusText.Text = "Análise concluída no backend. A guardar resultados...";
                    await Task.Delay(TimeSpan.FromSeconds(remaining));
                }
                StaticAnalysisStatusText.Text = "Análise estática concluída no backend.";
                StaticAnalysisProgressBar.IsIndeterminate = false;
                StaticAnalysisProgressBar.Value = 100;
                return jobId;
            }
            else if (string.Equals(status, "failed", StringComparison.OrdinalIgnoreCase))
            {
                var errorMessage = string.IsNullOrWhiteSpace(jobStatus.Error)
                    ? "A análise estática falhou no backend."
                    : $"A análise estática falhou: {jobStatus.Error}";
                StaticAnalysisStatusText.Text = "Análise estática falhou.";
                StaticAnalysisProgressBar.IsIndeterminate = false;
                StaticAnalysisProgressBar.Value = 0;
                throw new InvalidOperationException(errorMessage);
            }
            else
            {
                StaticAnalysisStatusText.Text = $"Estado desconhecido da análise: {status}";
            }
        }

        StaticAnalysisProgressBar.IsIndeterminate = false;
        StaticAnalysisProgressBar.Value = 0;
        throw new TimeoutException("Timeout ao aguardar a conclusão da análise estática.");
    }

    private static async Task<bool> IsBackendUpAsync(HttpClient client)
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            var response = await client.GetAsync($"{ApiBaseUrl}/api/health", cts.Token);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    private static string? FindBackendWorkingDirectory()
    {
        var current = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
        for (var i = 0; i < 6 && current is not null; i++)
        {
            var candidate = Path.Combine(current.FullName, "backend");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            current = current.Parent;
        }

        return null;
    }

    private async Task EnsureBackendRunningAsync(HttpClient client)
    {
        if (await IsBackendUpAsync(client))
        {
            return;
        }

        StaticAnalysisStatusText.Text = "A iniciar servidor backend (uvicorn)...";

        var backendDir = FindBackendWorkingDirectory() ?? AppDomain.CurrentDomain.BaseDirectory;

        // Reutiliza a mesma lógica de arranque usada no ecrã de loading,
        // garantindo que o backend é gerido de forma centralizada.
        await LoadingPage.StartBackendAsync(client);
    }

    private void DynamicAnalysis_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_selectedFilePath))
        {
            MessageBox.Show("Nenhum ficheiro selecionado.", "RAT Analyzer", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        MessageBox.Show(
            $"(Placeholder)\n\nIria ser iniciada a ANÁLISE COMPORTAMENTAL/DINÂMICA em VM para:\n{_selectedFilePath}",
            "Behavioral Analysis",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private sealed class SubmitResponse
    {
        public string? JobId { get; set; }
        public string? AnalysisType { get; set; }
        public string? Status { get; set; }
    }

    private sealed class JobStatusPayload
    {
        public string? Status { get; set; }
        public string? Error { get; set; }
    }
}