using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;
using RatAnalyzer.Desktop;

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
        try
        {
            await ProjectDependencyBootstrap.EnsureAndInstallAsync(
                msg => Dispatcher.Invoke(() => AddLog(msg)),
                CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Dispatcher.Invoke(() => AddLog($"[AVISO] Dependências: {ex.Message}"));
        }

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
                await StartBackendAsync(client, msg => Dispatcher.Invoke(() => AddLog(msg)));
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
        await EnsureFrontendRunningAsync(msg => Dispatcher.Invoke(() => AddLog(msg)));

        StatusText.Text = "Frontend pronto.";
        AddLog("[OK] Frontend pronto.");

        await Task.Delay(800);

        LoadingCompleted?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// Executa a sequência completa de arranque: verifica/inicia backend (porta 8000),
    /// verifica/inicia frontend (porta 8080). Usado pela LoadingView
    /// para que o WPF abra as portas ao iniciar. Ao fechar, ShutdownManager liberta-as.
    /// </summary>
    public static async Task RunFullStartupSequenceAsync(Action<string>? addLog = null)
    {
        void Log(string m) => addLog?.Invoke(m);
        try
        {
            await ProjectDependencyBootstrap.EnsureAndInstallAsync(Log, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Log($"[AVISO] Fase de dependências: {ex.Message}");
        }

        using var client = new HttpClient();
        // Paralelizar: backend e frontend são independentes (porta 8000 vs 8080).
        var backendTask = Task.Run(async () =>
        {
            addLog?.Invoke("[INFO] A verificar backend em http://localhost:8000 ...");
            var backendAlreadyRunning = await IsBackendUpAsync(client);
            if (!backendAlreadyRunning)
            {
                addLog?.Invoke("[INFO] Backend não encontrado. A iniciar servidor uvicorn...");
                await StartBackendAsync(client, addLog);
                addLog?.Invoke("[OK] Backend iniciado com sucesso em http://localhost:8000.");
            }
            else
            {
                addLog?.Invoke("[OK] Backend já se encontra em execução.");
            }
        });

        var frontendTask = Task.Run(async () =>
        {
            addLog?.Invoke("[INFO] A verificar dev server do frontend...");
            await EnsureFrontendRunningAsync(addLog);
            addLog?.Invoke("[OK] Frontend pronto.");
        });

        await Task.WhenAll(backendTask, frontendTask);
        // Não abrir automaticamente o browser no arranque.
        // A interface web deve ser aberta por ação explícita do utilizador (ex.: clicar em "Análise estática").
    }

    private static void OpenFrontendInBrowser(Action<string>? addLog)
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
            addLog?.Invoke("[ERRO] Não foi possível abrir automaticamente o navegador.");
            addLog?.Invoke(ex.Message);
        }
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

    /// <summary>
    /// Considera dependências NPM satisfeitas se existir vite em node_modules (necessário para npm run dev).
    /// Evita correr npm install em cada arranque.
    /// </summary>
    private static bool FrontendNodeModulesLooksComplete(string frontendDir)
    {
        var viteDir = Path.Combine(frontendDir, "node_modules", "vite");
        return Directory.Exists(viteDir);
    }

    /// <summary>
    /// Garante dependências pip do backend (requirements.txt). Se já instaladas, o pip sai rapidamente.
    /// </summary>
    internal static async Task EnsureBackendPythonDependenciesAsync(string backendDir, Action<string>? addLog)
    {
        var reqPath = Path.Combine(backendDir, "requirements.txt");
        if (!File.Exists(reqPath))
        {
            addLog?.Invoke("[AVISO] Ficheiro requirements.txt não encontrado na pasta backend; a saltar pip install.");
            return;
        }

        addLog?.Invoke("[INFO] A garantir dependências Python (pip)…");

        await Task.Run(async () =>
        {
            var psi = new ProcessStartInfo
            {
                FileName = "python",
                Arguments = "-m pip install -r requirements.txt --disable-pip-version-check -q",
                WorkingDirectory = backendDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            using var proc = Process.Start(psi);
            if (proc is null)
            {
                throw new InvalidOperationException("Não foi possível iniciar pip (python não encontrado?).");
            }

            var stdoutTask = proc.StandardOutput.ReadToEndAsync();
            var stderrTask = proc.StandardError.ReadToEndAsync();
            using (var killCts = new CancellationTokenSource(TimeSpan.FromMinutes(10)))
            {
                await proc.WaitForExitAsync(killCts.Token);
            }

            var stdout = await stdoutTask.ConfigureAwait(false);
            var stderr = await stderrTask.ConfigureAwait(false);

            if (proc.ExitCode != 0)
            {
                var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
                var trimmed = detail.Length > 2000 ? detail[..2000] + "…" : detail;
                throw new InvalidOperationException(
                    $"pip install falhou (código {proc.ExitCode}).\n{trimmed}");
            }
        });

        addLog?.Invoke("[OK] Dependências Python verificadas/instaladas.");
    }

    /// <summary>
    /// Corre npm install só se node_modules estiver incompleto (vite em falta).
    /// </summary>
    internal static async Task EnsureFrontendNpmDependenciesAsync(string frontendDir, Action<string>? addLog)
    {
        if (FrontendNodeModulesLooksComplete(frontendDir))
        {
            return;
        }

        addLog?.Invoke("[INFO] node_modules incompletos ou em falta. A executar npm install…");

        await Task.Run(async () =>
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = "/c npm install --no-fund --no-audit --loglevel=error",
                WorkingDirectory = frontendDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8
            };

            using var proc = Process.Start(psi);
            if (proc is null)
            {
                throw new InvalidOperationException(
                    "Não foi possível iniciar npm. Verifique se o Node.js está instalado e no PATH.");
            }

            var stdoutTask = proc.StandardOutput.ReadToEndAsync();
            var stderrTask = proc.StandardError.ReadToEndAsync();
            using (var killCts = new CancellationTokenSource(TimeSpan.FromMinutes(15)))
            {
                await proc.WaitForExitAsync(killCts.Token);
            }

            var stdout = await stdoutTask.ConfigureAwait(false);
            var stderr = await stderrTask.ConfigureAwait(false);

            if (proc.ExitCode != 0)
            {
                var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
                var trimmed = detail.Length > 2000 ? detail[..2000] + "…" : detail;
                throw new InvalidOperationException(
                    $"npm install falhou (código {proc.ExitCode}).\n{trimmed}");
            }
        });

        if (!FrontendNodeModulesLooksComplete(frontendDir))
        {
            throw new InvalidOperationException(
                "npm install concluíu mas vite não aparece em node_modules. Verifique package.json.");
        }

        addLog?.Invoke("[OK] Dependências npm instaladas.");
    }

    internal static async Task StartBackendAsync(HttpClient client, Action<string>? addLog = null)
    {
        var backendDir = FindBackendWorkingDirectory() ?? AppDomain.CurrentDomain.BaseDirectory;

        try
        {
            await EnsureBackendPythonDependenciesAsync(backendDir, addLog);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                "Não foi possível instalar/atualizar as dependências Python do backend.\n\n" +
                "Na pasta 'backend', execute manualmente:\n" +
                "python -m pip install -r requirements.txt\n\n" +
                ex.Message);
        }

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

            var javaHome = JavaDependencyHelper.ResolveJavaHomeForBackend();
            if (!string.IsNullOrWhiteSpace(javaHome))
            {
                psi.Environment["JAVA_HOME"] = javaHome;
                var binDir = Path.Combine(javaHome, "bin");
                var pathNow = Environment.GetEnvironmentVariable("PATH") ?? "";
                if (!string.Equals(pathNow, binDir, StringComparison.OrdinalIgnoreCase)
                    && !pathNow.StartsWith(binDir + Path.PathSeparator, StringComparison.OrdinalIgnoreCase))
                    psi.Environment["PATH"] = binDir + Path.PathSeparator + pathNow;
            }

            var ghidraHome = GhidraDependencyHelper.ResolveGhidraInstallDirForBackend();
            if (!string.IsNullOrWhiteSpace(ghidraHome))
                psi.Environment["GHIDRA_INSTALL_DIR"] = ghidraHome;

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

    internal static string? FindFrontendWorkingDirectory()
    {
        var backendDir = FindBackendWorkingDirectory();
        var projectRoot = backendDir != null ? Directory.GetParent(backendDir)?.FullName : null;
        if (!string.IsNullOrWhiteSpace(projectRoot))
        {
            var candidate = Path.Combine(projectRoot!, "frontend");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }
        }

        // Fallback: procurar "frontend" a partir da pasta do executável.
        var current = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
        for (var i = 0; i < 6 && current is not null; i++)
        {
            var candidate = Path.Combine(current.FullName, "frontend");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            current = current.Parent;
        }

        return null;
    }

    private static async Task EnsureFrontendRunningAsync(Action<string>? addLog = null)
    {
        if (await IsFrontendUpAsync())
        {
            return;
        }

        var frontendDir = FindFrontendWorkingDirectory();
        if (string.IsNullOrWhiteSpace(frontendDir))
        {
            throw new InvalidOperationException(
                "Não foi possível localizar a pasta 'frontend' para iniciar o frontend.\n\n" +
                "Certifique-se de que a estrutura do projeto é a esperada e, se necessário, inicie manualmente o dev server.");
        }

        try
        {
            await EnsureFrontendNpmDependenciesAsync(frontendDir, addLog);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                "Não foi possível instalar as dependências npm do frontend.\n\n" +
                "Na pasta 'frontend', execute manualmente:\n" +
                "npm install\n\n" +
                ex.Message);
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
                "Tente iniciar manualmente a partir da pasta 'frontend' com:\n" +
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
            "npm run dev (na pasta frontend)");
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
                _managedBackendProcess.Kill(entireProcessTree: true);
                _managedBackendProcess.WaitForExit(5000);
            }
        }
        catch { /* ignorar */ }
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
                _managedFrontendProcess.Kill(entireProcessTree: true);
                _managedFrontendProcess.WaitForExit(5000);
            }
        }
        catch { /* ignorar */ }
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
