// --- Módulo: Program.cs ---
// Exemplo de demonstração com pedido HTTP opcional.
using System.Net.Http;
// --- Mensagem de arranque ---
Console.WriteLine("RAT Analyzer — MeuExemplo");
// --- Endpoint de demonstração ---
const string demoEndpoint = "https://example.com/api/status";
Console.WriteLine($"Endpoint de demonstração: {demoEndpoint}");
// --- Pedido HTTP de demonstração ---
// *falha esperada se offline*
using var client = new HttpClient();
try
{
    var response = await client.GetAsync(demoEndpoint);
    Console.WriteLine($"HTTP {(int)response.StatusCode}");
}
catch (HttpRequestException ex)
{
    Console.WriteLine($"Pedido falhou (esperado offline): {ex.Message}");
}
return 0;
