using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

using RatAnalyzer.Desktop.Infrastructure;

namespace RatAnalyzer.Desktop.Services;

public sealed record SetupPreflight(string VmName, bool VmExists, string VhdPath, bool VhdExists);

public sealed record RunPreflight(
    string VmName,
    bool VmExists,
    string SnapshotName,
    bool SnapshotExists,
    string IsoPath,
    bool IsoExists);

/// <summary>Execução PowerShell e preflight Hyper-V (sem dependências WPF).</summary>
public static class VmSandboxService
{
    public static string? FindHyperVScriptsPath()
    {
        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var dir = new DirectoryInfo(baseDir);
        for (var i = 0; i < 8 && dir != null; i++)
        {
            var scripts = Path.Combine(dir.FullName, "scripts", "hyperv-sandbox");
            if (Directory.Exists(scripts))
                return scripts;
            dir = dir.Parent;
        }

        return null;
    }

    public static async Task<int> RunScriptAsync(
        string scriptPath,
        IReadOnlyList<string>? extraArgs,
        Action<string> onLine,
        CancellationToken cancellationToken,
        VmGuestCredentials? guestCredentials = null)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? "",
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        ProcessOutputEncoding.ApplyWindowsAnsi(psi);
        ApplyGuestCredentials(psi, guestCredentials);
        psi.ArgumentList.Add("-NoLogo");
        psi.ArgumentList.Add("-NoProfile");
        psi.ArgumentList.Add("-NonInteractive");
        psi.ArgumentList.Add("-ExecutionPolicy");
        psi.ArgumentList.Add("Bypass");
        psi.ArgumentList.Add("-File");
        psi.ArgumentList.Add(scriptPath);
        if (extraArgs != null)
        {
            foreach (var arg in extraArgs)
                psi.ArgumentList.Add(arg);
        }

        using var process = new Process { StartInfo = psi, EnableRaisingEvents = true };

        process.OutputDataReceived += (_, e) =>
        {
            if (!string.IsNullOrEmpty(e.Data))
                onLine(ProcessOutputEncoding.NormalizeForDisplay(e.Data));
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (!string.IsNullOrEmpty(e.Data))
                onLine(ProcessOutputEncoding.NormalizeForDisplay("[stderr] " + e.Data));
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        await using var reg = cancellationToken.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                    process.Kill(true);
            }
            catch { /* ignorar */ }
        });

        try
        {
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            onLine("[*] Execução cancelada pelo utilizador.");
            throw;
        }

        return process.ExitCode;
    }

    public static string? TryReadRunStatus(string? runJsonPath)
    {
        if (string.IsNullOrWhiteSpace(runJsonPath) || !File.Exists(runJsonPath))
            return null;

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(runJsonPath));
            if (doc.RootElement.TryGetProperty("status", out var status))
                return status.GetString();
        }
        catch { /* ignorar */ }

        return null;
    }

    public static Task<RunPreflight?> GetRunPreflightAsync(string scriptsPath, CancellationToken ct, VmGuestCredentials? guestCredentials = null)
    {
        var configPath = Path.Combine(scriptsPath, "_Config.ps1");
        return RunPreflightQueryAsync<RunPreflight>(scriptsPath, BuildRunPreflightCommand(configPath), ct, guestCredentials);
    }

    public static Task<SetupPreflight?> GetSetupPreflightAsync(string scriptsPath, CancellationToken ct, VmGuestCredentials? guestCredentials = null)
    {
        var configPath = Path.Combine(scriptsPath, "_Config.ps1");
        return RunPreflightQueryAsync<SetupPreflight>(scriptsPath, BuildSetupPreflightCommand(configPath), ct, guestCredentials);
    }

    private static string BuildRunPreflightCommand(string configPath) =>
        "& { " +
        $"  . \"{configPath}\"; " +
        "  $vmName = $script:PROJETOVM_VMName; " +
        "  $snapName = $script:PROJETOVM_SnapshotName; " +
        "  $iso = $script:PROJETOVM_WindowsIsoPath; " +
        "  $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue; " +
        "  $snap = $null; if ($vm) { $snap = Get-VMSnapshot -VMName $vmName -Name $snapName -ErrorAction SilentlyContinue }; " +
        "  $obj = [pscustomobject]@{ VmName = $vmName; VmExists = [bool]$vm; SnapshotName = $snapName; SnapshotExists = [bool]$snap; IsoPath = $iso; IsoExists = (Test-Path -LiteralPath $iso) }; " +
        "  $obj | ConvertTo-Json -Compress " +
        "} ";

    private static string BuildSetupPreflightCommand(string configPath) =>
        "& { " +
        $"  . \"{configPath}\"; " +
        "  $vmName = $script:PROJETOVM_VMName; " +
        "  $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue; " +
        "  $vhdPath = Join-Path $script:PROJETOVM_VMPath \"Sandbox.vhdx\"; " +
        "  $obj = [pscustomobject]@{ VmName = $vmName; VmExists = [bool]$vm; VhdPath = $vhdPath; VhdExists = (Test-Path $vhdPath) }; " +
        "  $obj | ConvertTo-Json -Compress " +
        "} ";

    private static Task<T?> RunPreflightQueryAsync<T>(string scriptsPath, string command, CancellationToken ct, VmGuestCredentials? guestCredentials)
        where T : class
    {
        return Task.Run<T?>(() =>
        {
            try
            {
                var configPath = Path.Combine(scriptsPath, "_Config.ps1");
                if (!File.Exists(configPath))
                    return null;

                var psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = $"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {ToEncodedCommand(command)}",
                    WorkingDirectory = scriptsPath,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                };
                ProcessOutputEncoding.ApplyWindowsAnsi(psi);
                ApplyGuestCredentials(psi, guestCredentials);

                using var process = new Process { StartInfo = psi };
                process.Start();
                var stdout = process.StandardOutput.ReadToEnd();
                process.WaitForExit();
                if (process.ExitCode != 0)
                    return null;

                stdout = stdout?.Trim();
                if (string.IsNullOrWhiteSpace(stdout))
                    return null;

                return JsonSerializer.Deserialize<T>(stdout, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            }
            catch
            {
                return null;
            }
        }, ct);
    }

    private static string ToEncodedCommand(string command)
    {
        var bytes = Encoding.Unicode.GetBytes(command);
        return Convert.ToBase64String(bytes);
    }

    private static void ApplyGuestCredentials(ProcessStartInfo psi, VmGuestCredentials? guestCredentials)
    {
        if (guestCredentials == null)
            return;

        psi.Environment["PROJETOVM_GuestUser"] = guestCredentials.Username;
        psi.Environment["PROJETOVM_GuestPassword"] = guestCredentials.Password;
    }
}
