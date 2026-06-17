using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.Helpers;

/// <summary>
/// Oferece instalação guiada do ILSpy CLI (<c>ilspycmd</c>) quando <c>ILSPY_CMD_PATH</c> / PATH
/// não resolvem para um executável válido — mesmo fluxo que <see cref="GhidraDependencyHelper"/>.
/// </summary>
internal static class IlSpyDependencyHelper
{
    private const string ManualInstallUrl = "https://www.nuget.org/packages/ilspycmd";

    /// <summary>Página oficial do runtime .NET 6 (necessário apenas para ilspycmd 8.x / alguns 9.x).</summary>
    private const string DotNet6RuntimeDownloadUrl = "https://dotnet.microsoft.com/download/dotnet/6.0";

    /// <summary>
    /// Versões do pacote NuGet <c>ilspycmd</c> por ordem. 10.x costuma alinhar com .NET 8 — evita exigir o runtime .NET 6
    /// em separado (comum quando só existe SDK 8). 8.2.x é .NET 6; só usar se versões mais novas falharem no NuGet/SDK.
    /// </summary>
    private static readonly string[] IlSpyCmdPreferredVersions =
    [
        "10.0.0.8330",
        "9.1.0.7988",
        "8.2.0.7535",
    ];

    /// <summary>
    /// Resolve um executável ilspycmd utilizável (variável de ambiente, pasta de tools globais .NET, PATH).
    /// </summary>
    public static async Task<string?> GetEffectiveIlSpyExecutableAsync(CancellationToken ct = default)
    {
        var probe = await ProbeIlSpyAsync(ct).ConfigureAwait(false);
        return probe.Working ? probe.ExecutablePath : null;
    }

