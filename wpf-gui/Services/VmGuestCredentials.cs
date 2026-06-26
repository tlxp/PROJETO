// --- Módulo: VmGuestCredentials.cs ---
// Credenciais de convidado da VM guardadas de forma segura.
using System;



namespace RatAnalyzer.Desktop.Services;



// --- Par utilizador/palavra-passe da VM guest ---
public sealed record VmGuestCredentials(string Username, string Password);



// --- Armazena credenciais da VM (env ou sessão da aplicação) ---
public static class VmGuestCredentialStore
{
    private static VmGuestCredentials? _session;



    // --- Tenta a partir de ambiente ---
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



    // --- Tenta Get Session ---
    public static VmGuestCredentials? TryGetSession() => _session;



    // --- Define Session ---
    public static void SetSession(VmGuestCredentials credentials) =>
        _session = credentials ?? throw new ArgumentNullException(nameof(credentials));
}

