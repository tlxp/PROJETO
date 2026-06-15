using VmAgent.Configuration;
using VmAgent.Endpoints;
using VmAgent.Security;
using VmAgent.State;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<AnalysisState>();
builder.Services.AddSingleton<RunGate>();

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = AgentLimits.MaxUploadBytes;
});

var app = builder.Build();

var agentToken = AgentTokenMiddleware.ResolveTokenFromEnvironment();
var allowInsecure = AgentTokenMiddleware.IsInsecureDevMode();

if (!AgentTokenMiddleware.ValidateStartupToken(agentToken, allowInsecure))
{
    Environment.Exit(1);
}

app.UseAgentTokenAuth(agentToken);
app.MapAgentEndpoints();

app.Run();

// Expõe o tipo gerado para WebApplicationFactory nos testes de integração.
public partial class Program;
