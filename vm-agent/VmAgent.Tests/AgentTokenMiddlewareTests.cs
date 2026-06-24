// --- Módulo: AgentTokenMiddlewareTests.cs ---

using VmAgent.Security;
using Xunit;

namespace VmAgent.Tests;

// --- Testes do middleware de autenticação ---
public sealed class AgentTokenMiddlewareTests
{
    // --- Token presente deve permitir arranque ---
    [Fact]
    public void ValidateStartupToken_WithToken_ReturnsTrue()
    {
        Assert.True(AgentTokenMiddleware.ValidateStartupToken("my-token", allowInsecure: false));
    }

    // --- Sem token e sem modo inseguro deve bloquear arranque ---
    [Fact]
    public void ValidateStartupToken_WithoutTokenAndWithoutInsecure_ReturnsFalse()
    {
        Assert.False(AgentTokenMiddleware.ValidateStartupToken(null, allowInsecure: false));
        Assert.False(AgentTokenMiddleware.ValidateStartupToken("   ", allowInsecure: false));
    }

    // --- Modo inseguro permite arranque sem token ---
    [Fact]
    public void ValidateStartupToken_WithoutTokenButInsecureAllowed_ReturnsTrue()
    {
        Assert.True(AgentTokenMiddleware.ValidateStartupToken(null, allowInsecure: true));
    }

    // --- Variável VM_AGENT_ALLOW_INSECURE controla modo inseguro ---
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

    // --- Token é lido da variável VM_AGENT_TOKEN ---
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
