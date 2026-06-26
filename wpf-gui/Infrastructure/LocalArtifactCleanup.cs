// --- Módulo: LocalArtifactCleanup.cs ---
// Limpeza de artefatos temporários e jobs de sandbox em disco.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using RatAnalyzer.Desktop.Bootstrap;
using RatAnalyzer.Desktop.Views;



namespace RatAnalyzer.Desktop.Infrastructure;



// --- Limpeza de artefatos temporários e jobs de sandbox ---
internal static class LocalArtifactCleanup
{
    private static readonly string[] TempDirectoryPrefixes = { "rat_", "rat_stream_" };
    private const string AdkTempFolderName = "RatAnalyzerAdk";



    // --- Pastas em %LOCALAPPDATA%\RatAnalyzer preservadas na limpeza completa (ex.: Ghidra instalado no arranque) ---
    private static readonly HashSet<string> PreservedLocalDataTopLevelNames =
        new(StringComparer.OrdinalIgnoreCase) { "Ghidra" };



    // --- Limpa resumo ---
    internal sealed class CleanupSummary
    {
        public int TempDirectoriesRemoved { get; set; }
        public int SandboxJobDirectoriesProcessed { get; set; }
        public int SandboxFilesRemoved { get; set; }
        public int DataPathsRemoved { get; set; }
        public long BytesFreed { get; set; }
    }



    // --- Modelo de armazenamento estimate ---
    internal sealed class StorageEstimate
    {
        public long TempAnalysisBytes { get; set; }
        public int TempAnalysisDirectories { get; set; }
        public string TempPath { get; set; } = "";
        public string? SandboxJobsPath { get; set; }
        public long SandboxJobsBytes { get; set; }
    }



    // --- Estima Local artefactos ---
    internal static StorageEstimate EstimateLocalArtifacts()
    {
        var estimate = new StorageEstimate
        {
            TempPath = Path.GetTempPath()
        };



        foreach (var dir in EnumerateTempAnalysisDirectories())
        {
            estimate.TempAnalysisDirectories++;
            estimate.TempAnalysisBytes += GetDirectorySizeBytes(dir);
        }



        var sandboxJobs = ResolveSandboxJobsDirectory();
        if (!string.IsNullOrWhiteSpace(sandboxJobs) && Directory.Exists(sandboxJobs))
        {
            estimate.SandboxJobsPath = sandboxJobs;
            estimate.SandboxJobsBytes = GetDirectorySizeBytes(sandboxJobs);
        }



        return estimate;
    }



    // --- Limpa temporários análise pastas ---
    internal static CleanupSummary CleanupTempAnalysisDirectories()
    {
        var summary = new CleanupSummary();
        foreach (var dir in EnumerateTempAnalysisDirectories().ToList())
        {
            var size = GetDirectorySizeBytes(dir);
            if (TryDeleteDirectory(dir))
            {
                summary.TempDirectoriesRemoved++;
                summary.BytesFreed += size;
            }
        }



        return summary;
    }



    // --- Limpa sandbox job artefactos ---
    internal static CleanupSummary CleanupSandboxJobArtifacts()
    {
        var summary = new CleanupSummary();
        var sandboxJobs = ResolveSandboxJobsDirectory();
        if (string.IsNullOrWhiteSpace(sandboxJobs) || !Directory.Exists(sandboxJobs))
            return summary;



        foreach (var jobDir in Directory.EnumerateDirectories(sandboxJobs))
        {
            var jobName = Path.GetFileName(jobDir);
            if (string.IsNullOrWhiteSpace(jobName))
                continue;



            summary.SandboxJobDirectoriesProcessed++;
            summary.BytesFreed += TryDeletePath(Path.Combine(jobDir, "out"));
            summary.BytesFreed += TryDeletePath(Path.Combine(jobDir, "out.zip"));



            foreach (var file in Directory.EnumerateFiles(jobDir))
            {
                var name = Path.GetFileName(file);
                if (name.Equals("analysis.db", StringComparison.OrdinalIgnoreCase))
                    continue;



                var size = GetFileSizeBytes(file);
                if (TryDeleteFile(file))
                {
                    summary.SandboxFilesRemoved++;
                    summary.BytesFreed += size;
                }
            }
        }



        return summary;
    }



    // --- Limpa On Application saída ---
    internal static CleanupSummary CleanupOnApplicationExit()
    {
        var summary = new CleanupSummary();
        Merge(summary, CleanupTempAnalysisDirectories());
        Merge(summary, CleanupSandboxJobArtifacts());
        return summary;
    }



    // --- Limpa Everything ---
    internal static CleanupSummary CleanupEverything()
    {
        var summary = new CleanupSummary();
        Merge(summary, CleanupTempAnalysisDirectories());



        var dataDir = ResolveDataDirectory();
        if (!string.IsNullOrWhiteSpace(dataDir))
            PurgeLocalRatAnalyzerDataRootPreservingTooling(dataDir, summary);



        var legacySandboxJobs = ResolveLegacySandboxJobsDirectory();
        if (!string.IsNullOrWhiteSpace(legacySandboxJobs))
        {
            var size = GetDirectorySizeBytes(legacySandboxJobs);
            if (TryDeleteDirectory(legacySandboxJobs))
            {
                summary.DataPathsRemoved++;
                summary.BytesFreed += size;
            }
        }



        return summary;
    }



