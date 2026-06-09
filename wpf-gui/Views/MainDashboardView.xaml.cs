using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Principal;
using System.Text;
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
    private string? _lastStaticJobId;
    private string? _lastStaticJobUrl;

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

    private void SelectFileButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Selecionar ficheiro para análise",
            Filter = "Executáveis e ficheiros|*.exe;*.dll;*.zip|Todos os ficheiros (*.*)|*.*",
            FilterIndex = 1
        };
        if (dialog.ShowDialog() == true && !string.IsNullOrWhiteSpace(dialog.FileName))
        {
            _selectedFilePath = dialog.FileName;
            ShowOptions = true;
        }
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
        StaticAnalysisJobIdText.Visibility = Visibility.Collapsed;
        StaticAnalysisJobUrlText.Visibility = Visibility.Collapsed;
        OpenResultsButton.Visibility = Visibility.Collapsed;

        try
        {
            var jobId = await RunStaticAnalysisJobAsync(_selectedFilePath);

            StaticAnalysisStatusText.Text = "Análise estática concluída. A abrir resultados no navegador...";
            StaticAnalysisProgressBar.IsIndeterminate = false;
            StaticAnalysisProgressBar.Value = 100;

            _lastStaticJobId = jobId;
            _lastStaticJobUrl = $"{FrontendUrl}/resultados?jobId={Uri.EscapeDataString(jobId)}";
            StaticAnalysisJobIdText.Text = $"Job ID: {jobId}";
            StaticAnalysisJobUrlText.Text = _lastStaticJobUrl;
            StaticAnalysisJobIdText.Visibility = Visibility.Visible;
            StaticAnalysisJobUrlText.Visibility = Visibility.Visible;
            OpenResultsButton.Visibility = Visibility.Visible;

            try
            {
                OpenResultsInBrowser();
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

        // 1) Enviar o ficheiro para /api/analyze (análise estática síncrona, como o frontend).
        StaticAnalysisStatusText.Text = "A enviar ficheiro para análise estática...";

        using var form = new MultipartFormDataContent();
        await using var stream = File.OpenRead(filePath);
        var fileContent = new StreamContent(stream);
        form.Add(fileContent, "file", Path.GetFileName(filePath));

        HttpResponseMessage analyzeResponse;
        try
        {
            analyzeResponse = await client.PostAsync($"{ApiBaseUrl}/api/analyze", form);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                $"Não foi possível contactar o backend em {ApiBaseUrl}, mesmo depois de tentar arrancar o servidor.\n\n" +
                "Tente iniciar manualmente a partir da pasta 'backend' com:\n" +
                "uvicorn api:app --reload --host 0.0.0.0 --port 8000");
        }

        if (!analyzeResponse.IsSuccessStatusCode)
        {
            var body = await analyzeResponse.Content.ReadAsStringAsync();
            throw new InvalidOperationException(
                $"Falha ao executar análise estática (HTTP {(int)analyzeResponse.StatusCode}).\n\n{body}");
        }

        var analyzeJson = await analyzeResponse.Content.ReadAsStringAsync();
        var analyze = JsonSerializer.Deserialize<AnalyzeResponse>(analyzeJson, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });

        if (analyze is null)
        {
            throw new InvalidOperationException("Resposta inesperada do backend ao executar a análise estática.");
        }

        // 2) Publicar o resultado no backend via /api/analysis/upload_static para obter um jobId
        //    compatível com /resultados?jobId=... no frontend.
        StaticAnalysisStatusText.Text = "A publicar resultados no backend...";

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

        // O backend FastAPI espera campos em camelCase (fileName, report, cCode, ilCode, ...).
        // Configuramos o serializer para gerar JSON em camelCase para alinhar com o modelo StaticAnalysisUpload.
        var serializeOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
        var jsonPayload = JsonSerializer.Serialize(uploadPayload, serializeOptions);
        using var uploadContent = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

        HttpResponseMessage uploadResponse;
        try
        {
            uploadResponse = await client.PostAsync($"{ApiBaseUrl}/api/analysis/upload_static", uploadContent);
        }
        catch (HttpRequestException)
        {
            throw new InvalidOperationException(
                "Não foi possível publicar o resultado da análise estática no backend.");
        }

        if (!uploadResponse.IsSuccessStatusCode)
        {
            var body = await uploadResponse.Content.ReadAsStringAsync();
            throw new InvalidOperationException(
                $"Falha ao registar resultado estático no backend (HTTP {(int)uploadResponse.StatusCode}).\n\n{body}");
        }

        var uploadJson = await uploadResponse.Content.ReadAsStringAsync();
        var submit = JsonSerializer.Deserialize<SubmitResponse>(uploadJson, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });

        if (submit is null || string.IsNullOrWhiteSpace(submit.JobId))
        {
            throw new InvalidOperationException("Resposta inesperada ao publicar o resultado estático (jobId em falta).");
        }

        StaticAnalysisStatusText.Text = "Análise estática concluída e registada no backend.";
        StaticAnalysisProgressBar.IsIndeterminate = false;
        StaticAnalysisProgressBar.Value = 100;

        return submit.JobId;
    }

    private void OpenResultsInBrowser()
    {
        if (string.IsNullOrWhiteSpace(_lastStaticJobUrl))
        {
            MessageBox.Show(
                "Ainda não existe nenhum job de análise concluído para abrir no navegador.",
                "RAT Analyzer",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = _lastStaticJobUrl,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Não foi possível abrir a página de resultados no navegador.\n\n{ex.Message}",
                "RAT Analyzer",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private void OpenResultsButton_Click(object sender, RoutedEventArgs e)
    {
        OpenResultsInBrowser();
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

        if (!File.Exists(_selectedFilePath))
        {
            MessageBox.Show("O ficheiro selecionado já não existe no disco.", "RAT Analyzer", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (!IsRunningAsAdministrator())
        {
            MessageBox.Show(
                "A análise comportamental em VM requer direitos de administrador (Hyper-V e scripts PowerShell).\n\n" +
                "Feche esta aplicação e execute-a como Administrador:\n" +
                "• Clique direito em RatAnalyzer.Desktop.exe → \"Executar como administrador\"\n" +
                "• Ou abra o PowerShell como Administrador e execute: dotnet run",
                "Elevação necessária",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        var runFirstTimeSetup = FirstTimeVmCheckBox?.IsChecked == true;
        var vmWindow = new VmAnalysisWindow(_selectedFilePath, runFirstTimeSetup)
        {
            Owner = Window.GetWindow(this)
        };
        vmWindow.Show();
    }

    private void StorageMaintenanceButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var w = new StorageMaintenanceWindow
            {
                Owner = Window.GetWindow(this)
            };
            w.ShowDialog();
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"Não foi possível abrir a janela de manutenção.\n\n{ex.Message}",
                "RAT Analyzer",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
    }

    private static bool IsRunningAsAdministrator()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    private sealed class SubmitResponse
    {
        public string? JobId { get; set; }
        public string? AnalysisType { get; set; }
        public string? Status { get; set; }
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