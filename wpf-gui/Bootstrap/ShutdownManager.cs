// --- Módulo: ShutdownManager.cs ---
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text.RegularExpressions;
using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.Bootstrap;

internal static class ShutdownManager
{
    private const int FrontendPort = 8080;
    private const int BackendPort = 8000;
    private static bool _cleanupCompleted;

    // --- Ao sair: termina backend/frontend geridos, liberta portas 8000/8080 e limpa artefatos locais ---
    public static void CleanupOnExit()
    {
        if (_cleanupCompleted)
        {
            return;
        }

        _cleanupCompleted = true;

        try
        {
            StartupSequence.StopManagedBackend();
        }
        catch { /* ignorar */ }

        try
        {
            StartupSequence.StopManagedFrontend();
        }
        catch { /* ignorar */ }

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
            LocalArtifactCleanup.CleanupOnApplicationExit();
        }
        catch { /* ignorar */ }
    }

    // --- Termina processos à escuta na porta (netstat no Windows) para libertar 8080/8000 ---
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

            // Linhas LISTENING com :PORT exacto (evita :80801, :18080, etc.)
            var portPattern = new Regex($@"(?<!\d):{port}(\s|$)", RegexOptions.CultureInvariant);
            var currentPid = Environment.ProcessId;
            return output
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(line => portPattern.IsMatch(line) &&
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
        catch { /* ignorar */ }

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
        catch { /* ignorar */ }
    }
}