    // --- Resolve dados pasta ---
    private static string? ResolveDataDirectory()
    {
        var dataDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RatAnalyzer");
        return Directory.Exists(dataDir) ? dataDir : null;
    }



    // --- Resolve legado sandbox jobs pasta ---
    private static string? ResolveLegacySandboxJobsDirectory()
    {
        try
        {
            var backendDir = StartupSequence.FindBackendWorkingDirectory();
            var projectRoot = backendDir != null
                ? Directory.GetParent(backendDir)?.FullName
                : null;
            if (string.IsNullOrWhiteSpace(projectRoot))
                return null;



            var legacy = Path.Combine(projectRoot, "sandbox_jobs");
            return Directory.Exists(legacy) ? legacy : null;
        }
        catch
        {
            return null;
        }
    }



    // --- Remove relatórios/jobs sob %LOCALAPPDATA%\RatAnalyzer mantendo subpastas de tooling (ex.: Ghidra) ---
    private static void PurgeLocalRatAnalyzerDataRootPreservingTooling(string dataRoot, CleanupSummary summary)
    {
        if (string.IsNullOrWhiteSpace(dataRoot) || !Directory.Exists(dataRoot))
            return;



        foreach (var path in Directory.EnumerateFileSystemEntries(dataRoot))
        {
            var name = Path.GetFileName(path);
            if (string.IsNullOrWhiteSpace(name) || PreservedLocalDataTopLevelNames.Contains(name))
                continue;



            if (Directory.Exists(path))
            {
                var size = GetDirectorySizeBytes(path);
                if (TryDeleteDirectory(path))
                {
                    summary.DataPathsRemoved++;
                    summary.BytesFreed += size;
                }
                continue;
            }



            if (!File.Exists(path))
                continue;



            var fileSize = GetFileSizeBytes(path);
            if (TryDeleteFile(path))
            {
                summary.DataPathsRemoved++;
                summary.BytesFreed += fileSize;
            }
        }
    }



    // --- Enumera temporários análise pastas ---
    private static IEnumerable<string> EnumerateTempAnalysisDirectories()
    {
        var tempRoot = Path.GetTempPath();
        if (!Directory.Exists(tempRoot))
            yield break;



        foreach (var dir in Directory.EnumerateDirectories(tempRoot))
        {
            var name = Path.GetFileName(dir);
            if (string.IsNullOrWhiteSpace(name))
                continue;



            if (TempDirectoryPrefixes.Any(prefix => name.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
            {
                yield return dir;
                continue;
            }



            if (name.Equals(AdkTempFolderName, StringComparison.OrdinalIgnoreCase))
                yield return dir;
        }
    }



    // --- Resolve sandbox jobs pasta ---
    private static string? ResolveSandboxJobsDirectory()
    {
        var dataDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "RatAnalyzer",
            "sandbox_jobs");
        if (Directory.Exists(dataDir))
            return dataDir;



        try
        {
            var backendDir = StartupSequence.FindBackendWorkingDirectory();
            var projectRoot = backendDir != null
                ? Directory.GetParent(backendDir)?.FullName
                : null;
            if (!string.IsNullOrWhiteSpace(projectRoot))
            {
                var legacy = Path.Combine(projectRoot, "sandbox_jobs");
                if (Directory.Exists(legacy))
                    return legacy;
            }
        }
        catch { /* ignorar */ }



        return null;
    }



    // --- Obtém pasta tamanho bytes ---
    private static long GetDirectorySizeBytes(string path)
    {
        try
        {
            if (!Directory.Exists(path))
                return 0;



            long total = 0;
            foreach (var file in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories))
                total += GetFileSizeBytes(file);
            return total;
        }
        catch
        {
            return 0;
        }
    }



    // --- Obtém ficheiro tamanho bytes ---
    private static long GetFileSizeBytes(string path)
    {
        try
        {
            return new FileInfo(path).Length;
        }
        catch
        {
            return 0;
        }
    }



    // --- Tenta Delete pasta ---
    private static bool TryDeleteDirectory(string path)
    {
        try
        {
            if (!Directory.Exists(path))
                return false;



            Directory.Delete(path, recursive: true);
            return true;
        }
        catch
        {
            return false;
        }
    }



    // --- Tenta Delete caminho ---
    private static long TryDeletePath(string path)
    {
        var size = 0L;
        try
        {
            if (Directory.Exists(path))
            {
                size = GetDirectorySizeBytes(path);
                Directory.Delete(path, recursive: true);
                return size;
            }



            if (File.Exists(path))
            {
                size = GetFileSizeBytes(path);
                File.Delete(path);
            }
        }
        catch { /* ignorar */ }



        return size;
    }



    // --- Tenta Delete ficheiro ---
    private static bool TryDeleteFile(string path)
    {
        try
        {
            if (!File.Exists(path))
                return false;



            File.Delete(path);
            return true;
        }
        catch
        {
            return false;
        }
    }



    // --- Agrega ---
    private static void Merge(CleanupSummary target, CleanupSummary source)
    {
        target.TempDirectoriesRemoved += source.TempDirectoriesRemoved;
        target.SandboxJobDirectoriesProcessed += source.SandboxJobDirectoriesProcessed;
        target.SandboxFilesRemoved += source.SandboxFilesRemoved;
        target.DataPathsRemoved += source.DataPathsRemoved;
        target.BytesFreed += source.BytesFreed;
    }
}

