// --- Módulo: TokenComparerTests.cs ---
// Testes de comparação segura de tokens.


using VmAgent.Security;
using Xunit;



namespace VmAgent.Tests;



// --- Testes da comparação segura de tokens ---
public sealed class TokenComparerTests
{
    // --- Tokens idênticos devem coincidir ---
    [Fact]
    public void FixedTimeEquals_MatchingTokens_ReturnsTrue()
    {
        Assert.True(TokenComparer.FixedTimeEquals("secret-token", "secret-token"));
    }



    // --- Comprimentos diferentes devem falhar ---
    [Fact]
    public void FixedTimeEquals_DifferentLength_ReturnsFalse()
    {
        Assert.False(TokenComparer.FixedTimeEquals("short", "longer-value"));
    }



    // --- Conteúdo diferente com mesmo comprimento deve falhar ---
    [Fact]
    public void FixedTimeEquals_DifferentContentSameLength_ReturnsFalse()
    {
        Assert.False(TokenComparer.FixedTimeEquals("aaaaaaaa", "bbbbbbbb"));
    }



    // --- Entradas nulas devem sempre falhar ---
    [Theory]
    [InlineData(null, "value")]
    [InlineData("value", null)]
    [InlineData(null, null)]
    public void FixedTimeEquals_NullInput_ReturnsFalse(string? a, string? b)
    {
        Assert.False(TokenComparer.FixedTimeEquals(a, b));
    }
}

