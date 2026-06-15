namespace VmAgent.Configuration;

internal static class AgentLimits
{
    public const long MaxUploadBytes = 200L * 1024 * 1024;
    public const int DefaultRunTimeoutSeconds = 300;
    public const int MaxRunTimeoutSeconds = 600;
    public const int MaxCapturedOutputChars = 1024 * 1024;
}
