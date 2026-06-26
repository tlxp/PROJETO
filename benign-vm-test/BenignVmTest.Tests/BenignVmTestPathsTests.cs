// --- Módulo: BenignVmTestPathsTests.cs ---
// Testes das constantes de caminhos do smoke test.


using Xunit;



namespace BenignVmTest.Tests;



// --- Testes das constantes de caminhos ---
public sealed class BenignVmTestPathsTests
{
    // --- Diretório de trabalho deve ser C:\analysis_work ---
    [Fact]
    // --- trabalho pasta Is análise trabalho raiz ---
    public void WorkDir_IsAnalysisWorkRoot()
    {
        Assert.Equal(@"C:\analysis_work", BenignVmTestPaths.WorkDir);
    }



    // --- Artefactos devem estar sob o diretório de trabalho ---
    [Fact]
    // --- artefacto caminhos Are Under trabalho pasta ---
    public void ArtifactPaths_AreUnderWorkDir()
    {
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.MarkerPath);
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.ChildOutputPath);
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.RegistryFlagPath);
    }



    // --- Chave de registry deve usar prefixo da sandbox ---
    [Fact]
    // --- registry chave caminho Matches sandbox Telemetry prefixo ---
    public void RegistryKeyPath_MatchesSandboxTelemetryPrefix()
    {
        Assert.Equal(@"Software\RATAnalyzerTest", BenignVmTestPaths.RegistryKeyPath);
    }



    // --- Nome RunOnce deve ser distinto de outras amostras ---
    [Fact]
    // --- Executa única vez valor nome Is Distinct a partir de Other amostras ---
    public void RunOnceValueName_IsDistinctFromOtherSamples()
    {
        Assert.Equal("RATAnalyzerBenignFlag", BenignVmTestPaths.RunOnceValueName);
        Assert.Contains("RunOnce", BenignVmTestPaths.RunOnceKeyPath, StringComparison.OrdinalIgnoreCase);
    }



    // --- Prefixo de log deve ser estável para parsing de stdout ---
    [Fact]
    // --- log prefixo Is Stable para stdout Parsing ---
    public void LogPrefix_IsStableForStdoutParsing()
    {
        Assert.Equal("[benign-vm-test]", BenignVmTestPaths.LogPrefix);
    }
}

