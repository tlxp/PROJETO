using VmAgent.Services;
using Xunit;

namespace VmAgent.Tests;

public sealed class SampleStorageTests
{
    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData(".")]
    [InlineData("..")]
    [InlineData(@"..\..\windows\system32\cmd.exe")]
    public void TryResolveTargetPath_InvalidNames_ReturnsFalse(string fileName)
    {
        var ok = SampleStorage.TryResolveTargetPath(fileName, out var path, out var error);

        Assert.False(ok);
        Assert.Equal(string.Empty, path);
        Assert.False(string.IsNullOrWhiteSpace(error));
    }

    [Fact]
    public void TryResolveTargetPath_ValidName_ReturnsPathInsideSamplesDirectory()
    {
        var ok = SampleStorage.TryResolveTargetPath("sample.exe", out var path, out var error);

        Assert.True(ok);
        Assert.Null(error);
        Assert.StartsWith(SampleStorage.SamplesDirectory, path, StringComparison.OrdinalIgnoreCase);
        Assert.EndsWith("sample.exe", path, StringComparison.OrdinalIgnoreCase);
    }
}
