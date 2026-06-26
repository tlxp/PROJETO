// --- Módulo: ProjetoVmPathsTests.cs ---
// Testes de resolução de caminhos do sandbox Hyper-V.
using RatAnalyzer.Desktop.Infrastructure;
using Xunit;



namespace RatAnalyzer.Desktop.Tests;



// --- Testes de resolução de caminhos do sandbox Hyper-V ---
public sealed class ProjetoVmPathsTests
{
    [Fact]
    // --- Obtém Base caminho Prefers ambiente Variable ---
    public void GetBasePath_PrefersEnvironmentVariable()
    {
        var previous = Environment.GetEnvironmentVariable("PROJETOVM_BasePath");
        var tempDir = Path.Combine(Path.GetTempPath(), "projeto-vm-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);



        try
        {
            Environment.SetEnvironmentVariable("PROJETOVM_BasePath", tempDir);



            var basePath = ProjetoVmPaths.GetBasePath(Path.Combine(tempDir, "scripts"));



            Assert.Equal(tempDir, basePath);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PROJETOVM_BasePath", previous);
            try { Directory.Delete(tempDir, recursive: true); } catch { /* ignore */ }
        }
    }



    [Fact]
    // --- Obtém Base caminho Parses Config ficheiro When Env Missing ---
    public void GetBasePath_ParsesConfigFile_WhenEnvMissing()
    {
        var previous = Environment.GetEnvironmentVariable("PROJETOVM_BasePath");
        var tempDir = Path.Combine(Path.GetTempPath(), "projeto-vm-config-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);



        try
        {
            Environment.SetEnvironmentVariable("PROJETOVM_BasePath", null);
            File.WriteAllText(
                Path.Combine(tempDir, "_Config.ps1"),
                "$script:PROJETOVM_BasePath = if ($env:PROJETOVM_BasePath) { $env:PROJETOVM_BasePath } else { \"E:\\SandboxRoot\" }");



            var basePath = ProjetoVmPaths.GetBasePath(tempDir);



            Assert.Equal(@"E:\SandboxRoot", basePath);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PROJETOVM_BasePath", previous);
            try { Directory.Delete(tempDir, recursive: true); } catch { /* ignore */ }
        }
    }



    [Fact]
    // --- relatórios pasta Combines Base caminho com relatórios ---
    public void ReportsDir_CombinesBasePathWithReports()
    {
        var previous = Environment.GetEnvironmentVariable("PROJETOVM_BasePath");
        try
        {
            Environment.SetEnvironmentVariable("PROJETOVM_BasePath", @"C:\VMRoot");



            var reports = ProjetoVmPaths.ReportsDir(@"C:\repo\scripts");



            Assert.Equal(Path.Combine(@"C:\VMRoot", "Reports"), reports);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PROJETOVM_BasePath", previous);
        }
    }
}

