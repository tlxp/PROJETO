using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop;

internal static class ShutdownManager
{
    private const int FrontendPort = 8080;
    private const int BackendPort = 8000;

    /// <summary>
    /// Limpa recursos locais ao sair da aplicação:
    /// - Termina o backend uvicorn gerido pelo WPF (se estiver ativo)
    /// - Termina o dev server do frontend (npm run dev) gerido pelo WPF (se estiver ativo)
    /// - Liberta as portas do frontend e backend (processos que estejam a escutar nessas portas)
    /// - Apaga a cache local de jobs em sandbox_jobs (não afeta cache do browser).
    /// </summary>
    public static void CleanupOnExit()
    {
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
            var backendDir = LoadingPage.FindBackendWorkingDirectory();
            var projectRoot = backendDir != null
                ? Directory.GetParent(backendDir)?.FullName
                : null;

            if (string.IsNullOrWhiteSpace(projectRoot))
            {
                return;
            }

            // Nota: outputs já não vivem no repo por defeito (agora são guardados em %LOCALAPPDATA%\\RatAnalyzer).
            // Não apagar dados automaticamente ao sair (comportamento destrutivo).
        }
        catch
        {
            // Se a limpeza da cache falhar não impedimos o fecho da aplicação.
        }
    }

    /// <summary>
    /// Termina processos que estejam a escutar na porta indicada (ex.: node do frontend na 8080).
    /// Usa netstat no Windows para encontrar PIDs e garante que as portas são libertadas ao fechar o WPF.
    /// </summary>
    private static void KillProcessesListeningOnPort(int port)
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
            var pids = output
                .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(line => line.IndexOf(portStr, StringComparison.Ordinal) >= 0 &&
                               line.IndexOf("LISTENING", StringComparison.OrdinalIgnoreCase) >= 0)
                .Select(line =>
                {
                    var parts = line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                    return parts.Length > 0 && int.TryParse(parts[^1], out var id) ? id : (int?)null;
                })
                .Where(id => id.HasValue)
                .Select(id => id!.Value)
                .Distinct()
                .ToList();

            var currentPid = Environment.ProcessId;
            foreach (var pid in pids)
            {
                if (pid == currentPid)
                    continue;
                try
                {
                    using var p = Process.GetProcessById(pid);
                    p.Kill();
                }
                catch
                {
                    // Processo já terminou ou sem permissão; ignorar.
                }
            }
        }
        catch
        {
            // Falha ao executar netstat ou matar processo; não bloquear o fecho.
        }
    }
}

