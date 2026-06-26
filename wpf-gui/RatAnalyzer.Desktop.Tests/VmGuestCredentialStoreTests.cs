// --- Módulo: VmGuestCredentialStoreTests.cs ---
// Testes de persistência de credenciais de convidado.
using RatAnalyzer.Desktop.Services;
using Xunit;



namespace RatAnalyzer.Desktop.Tests;



// --- Testes do armazenamento de credenciais da VM ---
public sealed class VmGuestCredentialStoreTests
{
    [Fact]
    // --- Tenta a partir de ambiente devolve Null When palavra-passe Missing ---
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
    // --- Tenta a partir de ambiente Uses por omissão utilizador When User Missing ---
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
    // --- Define Session e Try Get Session Round Trip ---
    public void SetSession_AndTryGetSession_RoundTrip()
    {
        var creds = new VmGuestCredentials("guest", "pw");



        VmGuestCredentialStore.SetSession(creds);



        Assert.Equal(creds, VmGuestCredentialStore.TryGetSession());
    }



    [Fact]
    // --- Define Session Null Throws ---
    public void SetSession_Null_Throws()
    {
        Assert.Throws<ArgumentNullException>(() => VmGuestCredentialStore.SetSession(null!));
    }
}

