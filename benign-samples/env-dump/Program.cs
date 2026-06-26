// --- Módulo: Program.cs (BenignEnvDump) ---
// Amostra inofensiva: imprime variáveis de ambiente não sensíveis.
// --- Variáveis de ambiente não sensíveis ---
Console.WriteLine($"BenignEnvDump: OS={Environment.OSVersion.Version}");
Console.WriteLine($"BenignEnvDump: USER={Environment.UserName}");
Console.WriteLine($"BenignEnvDump: PROC={Environment.ProcessorCount}");
return 0;
