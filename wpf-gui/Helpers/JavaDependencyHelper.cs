using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;

using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.Helpers;

/// <summary>
/// Oferece instalação do JDK 21 (Ghidra 12 / PyGhidra) via <c>winget</c>, no mesmo espírito que
/// <see cref="IlSpyDependencyHelper"/> e <see cref="GhidraDependencyHelper"/>.
/// </summary>
internal static class JavaDependencyHelper
{
    /// <summary>
    /// JDK em disco ou nas variáveis de ambiente (Process/User/Machine), para o uvicorn herdar
    /// <c>JAVA_HOME</c> mesmo quando o processo WPF arrancou antes da instalação do JDK.
    /// </summary>
    internal static string? ResolveJavaHomeForBackend()
    {
        foreach (var target in new[]
                     { EnvironmentVariableTarget.Process, EnvironmentVariableTarget.User, EnvironmentVariableTarget.Machine })
        {
            var raw = Environment.GetEnvironmentVariable("JAVA_HOME", target);
            if (TryNormalizeExistingJavaHome(raw, out var norm))
                return norm;
        }

        var disk = FindTemurin21JdkHome();
        if (TryNormalizeExistingJavaHome(disk, out var fromDisk))
            return fromDisk;

        return null;
    }

    private static bool TryNormalizeExistingJavaHome(string? raw, out string normalized)
    {
        normalized = "";
        if (string.IsNullOrWhiteSpace(raw))
            return false;
        var trimmed = raw.Trim();
        if (!Directory.Exists(trimmed))
            return false;
        var javaExe = Path.Combine(trimmed, "bin", "java.exe");
        if (!File.Exists(javaExe))
            return false;
        normalized = Path.GetFullPath(trimmed);
        return true;
    }

    /// <summary>Ghidra 12.x documenta JDK 21 (64-bit).</summary>
    private const int MinimumJdkMajor = 21;

    private const string WingetPackageId = "EclipseAdoptium.Temurin.21.JDK";

    private const string ManualDownloadUrl = "https://adoptium.net/temurin/releases/?version=21";

