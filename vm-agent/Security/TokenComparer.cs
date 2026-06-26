// --- Módulo: TokenComparer.cs ---
// Comparação de tokens em tempo constante contra timing attacks.


using System.Security.Cryptography;
using System.Text;



namespace VmAgent.Security;



// --- Comparação segura de tokens ---
internal static class TokenComparer
{
    // --- Compara duas strings em tempo constante ---
    public static bool FixedTimeEquals(string? a, string? b)
    {
        if (a is null || b is null)
            return false;



        // *evita timing attacks ao comparar bytes com comprimento igual*
        var ba = Encoding.UTF8.GetBytes(a);
        var bb = Encoding.UTF8.GetBytes(b);
        return ba.Length == bb.Length && CryptographicOperations.FixedTimeEquals(ba, bb);
    }
}

