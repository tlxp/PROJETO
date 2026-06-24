// --- Módulo: StartupSequence ---
// --- Sequência de arranque: backend (uvicorn:8000) e frontend (npm:8080) ---
// *Processos geridos ficam registados para o ShutdownManager terminar ao fechar*

using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using RatAnalyzer.Desktop.Helpers;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;

namespace RatAnalyzer.Desktop.Bootstrap;

public static class StartupSequence
{
    private const string ApiBaseUrl = AppConstants.ApiBaseUrl;
    private const string FrontendUrl = AppConstants.FrontendUrl;

    // Backend uvicorn gerido pelo WPF (quando arrancado automaticamente).
    private static Process? _managedBackendProcess;
    // Dev server do frontend (npm run dev) gerido pelo WPF.
    private static Process? _managedFrontendProcess;

    // --- Executa arranque completo (backend + frontend em paralelo) ---
    public static async Task RunFullStartupSequenceAsync(Action<string>? addLog = null)
    {
        void Log(string m) => addLog?.Invoke(m);
        try
        {
            await ProjectDependencyBootstrap.EnsureAndInstallAsync(Log, CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Log(LocalizationManager.Format(LocKeys.LogDepsPhaseWarning, ex.Message));
        }

        using var client = new HttpClient();
        // Paralelizar: backend e frontend são independentes (porta 8000 vs 8080).
        var backendTask = Task.Run(async () =>
        {
            addLog?.Invoke(LocalizationManager.Get(LocKeys.LogBackendChecking));
            var backendAlreadyRunning = await IsBackendUpAsync(client);
            if (!backendAlreadyRunning)
            {
                addLog?.Invoke(LocalizationManager.Get(LocKeys.LogBackendStarting));
                await StartBackendAsync(client, addLog);
                addLog?.Invoke(LocalizationManager.Get(LocKeys.LogBackendStarted));
            }
            else
            {
                addLog?.Invoke(LocalizationManager.Get(LocKeys.LogBackendAlreadyRunning));
            }
        });

        var frontendTask = Task.Run(async () =>
        {
            addLog?.Invoke(LocalizationManager.Get(LocKeys.LogFrontendChecking));
            await EnsureFrontendRunningAsync(addLog);
            addLog?.Invoke(LocalizationManager.Get(LocKeys.LogFrontendReady));
        });

        await Task.WhenAll(backendTask, frontendTask);
        // Não abrir automaticamente o browser no arranque.
        // A interface web deve ser aberta por ação explícita do utilizador (ex.: clicar em "Análise estática").
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

    // --- Verifica se node_modules tem vite (evita npm install em cada arranque) ---
    private static bool FrontendNodeModulesLooksComplete(string frontendDir)
    {
        var viteDir = Path.Combine(frontendDir, "node_modules", "vite");
        return Directory.Exists(viteDir);
    }

    // --- Garante dependências pip do backend (requirements.lock preferido) ---
    internal static async Task EnsureBackendPythonDependenciesAsync(string backendDir, Action<string>? addLog)
    {
        var lockPath = Path.Combine(backendDir, "requirements.lock");
        var reqPath = Path.Combine(backendDir, "requirements.txt");
        string pipArgs;
        if (File.Exists(lockPath))
        {
            pipArgs = "-m pip install --require-hashes -r requirements.lock --disable-pip-version-check -q";
        }
        else if (File.Exists(reqPath))
        {
            addLog?.Invoke(LocalizationManager.Get(LocKeys.LogReqLockMissing));
            pipArgs = "-m pip install -r requirements.txt --disable-pip-version-check -q";
        }
        else
        {
            addLog?.Invoke(LocalizationManager.Get(LocKeys.LogReqFilesMissing));
            return;
        }

        addLog?.Invoke(LocalizationManager.Get(LocKeys.LogPipEnsure));

        await Task.Run(async () =>
        {
            var psi = new ProcessStartInfo
            {
                FileName = "python",
                Arguments = pipArgs,
                WorkingDirectory = backendDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            ProcessOutputEncoding.ApplyUtf8(psi);
            ProcessOutputEncoding.ApplyPythonUtf8Environment(psi);

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
                var detail = ProcessOutputEncoding.NormalizeForDisplay(
                    string.IsNullOrWhiteSpace(stderr) ? stdout : stderr);
                var trimmed = detail.Length > 2000 ? detail[..2000] + "…" : detail;
                throw new InvalidOperationException(
                    $"pip install falhou (código {proc.ExitCode}).\n{trimmed}");
            }
        });

        addLog?.Invoke(LocalizationManager.Get(LocKeys.LogPipOk));
    }

    // --- Corre npm install só se node_modules estiver incompleto ---
    internal static async Task EnsureFrontendNpmDependenciesAsync(string frontendDir, Action<string>? addLog)
    {
        if (FrontendNodeModulesLooksComplete(frontendDir))
        {
            return;
        }

        addLog?.Invoke(LocalizationManager.Get(LocKeys.LogNpmInstall));

        await Task.Run(async () =>
        {
            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = ProcessOutputEncoding.CmdUtf8Command("npm install --no-fund --no-audit --loglevel=error"),
                WorkingDirectory = frontendDir,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            ProcessOutputEncoding.ApplyUtf8(psi);

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
                var detail = ProcessOutputEncoding.NormalizeForDisplay(
                    string.IsNullOrWhiteSpace(stderr) ? stdout : stderr);
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

        addLog?.Invoke(LocalizationManager.Get(LocKeys.LogNpmOk));
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
                "python -m pip install --require-hashes -r requirements.lock\n\n" +
                ex.Message);
        }

        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = "python",
                // Sem --reload para evitar processos filhos difíceis de matar;
                // o WPF gere o ciclo de vida completo.
                Arguments = "-m uvicorn api:app --host 127.0.0.1 --port 8000",
                WorkingDirectory = backendDir,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            InheritParentEnvironment(psi);
            PropagateBackendSecrets(psi, addLog);
            AppConstants.PropagateLanguageEnvironment(psi);
            ProcessOutputEncoding.ApplyPythonUtf8Environment(psi);

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
                "uvicorn api:app --reload --host 127.0.0.1 --port 8000\n\n" +
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
            "uvicorn api:app --reload --host 127.0.0.1 --port 8000");
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
                Arguments = ProcessOutputEncoding.CmdUtf8Command("npm run dev"),
                WorkingDirectory = frontendDir,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            InheritParentEnvironment(psi);
            PropagateFrontendSecrets(psi);
            AppConstants.PropagateLanguageEnvironment(psi);

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

    // --- Copia variáveis de ambiente do processo WPF para filhos ---
    private static void InheritParentEnvironment(ProcessStartInfo psi)
    {
        foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
        {
            var key = entry.Key?.ToString();
            if (string.IsNullOrEmpty(key))
                continue;
            psi.Environment[key] = entry.Value?.ToString() ?? "";
        }
    }

    // --- Propaga segredos RATANALYZER_* ao uvicorn filho ---
    private static void PropagateBackendSecrets(ProcessStartInfo psi, Action<string>? addLog)
    {
        var requireToken = string.Equals(
            Environment.GetEnvironmentVariable("RATANALYZER_REQUIRE_API_TOKEN"),
            "1",
            StringComparison.Ordinal);
        var production = string.Equals(
            Environment.GetEnvironmentVariable("RATANALYZER_ENV"),
            "production",
            StringComparison.OrdinalIgnoreCase)
            || string.Equals(
                Environment.GetEnvironmentVariable("RATANALYZER_REQUIRE_SECRETS"),
                "1",
                StringComparison.Ordinal);

        if ((requireToken || production) && string.IsNullOrWhiteSpace(AppConstants.BackendApiToken))
        {
            addLog?.Invoke(LocalizationManager.Get(LocKeys.LogProdTokenWarning));
        }
    }

    // --- Alinha VITE_API_TOKEN com RATANALYZER_API_TOKEN se o frontend não definir ---
    private static void PropagateFrontendSecrets(ProcessStartInfo psi)
    {
        if (!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("VITE_API_TOKEN")))
            return;

        var apiToken = AppConstants.BackendApiToken;
        if (!string.IsNullOrWhiteSpace(apiToken))
            psi.Environment["VITE_API_TOKEN"] = apiToken;
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
}