    /// <summary>
    /// Se já existir <c>java</c> no PATH com major ≥ 21, regista no log. Caso contrário pergunta ao
    /// utilizador e tenta <c>winget install EclipseAdoptium.Temurin.21.JDK</c>.
    /// </summary>
    public static async Task TryOfferInstallIfMissingAsync(Action<string> log, CancellationToken ct)
    {
        var probe = await ProbeJdkAsync(ct).ConfigureAwait(false);
        if (probe.Ok && probe.MajorVersion >= MinimumJdkMajor)
        {
            VerifyJavaIntegrityIfConfigured(log);
            log($"[OK] Java (JDK {probe.MajorVersion}+): {probe.VersionLine}");
            if (!string.IsNullOrEmpty(probe.JavaHomeFromEnv))
                log($"[INFO] JAVA_HOME: {probe.JavaHomeFromEnv}");
            return;
        }

        var raw = Environment.GetEnvironmentVariable("JAVA_HOME");
        if (!string.IsNullOrWhiteSpace(raw) && !Directory.Exists(raw.Trim()))
            log("[AVISO] JAVA_HOME está definido mas a pasta não existe: " + raw.Trim());
        else if (string.IsNullOrWhiteSpace(raw))
            log("[INFO] JAVA_HOME não definido (opcional se java estiver no PATH).");

        if (probe.Ok && probe.MajorVersion > 0 && probe.MajorVersion < MinimumJdkMajor)
        {
            log($"[AVISO] JDK detetado é {probe.MajorVersion}; Ghidra 12 requer JDK {MinimumJdkMajor}+. " +
                "É recomendável instalar JDK 21 em paralelo (Temurin).");
        }
        else if (!probe.Ok)
        {
            log($"[INFO] JDK {MinimumJdkMajor}+ não encontrado no PATH (necessário para Ghidra / pseudo-C).");
        }

        var app = Application.Current;
        if (app?.Dispatcher == null)
        {
            log("[INFO] Java em falta — sem janela principal para confirmar a instalação; " +
                "instale JDK 21 manualmente ou defina JAVA_HOME. " + ManualDownloadUrl);
            return;
        }

        if (!await IsWingetAvailableAsync(ct).ConfigureAwait(false))
        {
            log("[AVISO] winget não disponível — não é possível instalar o JDK automaticamente. " +
                "Instale JDK 21 a partir de: " + ManualDownloadUrl);
            return;
        }

        var confirm = await app.Dispatcher.InvokeAsync(() =>
            MessageBox.Show(
                "Não foi encontrado JDK 21 (Java) no sistema ou no PATH.\n\n" +
                "O Ghidra 12 e o PyGhidra precisam de um JDK 21 de 64 bits.\n\n" +
                "Deseja instalar automaticamente o Eclipse Temurin JDK 21 com o winget?\n\n" +
                "• Pode pedir elevação (UAC)\n" +
                "• Ligação à Internet necessária\n" +
                "• Pacote: " + WingetPackageId + "\n\n" +
                "Alternativa: instale manualmente a partir de\n" + ManualDownloadUrl,
                "Instalar Java (JDK 21)",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes);

        if (!confirm)
        {
            log("[INFO] Instalação automática do JDK cancelada.");
            return;
        }

        try
        {
            await InstallTemurin21ViaWingetAsync(log, ct).ConfigureAwait(false);
            TrySetJavaHomeFromDisk(log);

            probe = await ProbeJdkAsync(ct).ConfigureAwait(false);
            if (!probe.Ok || probe.MajorVersion < MinimumJdkMajor)
                throw new InvalidOperationException(
                    "JDK 21 ainda não ficou disponível após a instalação. " +
                    "Reinicie o terminal ou o PC e confirme: java -version");

            VerifyJavaIntegrityIfConfigured(log);
            log($"[OK] Java após instalação: {probe.VersionLine}");

            Application.Current?.Dispatcher.Invoke(() =>
                MessageBox.Show(
                    "JDK 21 configurado.\n\n" +
                    "JAVA_HOME foi definido para o utilizador se a instalação foi detetada em " +
                    "Program Files\\Eclipse Adoptium.\n\n" +
                    "Se o backend Python já estiver em execução, reinicie-o para aplicar JAVA_HOME.",
                    "Java",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information));
        }
        catch (Exception ex)
        {
            log($"[ERRO] Java JDK: {ex.Message}");
            await app.Dispatcher.InvokeAsync(() =>
                MessageBox.Show(
                    "Não foi possível instalar o JDK automaticamente.\n\n" + ex.Message + "\n\n" +
                    "Instale manualmente JDK 21:\n" + ManualDownloadUrl,
                    "Erro — Java",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning));
        }
    }

    private sealed record JdkProbe(bool Ok, int MajorVersion, string VersionLine, string? JavaHomeFromEnv);

    private static void VerifyJavaIntegrityIfConfigured(Action<string> log)
    {
        var javaExe = GetResolvedJavaExePath();
        if (string.IsNullOrEmpty(javaExe))
            return;

        DownloadIntegrity.LogAndVerifyOptionalEnvSha256(
            javaExe,
            DownloadIntegrity.JavaExeSha256Env,
            log,
            "Java (java.exe)");
    }

    private static string? GetResolvedJavaExePath()
    {
        foreach (var candidate in EnumerateJavaExeCandidates())
        {
            if (File.Exists(candidate))
                return Path.GetFullPath(candidate);
        }

        return null;
    }

    private static async Task<JdkProbe> ProbeJdkAsync(CancellationToken ct)
    {
        return await Task.Run(() =>
        {
            JdkProbe? best = null;
            foreach (var candidate in EnumerateJavaExeCandidates())
            {
                ct.ThrowIfCancellationRequested();
                var p = TryProbeJavaExe(candidate, ct);
                if (p.MajorVersion >= MinimumJdkMajor)
                    return p;
                if (best == null || p.MajorVersion > best.MajorVersion)
                    best = p;
            }

            return best ?? new JdkProbe(false, 0, "", Environment.GetEnvironmentVariable("JAVA_HOME"));
        }, ct).ConfigureAwait(false);
    }

    private static IEnumerable<string> EnumerateJavaExeCandidates()
    {
        yield return "java";

        foreach (var target in new[]
                     { EnvironmentVariableTarget.Process, EnvironmentVariableTarget.User, EnvironmentVariableTarget.Machine })
        {
            var jh = Environment.GetEnvironmentVariable("JAVA_HOME", target);
            if (string.IsNullOrWhiteSpace(jh))
                continue;
            var exe = Path.Combine(jh.Trim(), "bin", "java.exe");
            if (File.Exists(exe))
                yield return exe;
        }

        var disk = FindTemurin21JdkHome();
        if (!string.IsNullOrEmpty(disk))
        {
            var exe = Path.Combine(disk, "bin", "java.exe");
            if (File.Exists(exe))
                yield return exe;
        }
    }

    private static JdkProbe TryProbeJavaExe(string fileNameOrCommand, CancellationToken ct)
    {
        try
        {
            var psi = new ProcessStartInfo
            {
                FileName = fileNameOrCommand,
                Arguments = "-version",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            ProcessOutputEncoding.ApplyConsole(psi);
            if (File.Exists(fileNameOrCommand))
                psi.FileName = Path.GetFullPath(fileNameOrCommand);

            using var proc = Process.Start(psi);
            if (proc is null)
                return new JdkProbe(false, 0, "", Environment.GetEnvironmentVariable("JAVA_HOME"));

            var stdout = proc.StandardOutput.ReadToEnd();
            var stderr = proc.StandardError.ReadToEnd();
            proc.WaitForExit(30_000);
            ct.ThrowIfCancellationRequested();

            var combined = stdout + stderr;
            var major = ParseJavaMajor(combined);
            var oneLine = string.Join(" ", combined.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries));
            if (oneLine.Length > 160)
                oneLine = oneLine[..160] + "…";

            return new JdkProbe(major > 0, major, string.IsNullOrEmpty(oneLine) ? "(sem saída)" : oneLine,
                Environment.GetEnvironmentVariable("JAVA_HOME"));
        }
        catch
        {
            return new JdkProbe(false, 0, "", Environment.GetEnvironmentVariable("JAVA_HOME"));
        }
    }

    private static int ParseJavaMajor(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return 0;

        // openjdk version "21.0.5" / java version "1.8.0_391"
        var m = Regex.Match(
            text,
            @"version\s+""(?<a>\d+)\.(?<b>\d+)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        if (!m.Success)
            return 0;

        var a = int.Parse(m.Groups["a"].Value, System.Globalization.CultureInfo.InvariantCulture);
        if (a == 1)
            return int.Parse(m.Groups["b"].Value, System.Globalization.CultureInfo.InvariantCulture);
        return a;
    }

    private static async Task<bool> IsWingetAvailableAsync(CancellationToken ct)
    {
        return await Task.Run(() =>
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "winget",
                    Arguments = "--version",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using var proc = Process.Start(psi);
                if (proc is null)
                    return false;
                proc.WaitForExit(20_000);
                ct.ThrowIfCancellationRequested();
                return proc.ExitCode == 0;
            }
            catch
            {
                return false;
            }
        }, ct).ConfigureAwait(false);
    }

