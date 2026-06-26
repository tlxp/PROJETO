// --- Módulo: Program.cs (BenignHttpMs) ---
// Amostra inofensiva: HTTP GET a URL Microsoft para testar FP C2.
using System.Net.Http;
// --- Pedido HTTP a domínio Microsoft ---
var url = "https://www.microsoft.com/";
using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
using var response = await client.GetAsync(url);
Console.WriteLine($"BenignHttpMs: {(int)response.StatusCode} {url}");
return response.IsSuccessStatusCode ? 0 : 1;
