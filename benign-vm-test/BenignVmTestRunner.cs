using System.Diagnostics;
using System.Runtime.Versioning;
using Microsoft.Win32;

namespace BenignVmTest;

/// <summary>
/// Executa os três sinais observáveis (ficheiro, registry, processo filho) de forma inofensiva.
/// </summary>
public static class BenignVmTestRunner
{
    public static int Run(TextWriter? log = null)
    {
        log ??= Console.Out;
        var err = log == Console.Out ? Console.Error : log;

        log.WriteLine($"{BenignVmTestPaths.LogPrefix} início");

        try
        {
            Directory.CreateDirectory(BenignVmTestPaths.WorkDir);

            File.WriteAllText(
                BenignVmTestPaths.MarkerPath,
                $"benign marker @ {DateTimeOffset.Now:O}{Environment.NewLine}");
            log.WriteLine($"{BenignVmTestPaths.LogPrefix} ficheiro escrito: {BenignVmTestPaths.MarkerPath}");

            if (OperatingSystem.IsWindows())
            {
                WriteRegistryMarker(BenignVmTestPaths.RegistryKeyPath);
                log.WriteLine(
                    $@"{BenignVmTestPaths.LogPrefix} registry escrito: HKCU\{BenignVmTestPaths.RegistryKeyPath}");

                WriteRunOnceFlag(
                    BenignVmTestPaths.RunOnceKeyPath,
                    BenignVmTestPaths.RunOnceValueName,
                    BenignVmTestPaths.RegistryFlagPath);
                log.WriteLine(
                    $@"{BenignVmTestPaths.LogPrefix} RunOnce escrito: HKCU\{BenignVmTestPaths.RunOnceKeyPath}\{BenignVmTestPaths.RunOnceValueName}");

                File.WriteAllText(BenignVmTestPaths.RegistryFlagPath, "BENIGN_FLAG_SET=1" + Environment.NewLine);
                log.WriteLine($"{BenignVmTestPaths.LogPrefix} ficheiro-flag escrito: {BenignVmTestPaths.RegistryFlagPath}");
            }

            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments =
                    $"/c echo benign child @ %DATE% %TIME% > \"{BenignVmTestPaths.ChildOutputPath}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var child = Process.Start(psi);
            if (child is null)
            {
                err.WriteLine($"{BenignVmTestPaths.LogPrefix} falha ao iniciar processo filho (cmd.exe).");
                return 1;
            }

            child.WaitForExit(10_000);
            log.WriteLine($"{BenignVmTestPaths.LogPrefix} processo filho concluído: {BenignVmTestPaths.ChildOutputPath}");
        }
        catch (Exception ex)
        {
            err.WriteLine($"{BenignVmTestPaths.LogPrefix} erro: {ex.Message}");
            return 1;
        }

        log.WriteLine($"{BenignVmTestPaths.LogPrefix} fim");
        return 0;
    }

    [SupportedOSPlatform("windows")]
    private static void WriteRegistryMarker(string keyPath)
    {
        using var key = Registry.CurrentUser.CreateSubKey(keyPath);
        key.SetValue("BenignFlag", 1, RegistryValueKind.DWord);
        key.SetValue("Installed", DateTimeOffset.Now.ToString("O"), RegistryValueKind.String);
        key.SetValue("Marker", "benign-vm-test", RegistryValueKind.String);
    }

    [SupportedOSPlatform("windows")]
    private static void WriteRunOnceFlag(string keyPath, string valueName, string flagFilePath)
    {
        var cmd = $@"C:\Windows\System32\cmd.exe /c echo BENIGN_FLAG_SET=1> ""{flagFilePath}""";
        using var key = Registry.CurrentUser.CreateSubKey(keyPath);
        key.SetValue(valueName, cmd, RegistryValueKind.String);
    }
}
