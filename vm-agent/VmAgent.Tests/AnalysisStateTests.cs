// --- Módulo: AnalysisStateTests.cs ---
// Testes de reinício do estado de análise.


using VmAgent.State;
using Xunit;



namespace VmAgent.Tests;



// --- Testes do estado de análise ---
public sealed class AnalysisStateTests
{
    // --- Verifica que Reset limpa amostra e comportamento ---
    [Fact]
    // --- Reinicia Clears amostra e comportamento ---
    public void Reset_ClearsSampleAndBehavior()
    {
        var state = new AnalysisState
        {
            SamplePath = @"C:\samples\test.exe",
            SampleFileName = "test.exe",
            LastBehavior = new Dictionary<string, object?> { ["status"] = "finished" }
        };



        state.Reset();



        Assert.Null(state.SamplePath);
        Assert.Null(state.SampleFileName);
        Assert.Null(state.LastBehavior);
    }
}

