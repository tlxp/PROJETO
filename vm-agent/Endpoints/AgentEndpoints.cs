// --- Módulo: AgentEndpoints.cs ---
// Endpoints HTTP /api/* do agente de análise na VM.


using VmAgent.Configuration;
using VmAgent.Models;
using VmAgent.Services;
using VmAgent.State;



namespace VmAgent.Endpoints;



// --- Endpoints HTTP da API do agente ---
internal static class AgentEndpoints
{
    // --- Mapeia rotas /api/* na aplicação ---
    public static void MapAgentEndpoints(this WebApplication app)
    {
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



            if (file.Length > AgentLimits.MaxUploadBytes)
            {
                return Results.StatusCode(StatusCodes.Status413PayloadTooLarge);
            }



            var safeName = Path.GetFileName(file.FileName);
            if (!SampleStorage.TryResolveTargetPath(safeName, out var targetPath, out var pathError))
            {
                return Results.BadRequest(new { detail = pathError });
            }



            // *nova amostra invalida estado de execuções anteriores*
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
                return await SampleRunner.RunAsync(req, state);
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



            // *relatório mínimo — telemetria avançada ainda não implementada*
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
    }
}

