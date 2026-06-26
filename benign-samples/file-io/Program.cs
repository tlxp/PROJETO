// --- Módulo: Program.cs (BenignFileIo) ---
// Amostra inofensiva: escrita e leitura em %TEMP%.
// --- Escrita e leitura de marcador em %TEMP% ---
var path = Path.Combine(Path.GetTempPath(), "benign-file-io-marker.txt");
await File.WriteAllTextAsync(path, $"benign @ {DateTimeOffset.UtcNow:O}{Environment.NewLine}");
var text = await File.ReadAllTextAsync(path);
Console.WriteLine($"BenignFileIo: wrote {path} ({text.Length} chars)");
return 0;
