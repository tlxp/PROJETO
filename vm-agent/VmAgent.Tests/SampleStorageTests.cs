// --- Módulo: SampleStorageTests.cs ---

using VmAgent.Services;
using Xunit;

namespace VmAgent.Tests;

// --- Testes do armazenamento seguro de amostras ---
public sealed class SampleStorageTests
{
    // --- Nomes inválidos ou com path traversal devem ser rejeitados ---
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

    // --- Nome válido deve resolver dentro da pasta samples ---
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
