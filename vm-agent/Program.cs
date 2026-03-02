using System.Diagnostics;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<AnalysisState>();

var app = builder.Build();

app.MapGet("/api/health", () => Results.Ok(new { status = "ok", component = "vm-agent" }));

app.MapPost("/api/upload", async (HttpRequest request, AnalysisState state) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest(new { detail = "Content-Type deve ser multipart/form-data." });
    }

    var form = await request.ReadFormAsync();
    var file = form.Files["file"];
    if (file is null || file.Length == 0)
    {
        return Results.BadRequest(new { detail = "Ficheiro 'file' em falta ou vazio." });
    }

    state.Reset();

    var baseDir = Path.Combine(AppContext.BaseDirectory, "samples");
    Directory.CreateDirectory(baseDir);
    var targetPath = Path.Combine(baseDir, file.FileName);

    await using (var fs = File.Create(targetPath))
    await using (var stream = file.OpenReadStream())
    {
        await stream.CopyToAsync(fs);
    }

    state.SamplePath = targetPath;

    return Results.Ok(new { status = "uploaded", fileName = file.FileName });
});

app.MapPost("/api/run", async (RunRequest req, AnalysisState state) =>
{
    if (string.IsNullOrEmpty(state.SamplePath) || !File.Exists(state.SamplePath))
    {
        return Results.BadRequest(new { detail = "Nenhuma amostra carregada. Chame /api/upload primeiro." });
    }

    var timeoutSeconds = req.TimeoutSeconds > 0 ? req.TimeoutSeconds : 300;

    var psi = new ProcessStartInfo
    {
        FileName = state.SamplePath,
        WorkingDirectory = Path.GetDirectoryName(state.SamplePath) ?? AppContext.BaseDirectory,
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true
    };

    var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
    var startedAt = DateTime.UtcNow;
    state.LastBehavior = new Dictionary<string, object?>
    {
        ["status"] = "running",
        ["startedAt"] = startedAt.ToString("O"),
        ["samplePath"] = state.SamplePath
    };

    proc.Start();

    var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
    try
    {
        await proc.WaitForExitAsync(cts.Token);
    }
    catch (OperationCanceledException)
    {
        try { if (!proc.HasExited) proc.Kill(true); } catch { /* ignore */ }
        state.LastBehavior["status"] = "timeout";
        state.LastBehavior["exitCode"] = null;
        state.LastBehavior["stdout"] = await proc.StandardOutput.ReadToEndAsync();
        state.LastBehavior["stderr"] = await proc.StandardError.ReadToEndAsync();
        state.LastBehavior["finishedAt"] = DateTime.UtcNow.ToString("O");
        return Results.Ok(new { status = "timeout" });
    }

    state.LastBehavior["status"] = "finished";
    state.LastBehavior["exitCode"] = proc.ExitCode;
    state.LastBehavior["stdout"] = await proc.StandardOutput.ReadToEndAsync();
    state.LastBehavior["stderr"] = await proc.StandardError.ReadToEndAsync();
    state.LastBehavior["finishedAt"] = DateTime.UtcNow.ToString("O");

    return Results.Ok(new { status = "finished", exitCode = proc.ExitCode });
});

app.MapGet("/api/report", (AnalysisState state) =>
{
    if (state.LastBehavior is null)
    {
        return Results.BadRequest(new { detail = "Nenhuma execução registada ainda." });
    }

    // Estrutura pensada para ser estendida com Sysmon/ETW no futuro.
    var behavior = new
    {
        status = state.LastBehavior.GetValueOrDefault("status") ?? "unknown",
        startedAt = state.LastBehavior.GetValueOrDefault("startedAt"),
        finishedAt = state.LastBehavior.GetValueOrDefault("finishedAt"),
        samplePath = state.LastBehavior.GetValueOrDefault("samplePath"),
        exitCode = state.LastBehavior.GetValueOrDefault("exitCode"),
        stdout = state.LastBehavior.GetValueOrDefault("stdout"),
        stderr = state.LastBehavior.GetValueOrDefault("stderr"),
        processes = Array.Empty<object>(),
        fileSystem = Array.Empty<object>(),
        registry = Array.Empty<object>(),
        network = Array.Empty<object>(),
        mutexes = Array.Empty<object>(),
        persistence = Array.Empty<object>(),
        privilegeEscalation = Array.Empty<object>(),
        sensitiveApiCalls = Array.Empty<object>()
    };

    return Results.Ok(behavior);
});

app.Run();

public sealed class AnalysisState
{
    public string? SamplePath { get; set; }

    public Dictionary<string, object?>? LastBehavior { get; set; }

    public void Reset()
    {
        SamplePath = null;
        LastBehavior = null;
    }
}

public sealed class RunRequest
{
    public int TimeoutSeconds { get; set; } = 300;
}

