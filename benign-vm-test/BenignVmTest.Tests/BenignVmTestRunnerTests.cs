using System.Text;
using Xunit;

namespace BenignVmTest.Tests;

public sealed class BenignVmTestRunnerTests
{
    [Fact]
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
