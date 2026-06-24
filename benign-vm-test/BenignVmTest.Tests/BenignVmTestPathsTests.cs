// --- Módulo: BenignVmTestPathsTests.cs ---

using Xunit;

namespace BenignVmTest.Tests;

// --- Testes das constantes de caminhos ---
public sealed class BenignVmTestPathsTests
{
    // --- Diretório de trabalho deve ser C:\analysis_work ---
    [Fact]
    public void WorkDir_IsAnalysisWorkRoot()
    {
        Assert.Equal(@"C:\analysis_work", BenignVmTestPaths.WorkDir);
    }

    // --- Artefactos devem estar sob o diretório de trabalho ---
    [Fact]
    public void ArtifactPaths_AreUnderWorkDir()
    {
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.MarkerPath);
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.ChildOutputPath);
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.RegistryFlagPath);
    }

    // --- Chave de registry deve usar prefixo da sandbox ---
    [Fact]
    public void RegistryKeyPath_MatchesSandboxTelemetryPrefix()
    {
        Assert.Equal(@"Software\RATAnalyzerTest", BenignVmTestPaths.RegistryKeyPath);
    }

    // --- Nome RunOnce deve ser distinto de outras amostras ---
    [Fact]
    public void RunOnceValueName_IsDistinctFromOtherSamples()
    {
        Assert.Equal("RATAnalyzerBenignFlag", BenignVmTestPaths.RunOnceValueName);
        Assert.Contains("RunOnce", BenignVmTestPaths.RunOnceKeyPath, StringComparison.OrdinalIgnoreCase);
    }

    // --- Prefixo de log deve ser estável para parsing de stdout ---
    [Fact]
    public void LogPrefix_IsStableForStdoutParsing()
    {
        Assert.Equal("[benign-vm-test]", BenignVmTestPaths.LogPrefix);
    }
}
