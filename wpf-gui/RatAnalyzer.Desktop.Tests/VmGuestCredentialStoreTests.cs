using RatAnalyzer.Desktop.Services;
using Xunit;

namespace RatAnalyzer.Desktop.Tests;

public sealed class VmGuestCredentialStoreTests
{
    [Fact]
    public void TryFromEnvironment_ReturnsNull_WhenPasswordMissing()
    {
        var previousPassword = Environment.GetEnvironmentVariable("PROJETOVM_GuestPassword");
        var previousUser = Environment.GetEnvironmentVariable("PROJETOVM_GuestUser");

        try
        {
            Environment.SetEnvironmentVariable("PROJETOVM_GuestPassword", null);
            Environment.SetEnvironmentVariable("PROJETOVM_GuestUser", null);

            Assert.Null(VmGuestCredentialStore.TryFromEnvironment());
        }
        finally
        {
            Environment.SetEnvironmentVariable("PROJETOVM_GuestPassword", previousPassword);
            Environment.SetEnvironmentVariable("PROJETOVM_GuestUser", previousUser);
        }
    }

    [Fact]
    public void TryFromEnvironment_UsesDefaultUsername_WhenUserMissing()
    {
        var previousPassword = Environment.GetEnvironmentVariable("PROJETOVM_GuestPassword");
        var previousUser = Environment.GetEnvironmentVariable("PROJETOVM_GuestUser");

        try
        {
            Environment.SetEnvironmentVariable("PROJETOVM_GuestPassword", "secret");
            Environment.SetEnvironmentVariable("PROJETOVM_GuestUser", null);

            var creds = VmGuestCredentialStore.TryFromEnvironment();

            Assert.NotNull(creds);
            Assert.Equal("analyst", creds.Username);
            Assert.Equal("secret", creds.Password);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PROJETOVM_GuestPassword", previousPassword);
            Environment.SetEnvironmentVariable("PROJETOVM_GuestUser", previousUser);
        }
    }

    [Fact]
    public void SetSession_AndTryGetSession_RoundTrip()
    {
        var creds = new VmGuestCredentials("guest", "pw");

        VmGuestCredentialStore.SetSession(creds);

        Assert.Equal(creds, VmGuestCredentialStore.TryGetSession());
    }

    [Fact]
    public void SetSession_Null_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => VmGuestCredentialStore.SetSession(null!));
    }
}
