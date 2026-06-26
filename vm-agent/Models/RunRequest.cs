// --- Módulo: RunRequest.cs ---
// Modelo de pedido de execução de amostra com timeout.


namespace VmAgent.Models;



// --- Pedido de execução de amostra ---
public sealed class RunRequest
{
    public int TimeoutSeconds { get; set; } = Configuration.AgentLimits.DefaultRunTimeoutSeconds;
}

