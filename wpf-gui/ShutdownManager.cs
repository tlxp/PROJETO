using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop;

internal static class ShutdownManager
{
    private const int FrontendPort = 8080;
    private const int BackendPort = 8000;
    private static bool _cleanupCompleted;

    /// <summary>
    /// Limpa recursos locais ao sair da aplicação:
    /// - Termina o backend uvicorn gerido pelo WPF (se estiver ativo)
    /// - Termina o dev server do frontend (npm run dev) gerido pelo WPF (se estiver ativo)
    /// - Liberta as portas do frontend e backend (processos que estejam a escutar nessas portas)
    /// - Remove pastas temporárias de análise em %TEMP% (rat_*, rat_stream_*, RatAnalyzerAdk)
    /// - Remove amostras e artefactos em disco em sandbox_jobs (mantém analysis.db).
    /// </summary>
    public static void CleanupOnExit()
    {
        if (_cleanupCompleted)
        {
            return;
        }

        _cleanupCompleted = true;

        try
        {
            LoadingPage.StopManagedBackend();
        }
        catch
        {
            // Ignorar erros ao terminar o backend.
        }

        try
        {
            LoadingPage.StopManagedFrontend();
        }
        catch
        {
            // Ignorar erros ao terminar o frontend.
        }

        // Garantir que as portas 8080 (frontend) e 8000 (backend) são libertadas,
        // mesmo que processos filhos (ex.: node do npm) tenham ficado ativos.
        try
        {
            KillProcessesListeningOnPort(FrontendPort);
        }
        catch { /* ignorar */ }

        try
        {
            KillProcessesListeningOnPort(BackendPort);
        }
        catch { /* ignorar */ }

        try
        {
            KillOrphanedBackendUvicornProcesses();
        }
        catch { /* ignorar */ }

        try
        {
            KillProcessesListeningOnPort(FrontendPort);
            KillProcessesListeningOnPort(BackendPort);
        }
        catch { /* ignorar */ }

        try
        {
            LocalArtifactCleanup.CleanupOnApplicationExit();
        }
        catch
        {
            // Se a limpeza local falhar não impedimos o fecho da aplicação.
        }
    }

    /// <summary>
    /// Termina processos que estejam a escutar na porta indicada (ex.: node do frontend na 8080).
    /// Usa netstat no Windows para encontrar PIDs e garante que as portas são libertadas ao fechar o WPF.
    /// </summary>
    private static void KillProcessesListeningOnPort(int port)
    {
        foreach (var pid in GetListeningProcessIds(port))
        {
            TerminateProcessTree(pid);
        }
    }

    private static IEnumerable<int> GetListeningProcessIds(int port)
    {
        try
        {
            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "netstat",
                    Arguments = "-ano",
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                }
            };
            process.Start();
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(2000);

            // Linhas LISTENING com :PORT (ex.: "TCP    0.0.0.0:8080    0.0.0.0:0    LISTENING    12345")
            var portStr = $":{port}";
            var currentPid = Environment.ProcessId;
            return output
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(line => line.IndexOf(portStr, StringComparison.Ordinal) >= 0 &&
                               line.IndexOf("LISTENING", StringComparison.OrdinalIgnoreCase) >= 0)
                .Select(line =>
                {
                    var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    return parts.Length > 0 && int.TryParse(parts[^1], out var id) ? id : (int?)null;
                })
                .Where(id => id.HasValue && id.Value != currentPid)
                .Select(id => id!.Value)
                .Distinct()
                .ToList();
        }
        catch
        {
            return Array.Empty<int>();
        }
    }

    private static void TerminateProcessTree(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit(5000);
            }
        }
        catch
        {
            // Processo já terminou ou sem permissão; tentar taskkill como fallback.
        }

        try
        {
            using var killer = Process.Start(new ProcessStartInfo
            {
                FileName = "taskkill",
                Arguments = $"/F /T /PID {pid}",
                UseShellExecute = false,
                CreateNoWindow = true
            });
            killer?.WaitForExit(3000);
        }
        catch
        {
            // Ignorar falhas no fallback.
        }
    }

    private static void KillOrphanedBackendUvicornProcesses()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "powershell",
                Arguments = "-NoProfile -NonInteractive -Command \"Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'uvicorn' -and $_.CommandLine -match 'api:app' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {} }\"",
                UseShellExecute = false,
                CreateNoWindow = true
            });
            process?.WaitForExit(5000);
        }
        catch
        {
            // Ignorar falhas ao varrer processos Python/uvicorn.
        }
    }
}

