// --- Módulo: RunGateTests.cs ---

using VmAgent.State;
using Xunit;

namespace VmAgent.Tests;

// --- Testes do semáforo de execução única ---
public sealed class RunGateTests
{
    // --- Verifica que apenas um detentor é permitido de cada vez ---
    [Fact]
    public async Task TryEnterAsync_AllowsSingleConcurrentHolder()
    {
        var gate = new RunGate();

        // *primeira entrada deve ter sucesso*
        Assert.True(await gate.TryEnterAsync());
        // *segunda entrada deve falhar sem bloquear*
        Assert.False(await gate.TryEnterAsync());

        gate.Release();
        Assert.True(await gate.TryEnterAsync());
        gate.Release();
    }
}
