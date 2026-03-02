using System;
using System.IO;
using RatAnalyzer.Desktop.Views;

namespace RatAnalyzer.Desktop;

internal static class ShutdownManager
{
    /// <summary>
    /// Limpa recursos locais ao sair da aplicação:
    /// - Termina o backend uvicorn gerido pelo WPF (se estiver ativo)
    /// - Termina o dev server do frontend (npm run dev) gerido pelo WPF (se estiver ativo)
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

            // Segue a mesma convenção de backend/config.py (SANDBOX_JOBS_DIR = PROJECT_ROOT / "sandbox_jobs")
            var sandboxJobsDir = Path.Combine(projectRoot, "sandbox_jobs");
            if (Directory.Exists(sandboxJobsDir))
            {
                Directory.Delete(sandboxJobsDir, recursive: true);
            }
        }
        catch
        {
            // Se a limpeza da cache falhar não impedimos o fecho da aplicação.
        }
    }
}

