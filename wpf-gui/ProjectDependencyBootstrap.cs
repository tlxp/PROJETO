using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop;

/// <summary>
/// Na abertura do WPF: verifica e instala dependências comuns à análise estática (Python/pip, npm, YARA em Python,
/// JDK 21 para Ghidra, ILSpy CLI, Ghidra) e à análise em VM (Hyper-V, ADK/oscdimg, scripts). Depois <see cref="LoadingPage.RunFullStartupSequenceAsync"/>
/// continua para as portas 8000/8080.
/// </summary>
public static class ProjectDependencyBootstrap
{
    /// <summary>
    /// Instala apenas o que falta (pip/npm são idempotentes). Não instala Node/.NET/Python no sistema.
    /// </summary>
    public static async Task EnsureAndInstallAsync(Action<string> log, CancellationToken cancellationToken)
    {
        log("[INFO] === Dependências: análise estática + VM (verificação / instalação) ===");

        await CheckExecutableAsync("dotnet", "--version", "SDK .NET (vm-agent, builds)", log, cancellationToken).ConfigureAwait(false);
        await CheckExecutableAsync("python", "--version", "Python (backend)", log, cancellationToken).ConfigureAwait(false);
        await CheckExecutableAsync("node", "--version", "Node.js (frontend)", log, cancellationToken).ConfigureAwait(false);
        await CheckExecutableAsync("npm", "--version", "npm (frontend)", log, cancellationToken).ConfigureAwait(false);

        var backendDir = LoadingPage.FindBackendWorkingDirectory();
        if (string.IsNullOrWhiteSpace(backendDir))
        {
            log("[AVISO] Pasta 'backend' não encontrada a partir do executável — pip em falta.");
        }
        else
        {
            log($"[OK] Pasta backend: {backendDir}");
            try
            {
                await LoadingPage.EnsureBackendPythonDependenciesAsync(backendDir, log).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                log($"[ERRO] Dependências Python (pip): {ex.Message}");
            }

            await CheckPythonImportAsync(backendDir, "import fastapi, uvicorn", "FastAPI / uvicorn", log, cancellationToken).ConfigureAwait(false);
            await CheckPythonImportAsync(backendDir, "import yara", "yara-python (binário YARA no sistema)", log, cancellationToken).ConfigureAwait(false);
        }

        var frontendDir = LoadingPage.FindFrontendWorkingDirectory();
        if (string.IsNullOrWhiteSpace(frontendDir))
        {
            log("[AVISO] Pasta 'frontend' não encontrada — npm em falta.");
        }
        else
        {
            log($"[OK] Pasta frontend: {frontendDir}");
            try
            {
                await LoadingPage.EnsureFrontendNpmDependenciesAsync(frontendDir, log).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                log($"[ERRO] Dependências npm: {ex.Message}");
            }
        }

        await CheckHyperVOptionalFeatureAsync(log, cancellationToken).ConfigureAwait(false);

        var osc = SandboxHostDependencies.FindOscdimgPath();
        if (!string.IsNullOrWhiteSpace(osc))
        {
            log($"[OK] oscdimg.exe (Windows ADK): {osc}");
        }
        else
        {
            log("[AVISO] oscdimg.exe em falta — necessário para criar ISO com autounattend (VM). " +
                "Instale o Windows ADK (Deployment Tools) ou aceite a instalação quando abrir análise na VM.");
        }

        var hypervScripts = FindHyperVSandboxScriptsDirectory();
        if (!string.IsNullOrWhiteSpace(hypervScripts))
        {
            log($"[OK] scripts/hyperv-sandbox: {hypervScripts}");
        }
        else
        {
            log("[AVISO] scripts/hyperv-sandbox não encontrado — análise VM Hyper-V pode falhar.");
        }

        try
        {
            await JavaDependencyHelper.TryOfferInstallIfMissingAsync(log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[AVISO] Java JDK: {ex.Message}");
        }

        try
        {
            await IlSpyDependencyHelper.TryOfferInstallIfMissingAsync(log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[AVISO] ILSpy CLI: {ex.Message}");
        }

        try
        {
            await GhidraDependencyHelper.TryOfferInstallIfMissingAsync(log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[AVISO] Ghidra: {ex.Message}");
        }

        log("[INFO] === Fim dependências; a abrir serviços nas portas 8000 e 8080 ===");
    }

    private static string? FindHyperVSandboxScriptsDirectory()
    {
        var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
        for (var i = 0; i < 8 && dir != null; i++)
        {
            var candidate = Path.Combine(dir.FullName, "scripts", "hyperv-sandbox");
            if (Directory.Exists(candidate))
                return candidate;
            dir = dir.Parent;
        }

        return null;
    }

    private static async Task CheckExecutableAsync(
        string fileName,
        string arguments,
        string label,
        Action<string> log,
        CancellationToken cancellationToken)
    {
        await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = fileName,
                    Arguments = arguments,
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
                    log($"[ERRO] {label}: não foi possível iniciar '{fileName}'.");
                    return;
                }

                var stdout = proc.StandardOutput.ReadToEnd();
                var stderr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(30_000);
                cancellationToken.ThrowIfCancellationRequested();

                if (proc.ExitCode == 0)
                {
                    var oneLine = string.Join(" ", stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)).Trim();
                    if (oneLine.Length > 120)
                        oneLine = oneLine[..120] + "…";
                    log(string.IsNullOrEmpty(oneLine) ? $"[OK] {label}" : $"[OK] {label}: {oneLine}");
                }
                else
                {
                    var detail = string.IsNullOrWhiteSpace(stderr) ? stdout : stderr;
                    detail = detail.Trim();
                    if (detail.Length > 200)
                        detail = detail[..200] + "…";
                    log($"[ERRO] {label}: '{fileName}' saiu com código {proc.ExitCode}. {detail}");
                }
            }
            catch (Exception ex)
            {
                log($"[ERRO] {label}: {ex.Message}");
            }
        }, cancellationToken).ConfigureAwait(false);
    }

    private static async Task CheckPythonImportAsync(
        string workingDirectory,
        string importStatement,
        string label,
        Action<string> log,
        CancellationToken cancellationToken)
    {
        await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "python",
                    Arguments = "-c \"" + importStatement.Replace("\"", "\\\"") + "\"",
                    WorkingDirectory = workingDirectory,
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
                    log($"[ERRO] {label}: não foi possível executar python.");
                    return;
                }

                var stderr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(45_000);
                cancellationToken.ThrowIfCancellationRequested();

                if (proc.ExitCode == 0)
                {
                    log($"[OK] {label}");
                }
                else
                {
                    var err = stderr.Trim();
                    if (err.Length > 220)
                        err = err[..220] + "…";
                    log($"[AVISO] {label}: falhou (código {proc.ExitCode}). {err}");
                    if (importStatement.Contains("yara", StringComparison.OrdinalIgnoreCase))
                    {
                        log("[INFO] YARA: instale a biblioteca nativa (Windows) além do pip — ver README do projeto.");
                    }
                }
            }
            catch (Exception ex)
            {
                log($"[AVISO] {label}: {ex.Message}");
            }
        }, cancellationToken).ConfigureAwait(false);
    }

    private static async Task CheckHyperVOptionalFeatureAsync(Action<string> log, CancellationToken cancellationToken)
    {
        await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments =
                        "-NoProfile -ExecutionPolicy Bypass -Command \"(Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue | Select-Object -ExpandProperty State)\"",
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
                    log("[AVISO] Hyper-V: não foi possível executar PowerShell.");
                    return;
                }

                var stdout = proc.StandardOutput.ReadToEnd().Trim();
                proc.WaitForExit(120_000);
                cancellationToken.ThrowIfCancellationRequested();

                if (proc.ExitCode != 0)
                {
                    log("[AVISO] Hyper-V: não foi possível ler o estado (executar como Administrador?).");
                    return;
                }

                if (string.Equals(stdout, "Enabled", StringComparison.OrdinalIgnoreCase))
                {
                    log("[OK] Hyper-V (Microsoft-Hyper-V): Enabled");
                }
                else if (string.IsNullOrWhiteSpace(stdout))
                {
                    log("[AVISO] Hyper-V: estado desconhecido (edição Windows Home não inclui Hyper-V?).");
                }
                else
                {
                    log($"[AVISO] Hyper-V: estado '{stdout}' — necessário Enabled para VM local (reinício após Enable-WindowsOptionalFeature).");
                }
            }
            catch (Exception ex)
            {
                log($"[AVISO] Hyper-V: {ex.Message}");
            }
        }, cancellationToken).ConfigureAwait(false);
    }
}
