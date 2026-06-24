// --- Módulo: SampleRunnerTests.cs ---

using VmAgent.Configuration;
using VmAgent.Models;
using VmAgent.Services;
using VmAgent.State;
using Xunit;

namespace VmAgent.Tests;

// --- Testes do executor de amostras ---
public sealed class SampleRunnerTests
{
    // --- Sem amostra carregada deve devolver BadRequest ---
    [Fact]
    public async Task RunAsync_WithoutSample_ReturnsBadRequest()
    {
        var state = new AnalysisState();

        var result = await SampleRunner.RunAsync(new RunRequest(), state);

        Assert.Contains("BadRequest", result.GetType().Name, StringComparison.Ordinal);
    }

    // --- Ficheiro inexistente no disco deve devolver BadRequest ---
    [Fact]
    public async Task RunAsync_MissingFileOnDisk_ReturnsBadRequest()
    {
        var state = new AnalysisState
        {
            SamplePath = Path.Combine(Path.GetTempPath(), "missing-sample.exe"),
            SampleFileName = "missing-sample.exe"
        };

        var result = await SampleRunner.RunAsync(
            new RunRequest { TimeoutSeconds = AgentLimits.MaxRunTimeoutSeconds + 999 },
            state);

        Assert.Contains("BadRequest", result.GetType().Name, StringComparison.Ordinal);
    }

    // --- Executa utilitário Windows quando disponível ---
    [Fact]
    public async Task RunAsync_ExecutesWindowsUtility_WhenAvailable()
    {
        if (!OperatingSystem.IsWindows())
            return;

        var utility = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "where.exe");
        if (!File.Exists(utility))
            return;

        var state = new AnalysisState
        {
            SamplePath = utility,
            SampleFileName = "where.exe"
        };

        var result = await SampleRunner.RunAsync(
            new RunRequest { TimeoutSeconds = 15 },
            state);

        Assert.Contains("Ok", result.GetType().Name, StringComparison.Ordinal);
        Assert.Equal("finished", state.LastBehavior?["status"]);
        Assert.NotNull(state.LastBehavior?["exitCode"]);
    }
}
