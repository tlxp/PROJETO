namespace VmAgent.Models;

public sealed class RunRequest
{
    public int TimeoutSeconds { get; set; } = Configuration.AgentLimits.DefaultRunTimeoutSeconds;
}
