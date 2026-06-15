using System.Security.Cryptography;
using System.Text;

namespace VmAgent.Security;

internal static class TokenComparer
{
    public static bool FixedTimeEquals(string? a, string? b)
    {
        if (a is null || b is null)
            return false;

        var ba = Encoding.UTF8.GetBytes(a);
        var bb = Encoding.UTF8.GetBytes(b);
        return ba.Length == bb.Length && CryptographicOperations.FixedTimeEquals(ba, bb);
    }
}
