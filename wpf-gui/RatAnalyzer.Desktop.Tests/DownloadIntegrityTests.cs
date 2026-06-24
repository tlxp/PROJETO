// --- Módulo: DownloadIntegrityTests.cs ---
using RatAnalyzer.Desktop.Helpers;
using Xunit;

namespace RatAnalyzer.Desktop.Tests;

// --- Testes de verificação SHA-256 e parsing de assets GitHub ---
public sealed class DownloadIntegrityTests
{
    [Fact]
    public void ComputeSha256Hex_KnownContent_MatchesExpected()
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "rat-analyzer-test");

            var first = DownloadIntegrity.ComputeSha256Hex(path);
            var second = DownloadIntegrity.ComputeSha256Hex(path);

            Assert.Equal(first, second);
            Assert.Matches("^[0-9A-F]{64}$", first);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void VerifySha256OrThrow_Mismatch_Throws()
    {
        var path = Path.GetTempFileName();
        try
        {
            File.WriteAllText(path, "payload");

            var ex = Assert.Throws<InvalidOperationException>(() =>
                DownloadIntegrity.VerifySha256OrThrow(path, new string('0', 64)));

            Assert.Contains("SHA-256", ex.Message);
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void ParseSha256FileContent_GnuFormat_ReturnsHash()
    {
        const string content = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789  file.zip\n";

        var hash = DownloadIntegrity.ParseSha256FileContent(content);

        Assert.Equal("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789", hash);
    }

    [Fact]
    public void TryFindGithubAssetUrl_FindsMatchingAsset()
    {
        const string json = """
            {
              "assets": [
                { "name": "other.zip", "browser_download_url": "https://example.com/other.zip" },
                { "name": "tool.zip.sha256", "browser_download_url": "https://example.com/tool.zip.sha256" }
              ]
            }
            """;

        var url = DownloadIntegrity.TryFindGithubAssetUrl(json, "tool.zip.sha256");

        Assert.Equal("https://example.com/tool.zip.sha256", url);
    }

    [Fact]
    public void TryFindGithubSha256AssetUrl_FallsBackToUppercaseExtension()
    {
        const string json = """
            {
              "assets": [
                { "name": "tool.zip.SHA256", "browser_download_url": "https://example.com/tool.zip.SHA256" }
              ]
            }
            """;

        var url = DownloadIntegrity.TryFindGithubSha256AssetUrl(json, "tool.zip");

        Assert.Equal("https://example.com/tool.zip.SHA256", url);
    }
}
