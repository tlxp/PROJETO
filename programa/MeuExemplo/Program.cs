// Exemplo educativo para a GUI Tkinter (arrastar Program.cs → compilar → analisar).
// Não é malware — apenas strings e APIs comuns para experimentar o analisador estático.

using System.Net.Http;

Console.WriteLine("RAT Analyzer — MeuExemplo");

const string demoEndpoint = "https://example.com/api/status";
Console.WriteLine($"Endpoint de demonstração: {demoEndpoint}");

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
