using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace RatAnalyzer.Desktop;

/// <summary>
/// Verifica e, se o utilizador aceitar, instala o Windows ADK (Deployment Tools) para fornecer oscdimg.exe,
/// alinhado com <c>scripts/hyperv-sandbox/SandboxCommon.psm1</c>.
/// </summary>
internal static class SandboxHostDependencies
{
    /// <summary>Link oficial usado nos scripts (redireciona para adksetup.exe).</summary>
    public const string AdkSetupDownloadUrl = "https://go.microsoft.com/fwlink/?linkid=2196127";

    private static readonly string[] OscdimgCandidatePaths =
    {
        @"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        @"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
        @"C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
    };

    /// <summary>Localiza oscdimg.exe nos caminhos do ADK ou no PATH.</summary>
    public static string? FindOscdimgPath()
    {
        foreach (var p in OscdimgCandidatePaths)
        {
            if (File.Exists(p))
                return p;
        }

        var pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(pathEnv))
            return null;

        foreach (var dir in pathEnv.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim(), "oscdimg.exe");
                if (File.Exists(candidate))
                    return candidate;
            }
            catch
            {
                // ignorar caminhos inválidos
            }
        }

        return null;
    }

    /// <summary>
    /// Garante oscdimg: se em falta, pergunta ao utilizador e corre instalador silencioso do ADK (Deployment Tools).
    /// </summary>
    /// <returns>true se oscdimg ficou disponível; false se em falta após tentativa ou recusa.</returns>
    public static async Task<bool> EnsureOscdimgAsync(
        Action<string> log,
        CancellationToken cancellationToken,
        Func<Task<bool>> confirmInstallAsync)
    {
        var existing = FindOscdimgPath();
        if (existing != null)
        {
            log($"[OK] oscdimg.exe encontrado: {existing}");
            return true;
        }

        log("[AVISO] oscdimg.exe não encontrado — necessário para injetar autounattend.xml no ISO (Windows ADK Deployment Tools).");

        var confirm = await confirmInstallAsync().ConfigureAwait(true);
        if (!confirm)
        {
            log("[*] Instalação automática do ADK recusada; o setup pode continuar com ISO original e instalação manual na VM.");
            return false;
        }

        // Nome de ficheiro único: evita "ficheiro em uso" se um adksetup anterior, antivírus ou 2.º arranque
        // tiverem ainda o adksetup.exe clássico aberto em Temp\RatAnalyzerAdk\adksetup.exe.
        var tempDir = Path.Combine(Path.GetTempPath(), "RatAnalyzerAdk");
        Directory.CreateDirectory(tempDir);
        var setupPath = Path.Combine(tempDir, $"adksetup-{Guid.NewGuid():N}.exe");

        try
        {
            log("[INFO] A transferir o instalador web do Windows ADK (Microsoft)…");
            await DownloadAdkSetupAsync(setupPath, log, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[ERRO] Falha ao transferir adksetup.exe: {ex.Message}");
            return false;
        }

        log("[INFO] A iniciar instalação silenciosa do ADK (Deployment Tools). Será pedida permissão de administrador.");
        log("[INFO] Isto pode demorar vários minutos; não feche a janela do instalador na barra de tarefas.");

        int? exitCode;
        try
        {
            exitCode = await RunElevatedInstallerAsync(setupPath, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[ERRO] Não foi possível iniciar o instalador elevado: {ex.Message}");
            exitCode = null;
        }

        if (exitCode.HasValue)
        {
            log($"[INFO] Instalador ADK terminou com código: {exitCode.Value} (3010 = concluído, pode exigir reinício).");
        }

        // O processo elevado pode terminar antes dos ficheiros aparecerem; o adksetup pode delegar a MSIs.
        log("[INFO] A aguardar conclusão da instalação (a verificar oscdimg.exe)…");
        for (var i = 0; i < 540; i++) // até ~90 min, passo 10 s
        {
            cancellationToken.ThrowIfCancellationRequested();
            var found = FindOscdimgPath();
            if (found != null)
            {
                log($"[OK] oscdimg.exe disponível após instalação: {found}");
                return true;
            }

            await Task.Delay(10_000, cancellationToken).ConfigureAwait(false);
        }

        log("[ERRO] oscdimg.exe ainda não encontrado após a instalação. Instale manualmente o Windows ADK (Deployment Tools) a partir de: " +
            AdkSetupDownloadUrl);
        return false;
    }

    private static async Task DownloadAdkSetupAsync(string destinationPath, Action<string> log, CancellationToken cancellationToken)
    {
        const int maxAttempts = 5;
        using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(30) };

        using var response = await http.GetAsync(AdkSetupDownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken)
            .ConfigureAwait(false);
        response.EnsureSuccessStatusCode();

        // Buffer em memória: instalador web é pequeno e permite regravar se o disco estiver momentaneamente bloqueado.
        var data = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                await File.WriteAllBytesAsync(destinationPath, data, cancellationToken).ConfigureAwait(false);
                break;
            }
            catch (IOException ex) when (attempt < maxAttempts)
            {
                log($"[AVISO] Não foi possível gravar o instalador (tentativa {attempt}/{maxAttempts}): {ex.Message}");
                await Task.Delay(TimeSpan.FromSeconds(Math.Min(8, attempt * 2)), cancellationToken).ConfigureAwait(false);
            }
        }

        if (!File.Exists(destinationPath))
            throw new IOException($"Não foi possível gravar o instalador em '{destinationPath}' após {maxAttempts} tentativas.");

        var len = new FileInfo(destinationPath).Length;
        if (len < 50_000)
            throw new InvalidOperationException("Transferência demasiado pequena; possível página HTML em vez de adksetup.exe.");

        // Cabeçalho PE (MZ)
        await using (var check = File.OpenRead(destinationPath))
        {
            var sig = new byte[2];
            if (await check.ReadAsync(sig.AsMemory(0, 2), cancellationToken).ConfigureAwait(false) != 2 ||
                sig[0] != 0x4D || sig[1] != 0x5A)
            {
                throw new InvalidOperationException("O ficheiro transferido não parece ser um executável Windows (.exe).");
            }
        }

        log($"[OK] Instalador ADK guardado ({len / 1024} KB).");
    }

    /// <summary>
    /// Executa adksetup com elevação. Em alguns sistemas <see cref="Process.Start(processStartInfo)"/> com Verb runas
    /// não devolve o processo do filho elevado; nesse caso devolve null e confiamos no polling de oscdimg.
    /// </summary>
    private static async Task<int?> RunElevatedInstallerAsync(string setupPath, CancellationToken cancellationToken)
    {
        var psi = new ProcessStartInfo
        {
            FileName = setupPath,
            // Deployment Tools = oscdimg, alinhado com SandboxCommon.psm1
            Arguments = "/quiet /features OptionId.DeploymentTools /norestart",
            UseShellExecute = true,
            Verb = "runas",
            WorkingDirectory = Path.GetDirectoryName(setupPath) ?? Path.GetTempPath()
        };

        using var proc = Process.Start(psi);
        if (proc == null)
        {
            // Utilizador pode ter confirmado UAC; o processo de arranque pode não ser o mesmo.
            return null;
        }

        try
        {
            await proc.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            return proc.ExitCode;
        }
        catch
        {
            return null;
        }
    }
}
