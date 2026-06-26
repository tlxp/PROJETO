// --- Módulo: BenignVmTestRunnerTests.cs ---
// Testes da sequência de log do runner inofensivo.


using System.Text;
using Xunit;



namespace BenignVmTest.Tests;



// --- Testes do runner inofensivo ---
public sealed class BenignVmTestRunnerTests
{
    // --- Run deve emitir sequência de log esperada no Windows ---
    [Fact]
    // --- Executa Writes esperada log sequência ---
    public void Run_WritesExpectedLogSequence()
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }



        var log = new StringWriter();
        var code = BenignVmTestRunner.Run(log);
        var output = log.ToString();



        Assert.Equal(0, code);
        Assert.Contains($"{BenignVmTestPaths.LogPrefix} início", output);
        Assert.Contains($"{BenignVmTestPaths.LogPrefix} ficheiro escrito:", output);
        Assert.Contains($"{BenignVmTestPaths.LogPrefix} registry escrito:", output);
        Assert.Contains($"{BenignVmTestPaths.LogPrefix} processo filho concluído:", output);
        Assert.Contains($"{BenignVmTestPaths.LogPrefix} fim", output);
    }
}

