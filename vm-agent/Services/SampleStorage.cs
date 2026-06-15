using VmAgent.Configuration;

namespace VmAgent.Services;

internal static class SampleStorage
{
    public static string SamplesDirectory =>
        Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "samples"));

    public static bool TryResolveTargetPath(string safeName, out string targetPath, out string? error)
    {
        targetPath = string.Empty;
        error = null;

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
