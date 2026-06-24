// --- Módulo: RunRequest.cs ---

namespace VmAgent.Models;

// --- Pedido de execução de amostra ---
public sealed class RunRequest
{
    public int TimeoutSeconds { get; set; } = Configuration.AgentLimits.DefaultRunTimeoutSeconds;
}
