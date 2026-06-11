using System;
using System.IO;
using System.Text.RegularExpressions;

namespace RatAnalyzer.Desktop;

/// <summary>
/// Resolve caminhos do sandbox Hyper-V a partir de _Config.ps1 ou variáveis de ambiente.
/// </summary>
internal static class ProjetoVmPaths
{
    private static readonly Regex BasePathRegex = new(
        @"PROJETOVM_BasePath\s*=\s*(?:if\s*\([^)]+\)\s*\{\s*\$env:PROJETOVM_BasePath\s*\}\s*else\s*\{\s*)?""([^""]+)""",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);

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

    public static string ReportsDir(string hypervScriptsPath) =>
        Path.Combine(GetBasePath(hypervScriptsPath), "Reports");

    public static string LogsRunsDir(string hypervScriptsPath) =>
        Path.Combine(GetBasePath(hypervScriptsPath), "Logs", "Runs");
}
