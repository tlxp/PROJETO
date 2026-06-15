using VmAgent.Security;
using Xunit;

namespace VmAgent.Tests;

public sealed class TokenComparerTests
{
    [Fact]
    public void FixedTimeEquals_MatchingTokens_ReturnsTrue()
    {
        Assert.True(TokenComparer.FixedTimeEquals("secret-token", "secret-token"));
    }

    [Fact]
    public void FixedTimeEquals_DifferentLength_ReturnsFalse()
    {
        Assert.False(TokenComparer.FixedTimeEquals("short", "longer-value"));
    }

    [Fact]
    public void FixedTimeEquals_DifferentContentSameLength_ReturnsFalse()
    {
        Assert.False(TokenComparer.FixedTimeEquals("aaaaaaaa", "bbbbbbbb"));
    }

    [Theory]
    [InlineData(null, "value")]
    [InlineData("value", null)]
    [InlineData(null, null)]
    public void FixedTimeEquals_NullInput_ReturnsFalse(string? a, string? b)
    {
        Assert.False(TokenComparer.FixedTimeEquals(a, b));
    }
}
