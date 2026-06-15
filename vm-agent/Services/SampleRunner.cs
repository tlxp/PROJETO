using System.Diagnostics;
using System.Text;
using VmAgent.Configuration;
using VmAgent.Models;
using VmAgent.State;

namespace VmAgent.Services;

internal static class SampleRunner
{
    public static async Task<IResult> RunAsync(
        RunRequest req,
        AnalysisState state,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrEmpty(state.SamplePath) || !File.Exists(state.SamplePath))
        {
            return Results.BadRequest(new { detail = "Nenhuma amostra carregada. Chame /api/upload primeiro." });
        }

        var timeoutSeconds = req.TimeoutSeconds > 0 ? req.TimeoutSeconds : AgentLimits.DefaultRunTimeoutSeconds;
        timeoutSeconds = Math.Min(timeoutSeconds, AgentLimits.MaxRunTimeoutSeconds);

        var psi = new ProcessStartInfo
        {
            FileName = state.SamplePath,
            WorkingDirectory = Path.GetDirectoryName(state.SamplePath) ?? AppContext.BaseDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var startedAt = DateTime.UtcNow;
        state.LastBehavior = new Dictionary<string, object?>
        {
            ["status"] = "running",
            ["startedAt"] = startedAt.ToString("O"),
            ["fileName"] = state.SampleFileName
        };

        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        proc.OutputDataReceived += (_, e) =>
        {
            if (e.Data is not null && stdout.Length < AgentLimits.MaxCapturedOutputChars)
                stdout.AppendLine(e.Data);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null && stderr.Length < AgentLimits.MaxCapturedOutputChars)
                stderr.AppendLine(e.Data);
        };

        proc.Start();
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(TimeSpan.FromSeconds(timeoutSeconds));

        try
        {
            await proc.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                if (!proc.HasExited)
                    proc.Kill(true);
            }
            catch
            {
                // ignorar falha ao terminar processo após timeout
            }

            state.LastBehavior["status"] = "timeout";
            state.LastBehavior["exitCode"] = null;
            state.LastBehavior["stdout"] = stdout.ToString();
            state.LastBehavior["stderr"] = stderr.ToString();
            state.LastBehavior["finishedAt"] = DateTime.UtcNow.ToString("O");
            return Results.Ok(new { status = "timeout" });
        }

        state.LastBehavior["status"] = "finished";
        state.LastBehavior["exitCode"] = proc.ExitCode;
        state.LastBehavior["stdout"] = stdout.ToString();
        state.LastBehavior["stderr"] = stderr.ToString();
        state.LastBehavior["finishedAt"] = DateTime.UtcNow.ToString("O");

        return Results.Ok(new { status = "finished", exitCode = proc.ExitCode });
    }
}
