// --- Módulo: Program.cs (BenignRegistryRead) ---
// Amostra inofensiva: leitura de registry HKCU sem persistência.
using Microsoft.Win32;
// --- Leitura de valor HKCU sem escrita ---
var user = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion");
var name = user?.GetValue("ProgramFilesDir")?.ToString() ?? "(null)";
Console.WriteLine($"BenignRegistryRead: ProgramFilesDir={name}");
return 0;
