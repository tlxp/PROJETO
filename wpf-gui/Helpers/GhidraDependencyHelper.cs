// --- Módulo: GhidraDependencyHelper.cs ---
// Deteção e instalação opcional do Ghidra para o backend.
using System;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace RatAnalyzer.Desktop.Helpers;

// --- Oferece instalação guiada do Ghidra (transferência + extração) quando GHIDRA_INSTALL_DIR é inválido ---
internal sealed class GhidraDependencyHelper : DependencyProbeHelperBase
{
    private const string GithubLatestApi =
        "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest";

    // --- Resolve GHIDRA_INSTALL_DIR (processo/utilizador/máquina) se a pasta for instalação Ghidra válida ---
    public static string? GetEffectiveGhidraInstallDir()
    {
        foreach (var target in new[]
                     { EnvironmentVariableTarget.Process, EnvironmentVariableTarget.User, EnvironmentVariableTarget.Machine })
        {
            var v = Environment.GetEnvironmentVariable("GHIDRA_INSTALL_DIR", target);
            if (string.IsNullOrWhiteSpace(v))
                continue;
            var trim = v.Trim();
            if (IsValidGhidraDirectory(trim))
                return trim;
        }

        var baseDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RatAnalyzer",
            "Ghidra");
        if (!Directory.Exists(baseDir))
            return null;

        string? best = null;
        foreach (var d in Directory.GetDirectories(baseDir))
        {
            if (!IsValidGhidraDirectory(d))
                continue;
            if (best == null || string.Compare(d, best, StringComparison.OrdinalIgnoreCase) > 0)
                best = d;
        }

