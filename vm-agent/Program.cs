// --- Módulo: Program.cs ---
// Ponto de entrada do agente VM com API Minimal .NET na sandbox.


using VmAgent.Configuration;
using VmAgent.Endpoints;
using VmAgent.Security;
using VmAgent.State;



// --- Configuração do host Kestrel e serviços singleton ---
var builder = WebApplication.CreateBuilder(args);



builder.Services.AddSingleton<AnalysisState>();
builder.Services.AddSingleton<RunGate>();



builder.WebHost.ConfigureKestrel(options =>
{
    // *Limita tamanho máximo do corpo do pedido (upload de amostra)*
    options.Limits.MaxRequestBodySize = AgentLimits.MaxUploadBytes;
});



var app = builder.Build();



// --- Validação do token de autenticação antes de aceitar pedidos ---
var agentToken = AgentTokenMiddleware.ResolveTokenFromEnvironment();
var allowInsecure = AgentTokenMiddleware.IsInsecureDevMode();



if (!AgentTokenMiddleware.ValidateStartupToken(agentToken, allowInsecure))
{
    Environment.Exit(1);
}



app.UseAgentTokenAuth(agentToken);
app.MapAgentEndpoints();



app.Run();



// --- Expõe o tipo gerado para WebApplicationFactory nos testes de integração ---
public partial class Program;