    private static async Task InstallTemurin21ViaWingetAsync(Action<string> log, CancellationToken ct)
    {
        log("[INFO] Java: winget install " + WingetPackageId + " ...");
        var args =
            "install --id " + WingetPackageId +
            " -e --accept-package-agreements --accept-source-agreements";

        var (code, stdout, stderr) = await RunProcessCaptureAsync("winget", args, ct).ConfigureAwait(false);
        var combined = stdout + stderr;
        if (code != 0 && !LooksLikeWingetAlreadyInstalled(combined))
            throw new InvalidOperationException(
                $"winget terminou com código {code}. Saída:\n{Truncate(combined, 900)}");

        log(code == 0
            ? "[OK] winget concluiu a instalação do Temurin JDK 21."
            : "[INFO] winget reporta pacote já presente ou equivalente.");
    }

    private static bool LooksLikeWingetAlreadyInstalled(string output)
    {
        if (string.IsNullOrEmpty(output))
            return false;
        var lo = output.ToLowerInvariant();
        return lo.Contains("already installed", StringComparison.Ordinal)
               || lo.Contains("já está instalado", StringComparison.Ordinal)
               || lo.Contains("no newer package", StringComparison.Ordinal)
               || lo.Contains("no applicable upgrade", StringComparison.Ordinal);
    }

    private static void TrySetJavaHomeFromDisk(Action<string> log)
    {
        var home = FindTemurin21JdkHome();
        if (string.IsNullOrEmpty(home))
        {
            log("[AVISO] Java: não foi possível localizar automaticamente a pasta do JDK após winget " +
                "(procure jdk-21 em Program Files\\Eclipse Adoptium).");
            return;
        }

        Environment.SetEnvironmentVariable("JAVA_HOME", home, EnvironmentVariableTarget.User);
        Environment.SetEnvironmentVariable("JAVA_HOME", home, EnvironmentVariableTarget.Process);
        log($"[OK] JAVA_HOME definido para: {home}");
        log("[INFO] JAVA_HOME aplicado ao utilizador e a esta sessão.");
    }

    private static string? FindTemurin21JdkHome()
    {
        var adoptium = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            "Eclipse Adoptium");
        if (!Directory.Exists(adoptium))
            return null;

        try
        {
            var dirs = Directory.GetDirectories(adoptium, "jdk-21*", SearchOption.TopDirectoryOnly)
                .Where(d => File.Exists(Path.Combine(d, "bin", "java.exe")))
                .OrderByDescending(d => d, StringComparer.OrdinalIgnoreCase)
                .ToList();
            return dirs.Count > 0 ? dirs[0] : null;
        }
        catch
        {
            return null;
        }
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
            proc.WaitForExit(600_000);
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
