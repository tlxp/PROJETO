// --- Módulo: SampleStorage.cs ---

using VmAgent.Configuration;

namespace VmAgent.Services;

// --- Armazenamento seguro de amostras ---
internal static class SampleStorage
{
    public static string SamplesDirectory =>
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "samples"));

    // --- Resolve caminho de destino validando o nome do ficheiro ---
    public static bool TryResolveTargetPath(string safeName, out string targetPath, out string? error)
    {
        targetPath = string.Empty;
        error = null;

        // *rejeita nomes vazios, relativos ou com path traversal*
        if (string.IsNullOrWhiteSpace(safeName) ||
            safeName is "." or ".." ||
            safeName.Contains("..", StringComparison.Ordinal))
        {
            error = "Nome de ficheiro inválido.";
            return false;
        }

        var baseDir = SamplesDirectory;
        Directory.CreateDirectory(baseDir);
        targetPath = Path.GetFullPath(Path.Combine(baseDir, safeName));

        // *garante que o destino permanece dentro da pasta samples*
        if (!targetPath.StartsWith(baseDir + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(targetPath, baseDir, StringComparison.OrdinalIgnoreCase))
        {
            error = "Caminho de destino inválido.";
            targetPath = string.Empty;
            return false;
        }

        return true;
    }
}
