// --- Módulo: RunGate.cs ---

namespace VmAgent.State;

// --- Semáforo de execução única ---
public sealed class RunGate
{
    private readonly SemaphoreSlim _gate = new(1, 1);

    // --- Tenta adquirir o semáforo sem bloquear ---
    public async Task<bool> TryEnterAsync() => await _gate.WaitAsync(0);

    // --- Liberta o semáforo após execução ---
    public void Release() => _gate.Release();
}
