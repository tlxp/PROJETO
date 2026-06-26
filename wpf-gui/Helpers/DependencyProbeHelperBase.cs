// --- Módulo: DependencyProbeHelperBase.cs ---
// Classe base para helpers WPF de dependências externas (sondagem → MessageBox → instalação → verificação).
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.Helpers;

// --- Utilitários partilhados e orquestração do fluxo de instalação guiada ---
internal abstract class DependencyProbeHelperBase
{
    // --- Secção: Utilitários de processo ---

    // --- Executa processo com captura de stdout/stderr (timeouts configuráveis por chamada) ---
    protected static async Task<(int ExitCode, string StdOut, string StdErr)> RunProcessCaptureAsync(
        string fileName,
        string arguments,
        CancellationToken ct,
        int exitTimeoutMs = 300_000)
    {
        return await Task.Run(() =>
        {
            var psi = new ProcessStartInfo
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            ProcessOutputEncoding.ApplyConsole(psi);
            using var proc = Process.Start(psi);
            if (proc is null)
                return (-1, "", "Process.Start devolveu null.");
            var stdout = ProcessOutputEncoding.NormalizeForDisplay(proc.StandardOutput.ReadToEnd());
            var stderr = ProcessOutputEncoding.NormalizeForDisplay(proc.StandardError.ReadToEnd());
            proc.WaitForExit(exitTimeoutMs);
            ct.ThrowIfCancellationRequested();
            return (proc.ExitCode, stdout, stderr);
        }, ct).ConfigureAwait(false);
    }

    // --- Trunca texto longo para logs e MessageBox ---
    protected static string Truncate(string s, int max)
    {
        if (string.IsNullOrEmpty(s))
            return "";
        s = s.Trim();
        return s.Length <= max ? s : s[..max] + "…";
    }

    // --- Garante %USERPROFILE%\.dotnet\tools no PATH do processo filho ---
    protected static void EnsureDotNetGlobalToolsOnPath(ProcessStartInfo psi)
    {
        var tools = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".dotnet", "tools");
        if (!Directory.Exists(tools))
            return;

        var existing = psi.Environment["PATH"] ?? Environment.GetEnvironmentVariable("PATH") ?? "";
        if (existing.IndexOf(tools, StringComparison.OrdinalIgnoreCase) >= 0)
            return;

        psi.Environment["PATH"] = tools + Path.PathSeparator + existing;
    }

    // --- Verifica se um comando responde com código de saída zero ---
    protected static async Task<bool> IsCommandAvailableAsync(
        string fileName,
        string arguments,
        CancellationToken ct,
        int exitTimeoutMs = 30_000)
    {
        return await Task.Run(() =>
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
                    RedirectStandardError = true
                };
                using var proc = Process.Start(psi);
                if (proc is null)
                    return false;
                proc.WaitForExit(exitTimeoutMs);
                ct.ThrowIfCancellationRequested();
                return proc.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }, ct).ConfigureAwait(false);
    }

    // --- Interpreta saída típica de «dotnet tool install» quando o pacote já existe ---
    protected static bool LooksLikeDotnetToolAlreadyInstalled(string output)
    {
        if (string.IsNullOrEmpty(output))
            return false;
        var lo = output.ToLowerInvariant();
        return lo.Contains("already installed", StringComparison.Ordinal)
               || lo.Contains("is already installed", StringComparison.Ordinal)
               || lo.Contains("já está instalado", StringComparison.Ordinal)
               || lo.Contains("already has", StringComparison.Ordinal);
    }

    // --- Secção: Fluxo WPF (MessageBox) ---

    // --- Obtém Application.Current com Dispatcher utilizável ---
    protected static bool TryGetUiDispatcher(out Application app)
    {
        app = Application.Current!;
        return app?.Dispatcher != null;
    }

    // --- Diálogo Sim/Não para confirmar instalação automática ---
    protected static async Task<bool> ConfirmInstallAsync(Application app, string message, string title)
    {
        return await app.Dispatcher.InvokeAsync(() =>
            MessageBox.Show(
                message,
                title,
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes);
    }

    // --- Diálogo informativo após instalação bem-sucedida ---
    protected static void ShowInstallSuccess(string message, string title)
    {
        Application.Current?.Dispatcher.Invoke(() =>
            MessageBox.Show(
                message,
                title,
                MessageBoxButton.OK,
                MessageBoxImage.Information));
    }

    // --- Diálogo de aviso quando a instalação automática falha ---
    protected static async Task ShowInstallErrorAsync(Application app, string message, string title)
    {
        await app.Dispatcher.InvokeAsync(() =>
            MessageBox.Show(
                message,
                title,
                MessageBoxButton.OK,
                MessageBoxImage.Warning));
    }

    // --- Executa instalação com registo de erro e MessageBox em caso de excepção ---
    protected static async Task RunInstallWithUiErrorHandlingAsync(
        Application app,
        Action<string> log,
        string errorLogPrefix,
        string errorDialogTitle,
        Func<Exception, string> buildErrorDialogBody,
        CancellationToken ct,
        Func<Action<string>, CancellationToken, Task> installAsync)
    {
        try
        {
            await installAsync(log, ct).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[ERRO] {errorLogPrefix}: {ex.Message}");
            await ShowInstallErrorAsync(app, buildErrorDialogBody(ex), errorDialogTitle).ConfigureAwait(false);
        }
    }

    // --- Orquestra: dispatcher → pré-condição opcional → confirmação → instalação com erros UI ---
    protected static async Task TryRunConfirmedInstallFlowAsync(
        Action<string> log,
        CancellationToken ct,
        string noDispatcherLogMessage,
        string confirmMessage,
        string confirmTitle,
        string cancelLogMessage,
        string errorLogPrefix,
        string errorDialogTitle,
        Func<Exception, string> buildErrorDialogBody,
        Func<Action<string>, CancellationToken, Task> installAsync,
        Func<CancellationToken, Task<bool>>? preConfirmGateAsync = null,
        Action? onPreConfirmGateFailed = null)
    {
        if (!TryGetUiDispatcher(out var app))
        {
            log(noDispatcherLogMessage);
            return;
        }

        if (preConfirmGateAsync != null && !await preConfirmGateAsync(ct).ConfigureAwait(false))
        {
            onPreConfirmGateFailed?.Invoke();
            return;
        }

        if (!await ConfirmInstallAsync(app, confirmMessage, confirmTitle).ConfigureAwait(false))
        {
            log(cancelLogMessage);
            return;
        }

        await RunInstallWithUiErrorHandlingAsync(
            app,
            log,
            errorLogPrefix,
            errorDialogTitle,
            buildErrorDialogBody,
            ct,
            installAsync).ConfigureAwait(false);
    }
}
