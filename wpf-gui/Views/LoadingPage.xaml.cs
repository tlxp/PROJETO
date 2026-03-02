using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;

namespace RatAnalyzer.Desktop.Views;

public partial class LoadingPage : Page
{
    public event EventHandler? LoadingCompleted;

    private readonly ObservableCollection<string> _logs = new();

    private const string ApiBaseUrl = "http://localhost:8000";
    private const string FrontendUrl = "http://localhost:8080";

    // Backend uvicorn gerido pelo WPF (quando arrancado automaticamente).
    private static Process? _managedBackendProcess;
    // Dev server do frontend (npm run dev) gerido pelo WPF.
    private static Process? _managedFrontendProcess;

    public LoadingPage()
    {
        InitializeComponent();

        LogsList.ItemsSource = _logs;
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (FindResource("SpinnerStoryboard") is Storyboard storyboard)
        {
            storyboard.Begin();
        }

        _ = RunStartupSequenceAsync();
    }

    private async Task RunStartupSequenceAsync()
    {
        using var client = new HttpClient();

        AddLog("[INFO] A verificar backend em http://localhost:8000 ...");
        StatusText.Text = "A verificar backend...";

        var backendAlreadyRunning = await IsBackendUpAsync(client);
        if (!backendAlreadyRunning)
        {
            AddLog("[INFO] Backend não encontrado. A iniciar servidor uvicorn...");
            StatusText.Text = "A iniciar servidor backend (uvicorn)...";

            try
            {
                await StartBackendAsync(client);
                AddLog("[OK] Backend iniciado com sucesso em http://localhost:8000.");
            }
            catch (Exception ex)
            {
                AddLog("[ERRO] Falha ao iniciar backend automaticamente.");
                AddLog(ex.Message);
                StatusText.Text = "Falha ao iniciar backend.";

                MessageBox.Show(
                    "Não foi possível iniciar automaticamente o backend Python.\n\n" +
                    "Por favor inicie manualmente, na pasta 'backend', com:\n\n" +
                    "uvicorn api:app --reload --host 0.0.0.0 --port 8000",
                    "Erro ao iniciar backend",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);

                await Task.Delay(1200);
                LoadingCompleted?.Invoke(this, EventArgs.Empty);
                return;
            }
        }
        else
        {
            AddLog("[OK] Backend já se encontra em execução.");
        }

        StatusText.Text = "Backend pronto. A iniciar frontend...";

        AddLog("[INFO] A verificar dev server do frontend...");
        await EnsureFrontendRunningAsync();

        StatusText.Text = "Frontend pronto. A abrir interface web...";

        AddLog($"[INFO] A abrir frontend em {FrontendUrl} ...");
        TryOpenFrontend();

        await Task.Delay(800);

        LoadingCompleted?.Invoke(this, EventArgs.Empty);
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

    internal static string? FindBackendWorkingDirectory()
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

    internal static async Task StartBackendAsync(HttpClient client)
    {
        var backendDir = FindBackendWorkingDirectory() ?? AppDomain.CurrentDomain.BaseDirectory;

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "python",
                // Sem --reload para evitar processos filhos difíceis de matar;
                // o WPF gere o ciclo de vida completo.
                Arguments = "-m uvicorn api:app --host 0.0.0.0 --port 8000",
                WorkingDirectory = backendDir,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            // Guardamos o processo para o podermos terminar quando o WPF fechar.
            _managedBackendProcess = Process.Start(psi);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                "Não foi possível iniciar automaticamente o servidor backend (uvicorn).\n\n" +
                "Tente iniciar manualmente a partir da pasta 'backend' com:\n" +
                "uvicorn api:app --reload --host 0.0.0.0 --port 8000\n\n" +
                ex.Message);
        }

        var attempts = 0;
        const int maxAttempts = 30;

