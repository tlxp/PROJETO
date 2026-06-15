using VmAgent.Security;
using Xunit;

namespace VmAgent.Tests;

public sealed class AgentTokenMiddlewareTests
{
    [Fact]
    public void ValidateStartupToken_WithToken_ReturnsTrue()
    {
        Assert.True(AgentTokenMiddleware.ValidateStartupToken("my-token", allowInsecure: false));
    }

    [Fact]
    public void ValidateStartupToken_WithoutTokenAndWithoutInsecure_ReturnsFalse()
    {
        Assert.False(AgentTokenMiddleware.ValidateStartupToken(null, allowInsecure: false));
        Assert.False(AgentTokenMiddleware.ValidateStartupToken("   ", allowInsecure: false));
    }

    [Fact]
    public void ValidateStartupToken_WithoutTokenButInsecureAllowed_ReturnsTrue()
    {
        Assert.True(AgentTokenMiddleware.ValidateStartupToken(null, allowInsecure: true));
    }

    [Fact]
    public void IsInsecureDevMode_ReadsEnvironmentVariable()
    {
        var previous = Environment.GetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE");
        try
        {
            Environment.SetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE", "1");
            Assert.True(AgentTokenMiddleware.IsInsecureDevMode());

            Environment.SetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE", "0");
            Assert.False(AgentTokenMiddleware.IsInsecureDevMode());
        }
        finally
        {
            Environment.SetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE", previous);
        }
    }

    [Fact]
    public void ResolveTokenFromEnvironment_ReturnsConfiguredValue()
    {
        var previous = Environment.GetEnvironmentVariable("VM_AGENT_TOKEN");
        try
        {
            Environment.SetEnvironmentVariable("VM_AGENT_TOKEN", "configured-token");
            Assert.Equal("configured-token", AgentTokenMiddleware.ResolveTokenFromEnvironment());
        }
        finally
        {
            Environment.SetEnvironmentVariable("VM_AGENT_TOKEN", previous);
        }
    }
}
