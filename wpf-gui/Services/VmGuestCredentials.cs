using System;

namespace RatAnalyzer.Desktop.Services;

public sealed record VmGuestCredentials(string Username, string Password);

/// <summary>Credenciais do utilizador Windows na VM guest (sessão ou variáveis de ambiente).</summary>
public static class VmGuestCredentialStore
{
    private static VmGuestCredentials? _session;

    public static VmGuestCredentials? TryFromEnvironment()
    {
        var password = Environment.GetEnvironmentVariable("PROJETOVM_GuestPassword");
        if (string.IsNullOrWhiteSpace(password))
            return null;

        var user = Environment.GetEnvironmentVariable("PROJETOVM_GuestUser");
        if (string.IsNullOrWhiteSpace(user))
            user = "analyst";

        return new VmGuestCredentials(user.Trim(), password);
    }

    public static VmGuestCredentials? TryGetSession() => _session;

    public static void SetSession(VmGuestCredentials credentials) =>
        _session = credentials ?? throw new ArgumentNullException(nameof(credentials));
}