        while (attempts < maxAttempts)
        {
            attempts++;
            await Task.Delay(1000);

            if (await IsBackendUpAsync(client))
            {
                return;
            }
        }

        throw new TimeoutException(
            "Não foi possível confirmar o arranque do servidor backend em http://localhost:8000.\n\n" +
            "Verifique se o Python e o uvicorn estão instalados e, se necessário, inicie manualmente:\n" +
            "uvicorn api:app --reload --host 0.0.0.0 --port 8000");
    }

    private static string? FindFrontendWorkingDirectory()
    {
        var backendDir = FindBackendWorkingDirectory();
        var projectRoot = backendDir != null ? Directory.GetParent(backendDir)?.FullName : null;
        if (!string.IsNullOrWhiteSpace(projectRoot))
        {
            var candidate = Path.Combine(projectRoot!, "drop-n-analyze");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        // Fallback: procurar "drop-n-analyze" a partir da pasta do executável.
        var current = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
        for (var i = 0; i < 6 && current is not null; i++)
        {
            var candidate = Path.Combine(current.FullName, "drop-n-analyze");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            current = current.Parent;
        }

        return null;
    }

    private static async Task EnsureFrontendRunningAsync()
    {
        if (await IsFrontendUpAsync())
        {
            return;
        }

        var frontendDir = FindFrontendWorkingDirectory();
        if (string.IsNullOrWhiteSpace(frontendDir))
        {
            throw new InvalidOperationException(
                "Não foi possível localizar a pasta 'drop-n-analyze' para iniciar o frontend.\n\n" +
                "Certifique-se de que a estrutura do projeto é a esperada e, se necessário, inicie manualmente o dev server.");
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c npm run dev",
                WorkingDirectory = frontendDir,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            _managedFrontendProcess = Process.Start(psi);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                "Não foi possível iniciar automaticamente o dev server do frontend (npm run dev).\n\n" +
                "Tente iniciar manualmente a partir da pasta 'drop-n-analyze' com:\n" +
                "npm run dev\n\n" +
                ex.Message);
        }

        // Esperar alguns segundos até o servidor responder na porta configurada (8080).
        var attempts = 0;
        const int maxAttempts = 30;

        while (attempts < maxAttempts)
        {
            attempts++;
            await Task.Delay(1000);

            if (await IsFrontendUpAsync())
            {
                return;
            }
        }

        throw new TimeoutException(
            "Não foi possível confirmar o arranque do frontend em http://localhost:8080.\n\n" +
            "Verifique se o Node/npm estão instalados e, se necessário, inicie manualmente o dev server:\n" +
            "npm run dev (na pasta drop-n-analyze)");
    }

    private static async Task<bool> IsFrontendUpAsync()
    {
        try
        {
            using var client = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(2)
            };

            var response = await client.GetAsync(FrontendUrl);
            return response.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    internal static void StopManagedBackend()
    {
        try
        {
            if (_managedBackendProcess is { HasExited: false })
            {
                _managedBackendProcess.Kill(true);
            }
        }
        catch
        {
            // Ignorar falhas ao terminar o backend; o objetivo é apenas limpar o ambiente.
        }
        finally
        {
            _managedBackendProcess?.Dispose();
            _managedBackendProcess = null;
        }
    }

    internal static void StopManagedFrontend()
    {
        try
        {
            if (_managedFrontendProcess is { HasExited: false })
            {
                _managedFrontendProcess.Kill(true);
            }
        }
        catch
        {
            // Ignorar falhas ao terminar o frontend; o objetivo é apenas libertar a porta.
        }
        finally
        {
            _managedFrontendProcess?.Dispose();
            _managedFrontendProcess = null;
        }
    }

    private void TryOpenFrontend()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = FrontendUrl,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            AddLog("[ERRO] Não foi possível abrir automaticamente o navegador.");
            AddLog(ex.Message);
        }
    }

    private void AddLog(string message)
    {
        _logs.Add(message);
    }
}
