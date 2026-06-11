// Benign VM Test — programa INOFENSIVO para validar a sandbox/relatórios do RAT Analyzer.
//
// Reproduz, de forma controlada e reversível, três comportamentos observáveis que a monitorização
// da sandbox deve detetar: alteração de ficheiros, escrita no registry e criação de processo filho.
// NÃO contém qualquer lógica maliciosa.

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.Versioning;
using Microsoft.Win32;

const string workDir = @"C:\analysis_work";
const string markerPath = workDir + @"\benign_test_marker.txt";
const string childOutputPath = workDir + @"\child_process.txt";
const string registryKeyPath = @"Software\RATAnalyzerTest";

Console.WriteLine("[benign-vm-test] início");

try
{
    Directory.CreateDirectory(workDir);

    // 1) Ficheiro: cria/modifica um marcador.
    File.WriteAllText(markerPath, $"benign marker @ {DateTimeOffset.Now:O}{Environment.NewLine}");
    Console.WriteLine($"[benign-vm-test] ficheiro escrito: {markerPath}");

    // 2) Registry: escreve chaves em HKCU\Software\RATAnalyzerTest (apenas no Windows).
    if (OperatingSystem.IsWindows())
    {
        WriteRegistryMarker(registryKeyPath);
        Console.WriteLine($@"[benign-vm-test] registry escrito: HKCU\{registryKeyPath}");
    }

    // 3) Processo filho: cmd.exe que escreve um ficheiro.
    var psi = new ProcessStartInfo
    {
        FileName = "cmd.exe",
        Arguments = $"/c echo benign child @ %DATE% %TIME% > \"{childOutputPath}\"",
        UseShellExecute = false,
        CreateNoWindow = true,
    };
    using var child = Process.Start(psi);
    if (child is null)
    {
        Console.Error.WriteLine("[benign-vm-test] falha ao iniciar processo filho (cmd.exe).");
        return 1;
    }
    child.WaitForExit(10_000);
    Console.WriteLine($"[benign-vm-test] processo filho concluído: {childOutputPath}");
}
catch (Exception ex)
{
    Console.Error.WriteLine($"[benign-vm-test] erro: {ex.Message}");
    return 1;
}

Console.WriteLine("[benign-vm-test] fim");
return 0;

[SupportedOSPlatform("windows")]
static void WriteRegistryMarker(string keyPath)
{
    using var key = Registry.CurrentUser.CreateSubKey(keyPath);
    key.SetValue("Installed", DateTimeOffset.Now.ToString("O"), RegistryValueKind.String);
    key.SetValue("Marker", "benign-vm-test", RegistryValueKind.String);
}
