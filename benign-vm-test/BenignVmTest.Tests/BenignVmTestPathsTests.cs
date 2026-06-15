using Xunit;

namespace BenignVmTest.Tests;

public sealed class BenignVmTestPathsTests
{
    [Fact]
    public void WorkDir_IsAnalysisWorkRoot()
    {
        Assert.Equal(@"C:\analysis_work", BenignVmTestPaths.WorkDir);
    }

    [Fact]
    public void ArtifactPaths_AreUnderWorkDir()
    {
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.MarkerPath);
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.ChildOutputPath);
        Assert.StartsWith(BenignVmTestPaths.WorkDir, BenignVmTestPaths.RegistryFlagPath);
    }

    [Fact]
    public void RegistryKeyPath_MatchesSandboxTelemetryPrefix()
    {
        Assert.Equal(@"Software\RATAnalyzerTest", BenignVmTestPaths.RegistryKeyPath);
    }

    [Fact]
    public void RunOnceValueName_IsDistinctFromOtherSamples()
    {
        Assert.Equal("RATAnalyzerBenignFlag", BenignVmTestPaths.RunOnceValueName);
        Assert.Contains("RunOnce", BenignVmTestPaths.RunOnceKeyPath, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void LogPrefix_IsStableForStdoutParsing()
    {
        Assert.Equal("[benign-vm-test]", BenignVmTestPaths.LogPrefix);
    }
}
