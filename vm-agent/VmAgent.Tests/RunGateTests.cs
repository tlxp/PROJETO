using VmAgent.State;
using Xunit;

namespace VmAgent.Tests;

public sealed class RunGateTests
{
    [Fact]
    public async Task TryEnterAsync_AllowsSingleConcurrentHolder()
    {
        var gate = new RunGate();

        Assert.True(await gate.TryEnterAsync());
        Assert.False(await gate.TryEnterAsync());

        gate.Release();
        Assert.True(await gate.TryEnterAsync());
        gate.Release();
    }
}
