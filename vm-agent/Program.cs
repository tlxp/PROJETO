using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<AnalysisState>();
builder.Services.AddSingleton<RunGate>();

builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 200 * 1024 * 1024; // 200 MB
});

var app = builder.Build();

var agentToken = Environment.GetEnvironmentVariable("VM_AGENT_TOKEN");
var allowInsecure = string.Equals(
    Environment.GetEnvironmentVariable("VM_AGENT_ALLOW_INSECURE"),
    "1",
    StringComparison.Ordinal);

if (string.IsNullOrWhiteSpace(agentToken))
{
    if (!allowInsecure)
    {
        Console.Error.WriteLine(
            "[vm-agent] ERRO: VM_AGENT_TOKEN é obrigatório. " +
            "Defina VM_AGENT_TOKEN e use bind interno (ex.: http://192.168.100.x:5000). " +
            "Em dev local apenas, pode usar VM_AGENT_ALLOW_INSECURE=1.");
        Environment.Exit(1);
    }

    Console.Error.WriteLine(
        "[vm-agent] AVISO: VM_AGENT_ALLOW_INSECURE=1 — API aberta na rede da VM.");
}

app.Use(async (context, next) =>
{
    if (!string.IsNullOrWhiteSpace(agentToken))
    {
        if (!context.Request.Headers.TryGetValue("X-Agent-Token", out var provided) ||
            !FixedTimeEquals(provided.ToString(), agentToken))
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            await context.Response.WriteAsJsonAsync(new { detail = "Token inválido ou em falta (header X-Agent-Token)." });
            return;
        }
    }

    await next();
});

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

    if (file.Length > 200 * 1024 * 1024)
    {
        return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);
    }

    var safeName = Path.GetFileName(file.FileName);
    if (string.IsNullOrWhiteSpace(safeName) ||
        safeName is "." or ".." ||
        safeName.Contains("..", StringComparison.Ordinal))
    {
        return Results.BadRequest(new { detail = "Nome de ficheiro inválido." });
    }

    var baseDir = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "samples"));
    Directory.CreateDirectory(baseDir);
    var targetPath = Path.GetFullPath(Path.Combine(baseDir, safeName));

    if (!targetPath.StartsWith(baseDir + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) &&
        !string.Equals(targetPath, baseDir, StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest(new { detail = "Caminho de destino inválido." });
    }

    state.Reset();

    await using (var fs = File.Create(targetPath))
    await using (var stream = file.OpenReadStream())
    {
        await stream.CopyToAsync(fs);
    }

    state.SamplePath = targetPath;
    state.SampleFileName = safeName;

    return Results.Ok(new { status = "uploaded", fileName = safeName });
});

app.MapPost("/api/run", async (RunRequest req, AnalysisState state, RunGate gate) =>
{
    if (!await gate.TryEnterAsync())
    {
        return Results.Conflict(new { detail = "Já existe uma execução em curso." });
    }

    try
    {
        if (string.IsNullOrEmpty(state.SamplePath) || !File.Exists(state.SamplePath))
        {
            return Results.BadRequest(new { detail = "Nenhuma amostra carregada. Chame /api/upload primeiro." });
        }

        var timeoutSeconds = req.TimeoutSeconds > 0 ? req.TimeoutSeconds : 300;
        timeoutSeconds = Math.Min(timeoutSeconds, 600);

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
        const int maxCaptureChars = 1024 * 1024;

        proc.OutputDataReceived += (_, e) =>
        {
            if (e.Data is not null && stdout.Length < maxCaptureChars)
                stdout.AppendLine(e.Data);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null && stderr.Length < maxCaptureChars)
                stderr.AppendLine(e.Data);
        };

        proc.Start();
        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        var cts = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        try
        {
            await proc.WaitForExitAsync(cts.Token);
        }
        catch (OperationCanceledException)
        {
            try { if (!proc.HasExited) proc.Kill(true); } catch { /* ignorar */ }
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
    finally
    {
        gate.Release();
    }
});

app.MapGet("/api/report", (AnalysisState state) =>
{
    if (state.LastBehavior is null)
    {
        return Results.BadRequest(new { detail = "Nenhuma execução registada ainda." });
    }

    var behavior = new
    {
        status = state.LastBehavior.GetValueOrDefault("status") ?? "unknown",
        startedAt = state.LastBehavior.GetValueOrDefault("startedAt"),
        finishedAt = state.LastBehavior.GetValueOrDefault("finishedAt"),
        fileName = state.LastBehavior.GetValueOrDefault("fileName"),
        exitCode = state.LastBehavior.GetValueOrDefault("exitCode"),
        stdout = state.LastBehavior.GetValueOrDefault("stdout"),
        stderr = state.LastBehavior.GetValueOrDefault("stderr"),
        monitoring = "not_implemented",
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

static bool FixedTimeEquals(string? a, string? b)
{
    if (a is null || b is null) return false;
    var ba = Encoding.UTF8.GetBytes(a);
    var bb = Encoding.UTF8.GetBytes(b);
    return ba.Length == bb.Length && CryptographicOperations.FixedTimeEquals(ba, bb);
}

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

public sealed class RunGate
{
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<bool> TryEnterAsync()
    {
        return await _gate.WaitAsync(0);
    }

    public void Release() => _gate.Release();
}

public sealed class RunRequest
{
    public int TimeoutSeconds { get; set; } = 300;
}
