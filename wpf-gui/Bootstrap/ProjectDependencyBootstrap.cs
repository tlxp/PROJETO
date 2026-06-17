using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using RatAnalyzer.Desktop.Helpers;
using RatAnalyzer.Desktop.Infrastructure;
using RatAnalyzer.Desktop.Localization;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop.Bootstrap;

/// <summary>
/// Na abertura do WPF: verifica e instala dependências comuns à análise estática (Python/pip, npm, YARA em Python,
/// JDK 21 para Ghidra, ILSpy CLI, Ghidra) e à análise em VM (Hyper-V, ADK/oscdimg, scripts). Depois <see cref="StartupSequence.RunFullStartupSequenceAsync"/>
/// continua para as portas 8000/8080.
/// </summary>
public static class ProjectDependencyBootstrap
{
    /// <summary>
    /// Instala apenas o que falta (pip/npm são idempotentes). Não instala Node/.NET/Python no sistema.
    /// </summary>
    public static async Task EnsureAndInstallAsync(Action<string> log, CancellationToken cancellationToken)
    {
        log(LocalizationManager.Get(LocKeys.LogDepsStart));

        await CheckExecutableAsync("dotnet", "--version", "SDK .NET (vm-agent, builds)", log, cancellationToken).ConfigureAwait(false);
        await CheckExecutableAsync("python", "--version", "Python (backend)", log, cancellationToken).ConfigureAwait(false);
        await CheckExecutableAsync("node", "--version", "Node.js (frontend)", log, cancellationToken).ConfigureAwait(false);
        await CheckExecutableAsync("npm", "--version", "npm (frontend)", log, cancellationToken).ConfigureAwait(false);

        var backendDir = StartupSequence.FindBackendWorkingDirectory();
        if (string.IsNullOrWhiteSpace(backendDir))
        {
            log(LocalizationManager.Get(LocKeys.LogBackendNotFound));
        }
        else
        {
            log(LocalizationManager.Format(LocKeys.LogBackendOk, backendDir));
            try
            {
                await StartupSequence.EnsureBackendPythonDependenciesAsync(backendDir, log).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                log(LocalizationManager.Format(LocKeys.LogBackendPipError, ex.Message));
            }

            await CheckPythonImportAsync(backendDir, "import fastapi, uvicorn", "FastAPI / uvicorn", log, cancellationToken).ConfigureAwait(false);
            await CheckPythonImportAsync(backendDir, "import yara", "yara-python (binário YARA no sistema)", log, cancellationToken).ConfigureAwait(false);
        }

        var frontendDir = StartupSequence.FindFrontendWorkingDirectory();
        if (string.IsNullOrWhiteSpace(frontendDir))
        {
            log(LocalizationManager.Get(LocKeys.LogFrontendNotFound));
        }
        else
        {
            log(LocalizationManager.Format(LocKeys.LogFrontendOk, frontendDir));
            try
            {
                await StartupSequence.EnsureFrontendNpmDependenciesAsync(frontendDir, log).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                log(LocalizationManager.Format(LocKeys.LogFrontendNpmError, ex.Message));
            }
        }

        await CheckHyperVOptionalFeatureAsync(log, cancellationToken).ConfigureAwait(false);

        var osc = SandboxHostDependencies.FindOscdimgPath();
        if (!string.IsNullOrWhiteSpace(osc))
        {
            log(LocalizationManager.Format(LocKeys.LogOscdimgOk, osc));
        }
        else
        {
            log(LocalizationManager.Get(LocKeys.LogOscdimgMissing));
        }

        var hypervScripts = FindHyperVSandboxScriptsDirectory();
        if (!string.IsNullOrWhiteSpace(hypervScripts))
        {
            log(LocalizationManager.Format(LocKeys.LogHypervScriptsOk, hypervScripts));
        }
        else
        {
            log(LocalizationManager.Get(LocKeys.LogHypervScriptsMissing));
        }

        try
        {
            await JavaDependencyHelper.TryOfferInstallIfMissingAsync(log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log(LocalizationManager.Format(LocKeys.LogJavaWarning, ex.Message));
        }

        try
        {
            await IlSpyDependencyHelper.TryOfferInstallIfMissingAsync(log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log(LocalizationManager.Format(LocKeys.LogIlspyWarning, ex.Message));
        }

        try
        {
            await GhidraDependencyHelper.TryOfferInstallIfMissingAsync(log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log(LocalizationManager.Format(LocKeys.LogGhidraWarning, ex.Message));
        }

        log(LocalizationManager.Get(LocKeys.LogDepsEnd));
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
                    FileName = ProcessOutputEncoding.ResolveExecutable(fileName),
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                ProcessOutputEncoding.ApplyConsole(psi);

                using var proc = Process.Start(psi);
                if (proc is null)
                {
                    log(LocalizationManager.Format(LocKeys.LogExecFailed, label, fileName));
                    return;
                }

                var stdout = proc.StandardOutput.ReadToEnd();
                var stderr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(30_000);
                cancellationToken.ThrowIfCancellationRequested();

                if (proc.ExitCode == 0)
                {
                    var oneLine = ProcessOutputEncoding.NormalizeForDisplay(
                        string.Join(" ", stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)).Trim());
                    if (oneLine.Length > 120)
                        oneLine = oneLine[..120] + "…";
                    log(string.IsNullOrEmpty(oneLine)
                        ? LocalizationManager.Format(LocKeys.LogExecOk, label)
                        : LocalizationManager.Format(LocKeys.LogExecOkDetail, label, oneLine));
                }
                else
                {
                    var detail = ProcessOutputEncoding.NormalizeForDisplay(
                        string.IsNullOrWhiteSpace(stderr) ? stdout : stderr).Trim();
                    if (detail.Length > 200)
                        detail = detail[..200] + "…";
                    log(LocalizationManager.Format(LocKeys.LogExecExitCode, label, fileName, proc.ExitCode, detail));
                }
            }
            catch (Exception ex)
            {
                log(LocalizationManager.Format(LocKeys.LogExecError, label, ex.Message));
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
                };
                ProcessOutputEncoding.ApplyUtf8(psi);
                ProcessOutputEncoding.ApplyPythonUtf8Environment(psi);

                using var proc = Process.Start(psi);
                if (proc is null)
                {
                    log(LocalizationManager.Format(LocKeys.LogPythonFailed, label));
                    return;
                }

                var stderr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(45_000);
                cancellationToken.ThrowIfCancellationRequested();

                if (proc.ExitCode == 0)
                {
                    log(LocalizationManager.Format(LocKeys.LogPythonOk, label));
                }
                else
                {
                    var err = ProcessOutputEncoding.NormalizeForDisplay(stderr).Trim();
                    if (err.Length > 220)
                        err = err[..220] + "…";
                    log(LocalizationManager.Format(LocKeys.LogPythonCheckFailed, label, proc.ExitCode, err));
                    if (importStatement.Contains("yara", StringComparison.OrdinalIgnoreCase))
                    {
                        log(LocalizationManager.Get(LocKeys.LogYaraNativeHint));
                    }
                }
            }
            catch (Exception ex)
            {
                log(LocalizationManager.Format(LocKeys.LogExecError, label, ex.Message));
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
                };
                ProcessOutputEncoding.ApplyWindowsAnsi(psi);

                using var proc = Process.Start(psi);
                if (proc is null)
                {
                    log(LocalizationManager.Get(LocKeys.LogHypervPsFailed));
                    return;
                }

                var stdout = ProcessOutputEncoding.NormalizeForDisplay(proc.StandardOutput.ReadToEnd()).Trim();
                proc.WaitForExit(120_000);
                cancellationToken.ThrowIfCancellationRequested();

                if (proc.ExitCode != 0)
                {
                    log(LocalizationManager.Get(LocKeys.LogHypervStateFailed));
                    return;
                }

                if (string.Equals(stdout, "Enabled", StringComparison.OrdinalIgnoreCase))
                {
                    log(LocalizationManager.Get(LocKeys.LogHypervEnabled));
                }
                else if (string.IsNullOrWhiteSpace(stdout))
                {
                    log(LocalizationManager.Get(LocKeys.LogHypervUnknown));
                }
                else
                {
                    log(LocalizationManager.Format(LocKeys.LogHypervState, stdout));
                }
            }
            catch (Exception ex)
            {
                log(LocalizationManager.Format(LocKeys.LogHypervError, ex.Message));
            }
        }, cancellationToken).ConfigureAwait(false);
    }
}
