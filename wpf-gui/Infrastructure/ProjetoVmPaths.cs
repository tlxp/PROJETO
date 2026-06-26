// --- Módulo: ProjetoVmPaths.cs ---
// Resolve caminhos do sandbox Hyper-V a partir de env ou _Config.ps1.
using System;
using System.IO;
using System.Text.RegularExpressions;



namespace RatAnalyzer.Desktop.Infrastructure;



// --- Resolve caminhos do sandbox Hyper-V (base, relatórios, logs) ---
internal static class ProjetoVmPaths
{
    private static readonly Regex BasePathRegex = new(
        @"PROJETOVM_BasePath\s*=\s*(?:if\s*\([^)]+\)\s*\{\s*\$env:PROJETOVM_BasePath\s*\}\s*else\s*\{\s*)?""([^""]+)""",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);



    // --- Obtém caminho base a partir de env ou _Config.ps1 ---
    public static string GetBasePath(string hypervScriptsPath)
    {
        var fromEnv = Environment.GetEnvironmentVariable("PROJETOVM_BasePath");
        if (!string.IsNullOrWhiteSpace(fromEnv))
            return fromEnv.Trim();



        var configPath = Path.Combine(hypervScriptsPath, "_Config.ps1");
        if (File.Exists(configPath))
        {
            foreach (var line in File.ReadLines(configPath))
            {
                var match = BasePathRegex.Match(line);
                if (match.Success)
                    return match.Groups[1].Value;
            }
        }



        return @"D:\PROJETOVM";
    }



    // --- relatórios pasta ---
    public static string ReportsDir(string hypervScriptsPath) =>
        Path.Combine(GetBasePath(hypervScriptsPath), "Reports");



    // --- Logs Runs pasta ---
    public static string LogsRunsDir(string hypervScriptsPath) =>
        Path.Combine(GetBasePath(hypervScriptsPath), "Logs", "Runs");
}

