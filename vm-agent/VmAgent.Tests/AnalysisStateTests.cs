using VmAgent.State;
using Xunit;

namespace VmAgent.Tests;

public sealed class AnalysisStateTests
{
    [Fact]
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