    /// <summary>
    /// Se já existir ILSpy CLI válido, regista no log. Caso contrário pergunta ao utilizador e tenta instalar.
    /// </summary>
    public static async Task TryOfferInstallIfMissingAsync(Action<string> log, CancellationToken ct)
    {
        var existing = await GetEffectiveIlSpyExecutableAsync(ct).ConfigureAwait(false);
        if (!string.IsNullOrEmpty(existing))
        {
            VerifyIlSpyIntegrityIfConfigured(existing, log);
            log($"[OK] ILSpy: {existing}");
            return;
        }

        var raw = Environment.GetEnvironmentVariable("ILSPY_CMD_PATH");
        if (!string.IsNullOrWhiteSpace(raw))
        {
            log("[AVISO] ILSPY_CMD_PATH está definido mas não aponta para um ilspycmd válido " +
                "(ficheiro em falta ou comando não executável).");
        }
        else
        {
            log("[INFO] ILSPY_CMD_PATH não definido (descompilação .NET para C# opcional).");
        }

        var app = Application.Current;
        if (app?.Dispatcher == null)
        {
            log("[INFO] ILSpy em falta — sem janela principal para confirmar a instalação; " +
                "defina ILSPY_CMD_PATH manualmente ou reabra o arranque pela interface.");
            return;
        }

        var confirm = await app.Dispatcher.InvokeAsync(() =>
            MessageBox.Show(
                "O ILSpy não foi encontrado (variável ILSPY_CMD_PATH / comando ilspycmd).\n\n" +
                "Para descompilar assemblies .NET para C# na análise estática, é necessário o ILSpy CLI.\n\n" +
                "Deseja instalar automaticamente a ferramenta global oficial via NuGet?\n\n" +
                "• Ligação à Internet necessária\n" +
                "• Transferência pequena (ferramenta dotnet)\n" +
                "• Normalmente conclui em menos de um minuto\n\n" +
                "Alternativa: execute manualmente «dotnet tool install -g ilspycmd --version " +
                IlSpyCmdPreferredVersions[0] + "» (alinhado com .NET 8) " +
                "ou defina ILSPY_CMD_PATH para ILSpyCmd.exe.",
                "Instalar ILSpy",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes);

        if (!confirm)
        {
            log("[INFO] Instalação automática do ILSpy cancelada.");
            return;
        }

        try
        {
            await InstallIlSpyAsync(log, ct).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            log($"[ERRO] ILSpy: {ex.Message}");
            await app.Dispatcher.InvokeAsync(() =>
                MessageBox.Show(
                    "Não foi possível instalar o ILSpy automaticamente.\n\n" + ex.Message + "\n\n" +
                    "Instale manualmente (versão recomendada, .NET 8):\n" +
                    "  dotnet tool install -g ilspycmd --version " + IlSpyCmdPreferredVersions[0] + "\n\n" +
                    "Se o erro persistir, limpe a cache NuGet e repita:\n" +
                    "  dotnet nuget locals http-cache --clear\n\n" +
                    "Pacote NuGet:\n" + ManualInstallUrl,
                    "Erro — ILSpy",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning));
        }
    }

    private sealed record ProbeResult(bool Working, string? ExecutablePath);

    private static void VerifyIlSpyIntegrityIfConfigured(string exePath, Action<string> log)
    {
        var resolved = ResolveAbsoluteIlSpyPath(exePath);
        if (string.IsNullOrEmpty(resolved) || !File.Exists(resolved))
            return;

        DownloadIntegrity.LogAndVerifyOptionalEnvSha256(
            resolved,
            DownloadIntegrity.IlSpySha256Env,
            log,
            "ILSpy (ilspycmd)");
    }

    private static async Task InstallIlSpyAsync(Action<string> log, CancellationToken ct)
    {
        if (!await IsDotNetSdkAvailableAsync(ct).ConfigureAwait(false))
            throw new InvalidOperationException(
                "SDK .NET não encontrado. Instale o .NET SDK para poder executar «dotnet tool install -g ilspycmd».");

        log("[INFO] ILSpy: a instalar via dotnet tool (NuGet)...");
        await RunDotNetToolInstallOrUpdateAsync(log, ct).ConfigureAwait(false);

        await EnsureIlSpyShimFileExistsAsync(log, ct).ConfigureAwait(false);

        await WaitForIlSpyShimFileAsync(ct).ConfigureAwait(false);

        var probe = await ProbeIlSpyAsync(ct).ConfigureAwait(false);
        var exe = probe.Working ? ResolveAbsoluteIlSpyPath(probe.ExecutablePath) : null;
        if (string.IsNullOrEmpty(exe) || !File.Exists(exe))
            exe = FindIlSpyShimOnDisk();

        if (string.IsNullOrEmpty(exe) || !File.Exists(exe))
            throw new InvalidOperationException(
                BuildPostInstallFailureHint());

        if (!await IlSpyExecutableRespondsAsync(exe, ct).ConfigureAwait(false))
        {
            log("[AVISO] ILSpy: ilspycmd não respondeu com streams redireccionados (limitação comum do apphost). " +
                "A usar na mesma o shim criado pelo dotnet em:\n  " + exe);
        }

        VerifyIlSpyIntegrityIfConfigured(exe, log);

        Environment.SetEnvironmentVariable("ILSPY_CMD_PATH", exe, EnvironmentVariableTarget.User);
        Environment.SetEnvironmentVariable("ILSPY_CMD_PATH", exe, EnvironmentVariableTarget.Process);

        log($"[OK] ILSpy instalado em: {exe}");
        log("[INFO] ILSPY_CMD_PATH definido para o utilizador e para esta sessão.");

        Application.Current?.Dispatcher.Invoke(() =>
            MessageBox.Show(
                "ILSpy instalado em:\n" + exe + "\n\n" +
                "A variável de utilizador ILSPY_CMD_PATH foi definida.\n\n" +
                "Se o backend Python já estiver em execução, reinicie-o para aplicar o novo caminho.",
                "ILSpy",
                MessageBoxButton.OK,
                MessageBoxImage.Information));
    }

    private static async Task<ProbeResult> ProbeIlSpyAsync(CancellationToken ct)
    {
        foreach (var target in new[]
                     { EnvironmentVariableTarget.Process, EnvironmentVariableTarget.User, EnvironmentVariableTarget.Machine })
        {
            ct.ThrowIfCancellationRequested();
            var v = Environment.GetEnvironmentVariable("ILSPY_CMD_PATH", target);
            if (string.IsNullOrWhiteSpace(v))
                continue;
            var trim = v.Trim();
            if (!File.Exists(trim))
                continue;
            if (await IlSpyExecutableRespondsAsync(trim, ct).ConfigureAwait(false))
                return new ProbeResult(true, trim);
            return new ProbeResult(true, trim);
        }

        var userTool = GetDotNetGlobalIlSpyCmdPath();
        if (File.Exists(userTool))
        {
            if (await IlSpyExecutableRespondsAsync(userTool, ct).ConfigureAwait(false))
                return new ProbeResult(true, userTool);
            return new ProbeResult(true, userTool);
        }

        var wherePath = await TryFindIlSpyWithWhereAsync(ct).ConfigureAwait(false);
        if (!string.IsNullOrEmpty(wherePath) && File.Exists(wherePath))
        {
            if (await IlSpyExecutableRespondsAsync(wherePath, ct).ConfigureAwait(false))
                return new ProbeResult(true, wherePath);
            return new ProbeResult(true, wherePath);
        }

        if (await IlSpyExecutableRespondsAsync("ilspycmd", ct).ConfigureAwait(false))
        {
            var again = await TryFindIlSpyWithWhereAsync(ct).ConfigureAwait(false);
            if (!string.IsNullOrEmpty(again))
                return new ProbeResult(true, again);
            var globalExe = GetDotNetGlobalIlSpyCmdPath();
            if (File.Exists(globalExe))
                return new ProbeResult(true, globalExe);
        }

        return new ProbeResult(false, null);
    }

    /// <summary>
    /// Localiza o shim após <c>dotnet tool install</c> (nome fixo ou pesquisa na pasta tools).
    /// </summary>
    private static string? FindIlSpyShimOnDisk()
    {
        var expected = GetDotNetGlobalIlSpyCmdPath();
        if (File.Exists(expected))
            return Path.GetFullPath(expected);

        var toolsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".dotnet", "tools");
        if (!Directory.Exists(toolsDir))
            return null;

        try
        {
            foreach (var path in Directory.EnumerateFiles(toolsDir, "ilspycmd.exe", SearchOption.TopDirectoryOnly))
                return Path.GetFullPath(path);
        }
        catch { /* ignorar */ }

        return null;
    }

