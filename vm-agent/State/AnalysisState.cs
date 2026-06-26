// --- Módulo: AnalysisState.cs ---
// Estado em memória da amostra carregada e última execução.


namespace VmAgent.State;



// --- Estado da análise em memória ---
public sealed class AnalysisState
{
    public string? SamplePath { get; set; }
    public string? SampleFileName { get; set; }
    public Dictionary<string, object?>? LastBehavior { get; set; }



    // --- Reinicia o estado da análise ---
    public void Reset()
    {
        // *limpa amostra carregada e resultado da última execução*
        SamplePath = null;
        SampleFileName = null;
        LastBehavior = null;
    }
}