        return best;
    }

    // --- Instalação Ghidra válida para o uvicorn (ignora GHIDRA_INSTALL_DIR obsoleto) ---
    internal static string? ResolveGhidraInstallDirForBackend() => GetEffectiveGhidraInstallDir();

    // --- Verifica se válido Ghidra pasta ---
    public static bool IsValidGhidraDirectory(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
            return false;

        // ghidraRun.bat está na RAIZ da pasta do Ghidra (não em support\).
        if (File.Exists(Path.Combine(path, "ghidraRun.bat")))
            return true;

        // Fallback: validação alternativa pela presença de Ghidra\ + support\launch.properties
        if (Directory.Exists(Path.Combine(path, "Ghidra")) &&
            File.Exists(Path.Combine(path, "support", "launch.properties")))
            return true;

        // Compatibilidade retroativa com versões muito antigas que tinham support\ghidraRun.bat
        if (File.Exists(Path.Combine(path, "support", "ghidraRun.bat")))
            return true;

        return false;
    }

    // --- Se já existir Ghidra válido regista no log; senão pergunta ao utilizador e tenta instalar ---
    public static async Task TryOfferInstallIfMissingAsync(Action<string> log, CancellationToken ct)
    {
        var existing = GetEffectiveGhidraInstallDir();
        if (existing != null)
        {
            log($"[OK] Ghidra: {existing}");
            return;
        }

        var raw = Environment.GetEnvironmentVariable("GHIDRA_INSTALL_DIR");
        if (!string.IsNullOrWhiteSpace(raw))
        {
            log("[AVISO] GHIDRA_INSTALL_DIR está definido mas não é uma instalação Ghidra válida " +
                "(em falta: ghidraRun.bat na raiz da pasta do Ghidra).");
        }
        else
        {
            log("[INFO] GHIDRA_INSTALL_DIR não definido (pseudo-C nativo opcional).");
        }

        await TryRunConfirmedInstallFlowAsync(
            log,
            ct,
            noDispatcherLogMessage:
                "[INFO] Ghidra em falta — sem janela principal para confirmar a transferência; " +
                "defina GHIDRA_INSTALL_DIR manualmente ou reabra o arranque pela interface.",
            confirmMessage:
                "O Ghidra não foi encontrado (variável de ambiente GHIDRA_INSTALL_DIR).\n\n" +
                "Para decompilação nativa (pseudo-C), é necessário o Ghidra.\n\n" +
                "Deseja transferir e extrair automaticamente a versão mais recente dos releases oficiais " +
                "(NationalSecurityAgency/ghidra no GitHub)?\n\n" +
                "• Download grande (várias centenas de MB)\n" +
                "• Pode demorar vários minutos\n\n" +
                "Alternativa: instale manualmente e defina GHIDRA_INSTALL_DIR para a pasta extraída.",
            confirmTitle: "Instalar Ghidra",
            cancelLogMessage: "[INFO] Instalação automática do Ghidra cancelada.",
            errorLogPrefix: "Ghidra",
            errorDialogTitle: "Erro — Ghidra",
            buildErrorDialogBody: ex =>
                "Não foi possível instalar o Ghidra automaticamente.\n\n" + ex.Message + "\n\n" +
                "Instale manualmente a partir de:\nhttps://github.com/NationalSecurityAgency/ghidra/releases",
            installAsync: DownloadAndInstallAsync).ConfigureAwait(false);
    }

    // --- Transfere e instalação ---
    private static async Task DownloadAndInstallAsync(Action<string> log, CancellationToken ct)
    {
        using var http = new HttpClient();
        http.DefaultRequestHeaders.UserAgent.ParseAdd("RatAnalyzer-Desktop/1.0 (Ghidra auto-install)");
        http.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        http.Timeout = TimeSpan.FromMinutes(120);

        log("[INFO] Ghidra: a obter metadados do release mais recente (GitHub API)...");
        var releaseJson = await http.GetStringAsync(GithubLatestApi, ct).ConfigureAwait(false);
        var (zipUrl, zipName) = ParseLatestReleaseZip(releaseJson);
        if (zipUrl == null || zipName == null)
            throw new InvalidOperationException(
                "Não foi encontrado um ficheiro ghidra_*_PUBLIC_*.zip no último release.");

        var baseDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RatAnalyzer",
            "Ghidra");
        Directory.CreateDirectory(baseDir);
        var zipPath = Path.Combine(baseDir, zipName);

        log($"[INFO] Ghidra: a transferir {zipName} ...");
        await DownloadFileWithProgressAsync(http, zipUrl, zipPath, log, ct).ConfigureAwait(false);

        var shaUrl = DownloadIntegrity.TryFindGithubSha256AssetUrl(releaseJson, zipName);
        if (shaUrl != null)
        {
            log("[INFO] Ghidra: a verificar SHA-256 do release oficial...");
            var shaText = await http.GetStringAsync(shaUrl, ct).ConfigureAwait(false);
            var expected = DownloadIntegrity.ParseSha256FileContent(shaText);
            DownloadIntegrity.VerifySha256OrThrow(zipPath, expected);
            log("[OK] Ghidra: SHA-256 verificado.");
        }
        else
        {
            log("[AVISO] Ghidra: ficheiro .sha256 não encontrado no release — transferência sem verificação de hash.");
        }

        log("[INFO] Ghidra: a extrair (pode demorar)...");
        var extractRoot = Path.Combine(baseDir, "extract-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(extractRoot);
        try
        {
            ZipFile.ExtractToDirectory(zipPath, extractRoot);
        }
        catch
        {
            try
            {
                Directory.Delete(extractRoot, true);
            }
            catch { /* ignorar */ }

            throw;
        }

        var ghidraHome = FindGhidraRootInExtract(extractRoot);
        if (ghidraHome == null)
        {
            try
            {
                Directory.Delete(extractRoot, true);
            }
            catch { /* ignorar */ }

            throw new InvalidOperationException("Estrutura do ZIP inesperada (pasta Ghidra não encontrada).");
        }

        var folderName = Path.GetFileName(ghidraHome.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        var finalDir = Path.Combine(baseDir, folderName ?? "ghidra");
        if (Directory.Exists(finalDir))
        {
            try
            {
                Directory.Delete(finalDir, true);
            }
            catch (Exception ex)
            {
                throw new IOException($"Não foi possível substituir a pasta existente: {finalDir}", ex);
            }
        }

        Directory.Move(ghidraHome, finalDir);

        try
        {
            Directory.Delete(extractRoot, true);
        }
        catch { /* ignorar */ }

        Environment.SetEnvironmentVariable("GHIDRA_INSTALL_DIR", finalDir, EnvironmentVariableTarget.User);
        Environment.SetEnvironmentVariable("GHIDRA_INSTALL_DIR", finalDir, EnvironmentVariableTarget.Process);

        log($"[OK] Ghidra instalado em: {finalDir}");
        log("[INFO] GHIDRA_INSTALL_DIR definido para o utilizador e para esta sessão.");

        ShowInstallSuccess(
            "Ghidra extraído para:\n" + finalDir + "\n\n" +
            "A variável de utilizador GHIDRA_INSTALL_DIR foi definida.\n\n" +
            "Se o backend Python já estiver em execução, reinicie-o para aplicar o novo caminho.",
            "Ghidra");

        try
        {
            File.Delete(zipPath);
        }
        catch { /* ignorar */ }
    }

    // --- Localiza Ghidra raiz em extract ---
    private static string? FindGhidraRootInExtract(string extractRoot)
    {
        foreach (var d in Directory.GetDirectories(extractRoot))
        {
            if (IsValidGhidraDirectory(d))
                return d;
        }

        foreach (var top in Directory.GetDirectories(extractRoot))
        {
            foreach (var d in Directory.GetDirectories(top))
            {
                if (IsValidGhidraDirectory(d))
                    return d;
            }
        }

        return null;
    }

    private static (string? url, string? fileName) ParseLatestReleaseZip(string json)
    {
        using var doc = JsonDocument.Parse(json);
        if (!doc.RootElement.TryGetProperty("assets", out var assets))
            return (null, null);

        string? bestUrl = null;
        string? bestName = null;
        long bestSize = -1;

        foreach (var a in assets.EnumerateArray())
        {
            if (!a.TryGetProperty("name", out var nameEl))
                continue;
            var name = nameEl.GetString();
            if (string.IsNullOrEmpty(name) || !name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                continue;
            if (!name.Contains("PUBLIC", StringComparison.OrdinalIgnoreCase))
                continue;
            if (name.Contains("source", StringComparison.OrdinalIgnoreCase))
                continue;
            if (!name.StartsWith("ghidra_", StringComparison.OrdinalIgnoreCase))
                continue;
            if (!a.TryGetProperty("browser_download_url", out var urlEl))
                continue;
            var url = urlEl.GetString();
            if (string.IsNullOrEmpty(url))
                continue;
            var size = a.TryGetProperty("size", out var sz) ? sz.GetInt64() : 0;
            if (size > bestSize)
            {
                bestSize = size;
                bestUrl = url;
                bestName = name;
            }
        }

        return (bestUrl, bestName);
    }

    // --- Transfere ficheiro com progresso ---
    private static async Task DownloadFileWithProgressAsync(
        HttpClient http,
        string url,
        string destPath,
        Action<string> log,
        CancellationToken ct)
    {
        using var resp = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var total = resp.Content.Headers.ContentLength ?? -1;
        await using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        await using var fs = File.Create(destPath);
        var buffer = new byte[81920];
        long readTotal = 0;
        var lastPct = -1;
        int read;
        while ((read = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), ct).ConfigureAwait(false)) > 0)
        {
            await fs.WriteAsync(buffer.AsMemory(0, read), ct).ConfigureAwait(false);
            readTotal += read;
            if (total <= 0)
                continue;
            var pct = (int)(readTotal * 100 / total);
            if (pct != lastPct && pct % 5 == 0)
            {
                lastPct = pct;
                log($"[INFO] Ghidra: transferência {pct}% ({readTotal / 1024 / 1024} / {total / 1024 / 1024} MB)");
            }
        }
    }
}