    private static string GetDotNetGlobalIlSpyCmdPath()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".dotnet", "tools", "ilspycmd.exe");
    }

    /// <summary>
    /// O arranque do WPF herda frequentemente um PATH sem «%USERPROFILE%\.dotnet\tools», onde o dotnet coloca o shim.
    /// </summary>
    private static void EnsureDotNetGlobalToolsOnPath(ProcessStartInfo psi)
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

    private static async Task WaitForIlSpyShimFileAsync(CancellationToken ct)
    {
        var p = GetDotNetGlobalIlSpyCmdPath();
        for (var i = 0; i < 40; i++)
        {
            ct.ThrowIfCancellationRequested();
            if (File.Exists(p))
                return;
            await Task.Delay(100, ct).ConfigureAwait(false);
        }
    }

    /// <summary>
    /// O dotnet pode responder «already installed» com registo NuGet inconsistente — sem <c>ilspycmd.exe</c> na pasta de tools.
    /// Força desinstalar + limpar cache + reinstalar com versão pinada até o shim existir.
    /// </summary>
    private static async Task EnsureIlSpyShimFileExistsAsync(Action<string> log, CancellationToken ct)
    {
        var shim = GetDotNetGlobalIlSpyCmdPath();
        if (File.Exists(shim))
            return;

        log("[AVISO] ILSpy: shim ilspycmd.exe em falta em «.dotnet\\tools» apesar do dotnet tool — a reparar.");

        for (var attempt = 0; attempt < 2; attempt++)
        {
            ct.ThrowIfCancellationRequested();
            if (attempt > 0)
            {
                log("[INFO] ILSpy: a limpar cache HTTP NuGet e a repetir a instalação...");
                await RunProcessCaptureAsync("dotnet", "nuget locals http-cache --clear", ct).ConfigureAwait(false);
            }

            await TryUninstallIlSpyCmdGlobalAsync(log, ct).ConfigureAwait(false);

            var pin = IlSpyCmdPreferredVersions[0];
            log($"[INFO] ILSpy: dotnet tool install -g ilspycmd --version {pin} (reparação)...");
            var (code, stdout, stderr) = await RunProcessCaptureAsync(
                "dotnet", $"tool install -g ilspycmd --version {pin}", ct).ConfigureAwait(false);

            if (code != 0 && LooksLikeToolAlreadyInstalled(stdout + stderr))
            {
                log("[INFO] dotnet ainda reporta ferramenta instalada — a desinstalar novamente...");
                await TryUninstallIlSpyCmdGlobalAsync(log, ct).ConfigureAwait(false);
                (code, stdout, stderr) = await RunProcessCaptureAsync(
                    "dotnet", $"tool install -g ilspycmd --version {pin}", ct).ConfigureAwait(false);
            }

            if (code != 0)
                log($"[AVISO] Reparação tentativa {attempt + 1}: código {code}: {Truncate(stdout + stderr, 320)}");

            await WaitForIlSpyShimFileAsync(ct).ConfigureAwait(false);
            if (File.Exists(shim))
            {
                log("[OK] ILSpy: shim ilspycmd.exe criado após reparação.");
                return;
            }
        }

        var listed = await DotNetToolListContainsIlSpyCmdAsync(ct).ConfigureAwait(false);
        throw new InvalidOperationException(
            "O dotnet não criou «" + shim + "».\n\n" +
            "Estado detetado: ilspycmd " + (listed ? "aparece em dotnet tool list -g" : "não aparece em dotnet tool list -g") + ".\n\n" +
            "Execute num terminal (PowerShell):\n" +
            "  dotnet tool uninstall -g ilspycmd\n" +
            "  dotnet nuget locals http-cache --clear\n" +
            "  dotnet tool install -g ilspycmd --version " + IlSpyCmdPreferredVersions[0]);
    }

    private static async Task<bool> DotNetToolListContainsIlSpyCmdAsync(CancellationToken ct)
    {
        var (code, stdout, _) = await RunProcessCaptureAsync("dotnet", "tool list -g", ct).ConfigureAwait(false);
        if (code != 0)
            return false;
        return stdout.Contains("ilspycmd", StringComparison.OrdinalIgnoreCase);
    }

    private static async Task<string?> TryFindIlSpyWithWhereAsync(CancellationToken ct)
    {
        return await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "where.exe",
                    Arguments = "ilspycmd",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                ProcessOutputEncoding.ApplyConsole(psi);
                EnsureDotNetGlobalToolsOnPath(psi);
                using var proc = Process.Start(psi);
                if (proc is null)
                    return null;
                var stdout = proc.StandardOutput.ReadToEnd();
                proc.WaitForExit(15_000);
                ct.ThrowIfCancellationRequested();
                if (proc.ExitCode != 0)
                    return null;
                string? line = null;
                foreach (var part in stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    line = part.Trim();
                    break;
                }

                if (string.IsNullOrWhiteSpace(line))
                    return null;
                return File.Exists(line) ? line : null;
            }
            catch
            {
                return null;
            }
        }, ct).ConfigureAwait(false);
    }

    /// <summary>
    /// Nunca devolver só «ilspycmd» para ILSPY_CMD_PATH — o backend Python espera caminho absoluto se existir.
    /// </summary>
    private static string? ResolveAbsoluteIlSpyPath(string? probePath)
    {
        if (string.IsNullOrWhiteSpace(probePath))
            return null;
        var t = probePath.Trim();
        if (File.Exists(t))
            return Path.GetFullPath(t);

        var globalExe = GetDotNetGlobalIlSpyCmdPath();
        return File.Exists(globalExe) ? globalExe : null;
    }

    private static string BuildPostInstallFailureHint()
    {
        return
            "O dotnet não criou o shim ilspycmd.exe na pasta de ferramentas globais.\n\n" +
            "Confirme num terminal:\n" +
            "  dotnet tool list -g\n" +
            "  dir \"%USERPROFILE%\\.dotnet\\tools\\ilspycmd.exe\"\n\n" +
            "Instalação limpa sugerida:\n" +
            "  dotnet tool uninstall -g ilspycmd\n" +
            "  dotnet tool install -g ilspycmd --version " + IlSpyCmdPreferredVersions[0] + "\n\n" +
            "Se precisar da série 8.x do ilspycmd, instale também o runtime .NET 6 (x64):\n  " +
            DotNet6RuntimeDownloadUrl + "\n\n" +
            "Depois defina ILSPY_CMD_PATH para:\n  " + GetDotNetGlobalIlSpyCmdPath();
    }

    /// <summary>
    /// Confirma que o executável arranca; algumas versões tratam --version de forma inconsistente.
    /// </summary>
    private static async Task<bool> IlSpyExecutableRespondsAsync(string fileNameOrCommand, CancellationToken ct)
    {
        foreach (var args in new[] { "--version", "--help", "-?" })
        {
            if (await RunIlSpyProbeOnceAsync(fileNameOrCommand, args, ct).ConfigureAwait(false))
                return true;
        }

        return false;
    }

    private static async Task<bool> RunIlSpyProbeOnceAsync(string fileNameOrCommand, string arguments, CancellationToken ct)
    {
        return await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = fileNameOrCommand,
                    Arguments = arguments,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                ProcessOutputEncoding.ApplyConsole(psi);
                if (File.Exists(fileNameOrCommand))
                    psi.FileName = Path.GetFullPath(fileNameOrCommand);
                EnsureDotNetGlobalToolsOnPath(psi);

                using var proc = Process.Start(psi);
                if (proc is null)
                    return false;
                var stdout = ProcessOutputEncoding.NormalizeForDisplay(proc.StandardOutput.ReadToEnd());
                var stderr = ProcessOutputEncoding.NormalizeForDisplay(proc.StandardError.ReadToEnd());
                proc.WaitForExit(60_000);
                ct.ThrowIfCancellationRequested();
                if (proc.ExitCode == 0)
                    return true;
                var combined = (stdout + stderr).Trim();
                if (combined.Length >= 8 &&
                    (combined.Contains("ILSpy", StringComparison.OrdinalIgnoreCase) ||
                     combined.Contains("ilspycmd", StringComparison.OrdinalIgnoreCase)))
                    return true;
                return false;
            }
            catch
            {
                return false;
            }
        }, ct).ConfigureAwait(false);
    }

    private static async Task<bool> IsDotNetSdkAvailableAsync(CancellationToken ct)
    {
        return await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "dotnet",
                    Arguments = "--version",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using var proc = Process.Start(psi);
                if (proc is null)
                    return false;
                proc.WaitForExit(30_000);
                ct.ThrowIfCancellationRequested();
                return proc.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }, ct).ConfigureAwait(false);
    }

    private static async Task RunDotNetToolInstallOrUpdateAsync(Action<string> log, CancellationToken ct)
    {
        foreach (var ver in IlSpyCmdPreferredVersions)
        {
            ct.ThrowIfCancellationRequested();
            log($"[INFO] ILSpy: dotnet tool install -g ilspycmd --version {ver} ...");
            var (code, stdout, stderr) = await RunProcessCaptureAsync(
                "dotnet", $"tool install -g ilspycmd --version {ver}", ct).ConfigureAwait(false);
            var combined = stdout + stderr;

            if (code == 0)
            {
                log($"[OK] ilspycmd {ver} instalado com dotnet tool.");
                return;
            }

            if (LooksLikeToolAlreadyInstalled(combined))
            {
                log("[INFO] dotnet reporta ilspycmd já instalado.");
                if (File.Exists(GetDotNetGlobalIlSpyCmdPath()))
                {
                    log("[OK] Shim ilspycmd.exe encontrado em .dotnet\\tools.");
                    return;
                }

                log("[AVISO] «already installed» mas sem ilspycmd.exe — a desinstalar e a reinstalar esta versão...");
                await TryUninstallIlSpyCmdGlobalAsync(log, ct).ConfigureAwait(false);
                (code, stdout, stderr) = await RunProcessCaptureAsync(
                    "dotnet", $"tool install -g ilspycmd --version {ver}", ct).ConfigureAwait(false);
                combined = stdout + stderr;
                if (code == 0 && File.Exists(GetDotNetGlobalIlSpyCmdPath()))
                {
                    log($"[OK] ilspycmd {ver} reinstalado; shim presente.");
                    return;
                }

                log($"[AVISO] Reinstalação após «already installed» falhou ou shim ausente: {Truncate(combined, 280)}");
                continue;
            }

            if (IsNuGetToolManifestBroken(combined))
            {
                log("[AVISO] Pacote ilspycmd rejeitado pelo SDK (ex.: DotnetToolSettings.xml em falta). " +
                    "A remover ferramenta global e a repetir esta versão...");
                await TryUninstallIlSpyCmdGlobalAsync(log, ct).ConfigureAwait(false);

                (code, stdout, stderr) = await RunProcessCaptureAsync(
                    "dotnet", $"tool install -g ilspycmd --version {ver}", ct).ConfigureAwait(false);
                combined = stdout + stderr;
                if (code == 0)
                {
                    log($"[OK] ilspycmd {ver} instalado após limpeza da ferramenta global.");
                    return;
                }

                log($"[AVISO] Versão {ver} continua a falhar após limpeza: {Truncate(combined, 360)}");
                continue;
            }

            log($"[AVISO] Falha na versão {ver} (código {code}): {Truncate(combined, 380)}");
        }

        log("[INFO] ILSpy: último recurso — dotnet tool install -g ilspycmd (sem versão fixa)...");
        var (lastCode, lastOut, lastErr) = await RunProcessCaptureAsync(
            "dotnet", "tool install -g ilspycmd", ct).ConfigureAwait(false);
        var lastCombined = lastOut + lastErr;
        if (lastCode == 0)
        {
            log("[OK] dotnet tool install -g ilspycmd concluído (sem pin de versão).");
            return;
        }

        if (LooksLikeToolAlreadyInstalled(lastCombined))
        {
            log("[INFO] dotnet reporta ilspycmd já instalado (instalação sem versão fixa).");
            if (File.Exists(GetDotNetGlobalIlSpyCmdPath()))
            {
                log("[OK] Shim ilspycmd.exe encontrado.");
                return;
            }

            log("[AVISO] Shim ausente após «already installed» — continuação para update...");
        }

        var pin = IlSpyCmdPreferredVersions[0];
        log($"[INFO] ILSpy: dotnet tool update -g ilspycmd --version {pin} ...");
        var (upCode, upOut, upErr) = await RunProcessCaptureAsync(
            "dotnet", $"tool update -g ilspycmd --version {pin}", ct).ConfigureAwait(false);
        if (upCode == 0)
        {
            log($"[OK] dotnet tool update -g ilspycmd --version {pin} concluído.");
            return;
        }

        throw new InvalidOperationException(
            "dotnet tool não conseguiu instalar ilspycmd (várias versões testadas).\n\n" +
            $"Últimos erros:\n{Truncate(lastCombined + upOut + upErr, 520)}\n\n" +
            "Tente manualmente:\n" +
            $"  dotnet nuget locals http-cache --clear\n" +
            $"  dotnet tool install -g ilspycmd --version {pin}");
    }

    private static bool IsNuGetToolManifestBroken(string stderrOut)
    {
        if (string.IsNullOrEmpty(stderrOut))
            return false;
        var s = stderrOut;
        return s.Contains("DotnetToolSettings.xml", StringComparison.OrdinalIgnoreCase)
               || (s.Contains("settings file", StringComparison.OrdinalIgnoreCase)
                   && s.Contains("invalid", StringComparison.OrdinalIgnoreCase));
    }

    private static bool LooksLikeToolAlreadyInstalled(string output)
    {
        if (string.IsNullOrEmpty(output))
            return false;
        var lo = output.ToLowerInvariant();
        return lo.Contains("already installed", StringComparison.Ordinal)
               || lo.Contains("is already installed", StringComparison.Ordinal)
               || lo.Contains("já está instalado", StringComparison.Ordinal)
               || lo.Contains("already has", StringComparison.Ordinal);
    }

    private static async Task TryUninstallIlSpyCmdGlobalAsync(Action<string> log, CancellationToken ct)
    {
        var (code, _, _) = await RunProcessCaptureAsync("dotnet", "tool uninstall -g ilspycmd", ct).ConfigureAwait(false);
        if (code == 0)
            log("[INFO] ILSpy: removida a ferramenta global ilspycmd (reinstalação limpa).");
    }

    private static async Task<(int ExitCode, string StdOut, string StdErr)> RunProcessCaptureAsync(
        string fileName,
        string arguments,
        CancellationToken ct)
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
            proc.WaitForExit(300_000);
            ct.ThrowIfCancellationRequested();
            return (proc.ExitCode, stdout, stderr);
        }, ct).ConfigureAwait(false);
    }

    private static string Truncate(string s, int max)
    {
        if (string.IsNullOrEmpty(s))
            return "";
        s = s.Trim();
        return s.Length <= max ? s : s[..max] + "…";
    }
}
