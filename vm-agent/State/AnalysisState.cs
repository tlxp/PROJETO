namespace VmAgent.State;

public sealed class AnalysisState
{
    public string? SamplePath { get; set; }
    public string? SampleFileName { get; set; }
    public Dictionary<string, object?>? LastBehavior { get; set; }

    public void Reset()
    {
        SamplePath = null;
        SampleFileName = null;
        LastBehavior = null;
    }
}
