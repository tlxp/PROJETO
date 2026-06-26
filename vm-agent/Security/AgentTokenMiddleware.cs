// --- Módulo: AgentTokenMiddleware.cs ---
// Autenticação por token via header X-Agent-Token.


namespace VmAgent.Security;



// --- Autenticação por token do agente ---
internal static class AgentTokenMiddleware
{
    // --- Lê o token a partir da variável de ambiente ---
    public static string? ResolveTokenFromEnvironment()
    {
        return Environment.GetEnvironmentVariable("VM_AGENT_TOKEN");
    }



    // --- Verifica se o modo inseguro de desenvolvimento está ativo ---
    public static bool IsInsecureDevMode()
    {
        return string.Equals(
            Environment.GetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE"),
            "1",
            StringComparison.Ordinal);
    }



    // --- Valida o token no arranque da aplicação ---
    public static bool ValidateStartupToken(string? agentToken, bool allowInsecure)
    {
        if (!string.IsNullOrWhiteSpace(agentToken))
            return true;



        if (!allowInsecure)
        {
            // *token obrigatório em produção — instruções no stderr*
            Console.Error.WriteLine(
                "[vm-agent] ERRO: VM_AGENT_TOKEN é obrigatório. " +
                "Defina VM_AGENT_TOKEN e use bind interno (ex.: http://192.168.100.x:5000). " +
                "Em dev local apenas, pode usar VM_AGENT_ALLOW_INSECURE=1.");
            return false;
        }



        Console.Error.WriteLine(
            "[vm-agent] AVISO: VM_AGENT_ALLOW_INSECURE=1 — API aberta na rede da VM.");
        return true;
    }



    // --- Regista o middleware de autenticação por header ---
    public static void UseAgentTokenAuth(this WebApplication app, string? agentToken)
    {
        app.Use(async (context, next) =>
        {
            if (!string.IsNullOrWhiteSpace(agentToken))
            {
                // *rejeita pedidos sem header X-Agent-Token válido*
                if (!context.Request.Headers.TryGetValue("X-Agent-Token", out var provided) ||
                    !TokenComparer.FixedTimeEquals(provided.ToString(), agentToken))
                {
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    await context.Response.WriteAsJsonAsync(new
                    {
                        detail = "Token inválido ou em falta (header X-Agent-Token)."
                    });
                    return;
                }
            }



            await next();
        });
    }
}

