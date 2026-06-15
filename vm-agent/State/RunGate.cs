namespace VmAgent.State;

public sealed class RunGate
{
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<bool> TryEnterAsync() => await _gate.WaitAsync(0);

    public void Release() => _gate.Release();
}
