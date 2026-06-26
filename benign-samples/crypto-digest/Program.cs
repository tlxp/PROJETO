// --- Módulo: Program.cs (BenignCryptoDigest) ---
// Amostra inofensiva: hash SHA-256 local sem rede.
using System.Security.Cryptography;
using System.Text;
// --- Cálculo de digest SHA-256 ---
var bytes = Encoding.UTF8.GetBytes("benign-crypto-digest-sample");
var hash = Convert.ToHexString(SHA256.HashData(bytes));
Console.WriteLine($"BenignCryptoDigest: {hash[..16]}...");
return 0;
