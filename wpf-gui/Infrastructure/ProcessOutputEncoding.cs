// --- Módulo: ProcessOutputEncoding.cs ---
// Codificação e normalização da saída de processos filhos no Windows.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
namespace RatAnalyzer.Desktop.Infrastructure;
// --- Codificação de stdout/stderr de processos filhos no Windows e normalização para a UI WPF ---
public static class ProcessOutputEncoding
{
    private static readonly Encoding Utf8 = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);
    private static readonly Regex AnsiEscape = new(@"\x1B\[[0-9;?]*[ -/]*[@-~]|\x1B\][^\x07]*(?:\x07|\x1B\\)", RegexOptions.Compiled);
    // --- ANSI/OEM da consola (cmd, ferramentas legadas) ---
    public static Encoding ConsoleEncoding => ResolveConsoleEncoding();
    // --- Windows-1252 — saída redirecionada típica do Windows PowerShell 5.x ---
    public static Encoding WindowsAnsiEncoding => ResolveWindowsAnsiEncoding();
    // --- Aplica Console ---
    public static void ApplyConsole(ProcessStartInfo psi)
    {
        if (psi.RedirectStandardOutput)
            psi.StandardOutputEncoding = ConsoleEncoding;
        if (psi.RedirectStandardError)
            psi.StandardErrorEncoding = ConsoleEncoding;
    }
    // --- Aplica Windows Ansi ---
    public static void ApplyWindowsAnsi(ProcessStartInfo psi)
    {
        if (psi.RedirectStandardOutput)
            psi.StandardOutputEncoding = WindowsAnsiEncoding;
        if (psi.RedirectStandardError)
            psi.StandardErrorEncoding = WindowsAnsiEncoding;
    }
    // --- Aplica Utf 8 ---
    public static void ApplyUtf8(ProcessStartInfo psi)
    {
        if (psi.RedirectStandardOutput)
            psi.StandardOutputEncoding = Utf8;
        if (psi.RedirectStandardError)
            psi.StandardErrorEncoding = Utf8;
    }
    // --- Aplica Python Utf 8 ambiente ---
    public static void ApplyPythonUtf8Environment(ProcessStartInfo psi)
    {
        psi.Environment["PYTHONIOENCODING"] = "utf-8";
        psi.Environment["PYTHONUTF8"] = "1";
    }
    // --- Prefixo para cmd.exe emitir UTF-8 (npm, etc.) ---
    public static string CmdUtf8Command(string command)
        => "/c chcp 65001 >nul & " + command;
    // --- Resolve executáveis no PATH (ex.: npm.cmd) quando UseShellExecute é false ---
    public static string ResolveExecutable(string command)
    {
        if (string.IsNullOrWhiteSpace(command))
            return command;
        if (command.Contains(Path.DirectorySeparatorChar, StringComparison.Ordinal)
            || command.Contains(Path.AltDirectorySeparatorChar, StringComparison.Ordinal))
            return command;
        if (!OperatingSystem.IsWindows())
            return command;
        var pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(pathEnv))
            return command;
        var extensions = (Environment.GetEnvironmentVariable("PATHEXT") ?? ".EXE;.CMD;.BAT;.COM")
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var dir in pathEnv.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir))
                continue;
            foreach (var ext in extensions)
            {
                var suffix = ext.StartsWith('.') ? ext : "." + ext;
                var candidate = Path.Combine(dir, command + suffix);
                if (File.Exists(candidate))
                    return candidate;
            }
            var bare = Path.Combine(dir, command);
            if (File.Exists(bare))
                return bare;
        }
        return command;
    }
    // --- Limpa escapes ANSI, repara mojibake comum e remove caracteres inválidos ---
    public static string NormalizeForDisplay(string? text)
    {
        if (string.IsNullOrEmpty(text))
            return string.Empty;
        var s = AnsiEscape.Replace(text, string.Empty);
        s = s.Replace("\uFEFF", string.Empty);
        s = TryRepairMojibake(s);
        return StripInvalidChars(s);
    }
    // --- Resolve Console codificação ---
    private static Encoding ResolveConsoleEncoding()
    {
        try
        {
            return Encoding.GetEncoding(Console.OutputEncoding.CodePage);
        }
        catch
        {
            try
            {
                return Encoding.GetEncoding(850);
            }
            catch
            {
                return ResolveWindowsAnsiEncoding();
            }
        }
    }
    // --- Resolve Windows Ansi codificação ---
    private static Encoding ResolveWindowsAnsiEncoding()
    {
        try
        {
            return Encoding.GetEncoding(1252);
        }
        catch
        {
            return Encoding.Latin1;
        }
    }
    // --- Tenta Repair Mojibake ---
    private static string TryRepairMojibake(string text)
    {
        if (!LooksLikeMojibake(text))
            return text;
        var best = text;
        var bestScore = MojibakeScore(text);
        foreach (var source in MojibakeSourceEncodings())
        {
            try
            {
                var candidate = Encoding.UTF8.GetString(source.GetBytes(text));
                var score = MojibakeScore(candidate);
                if (score < bestScore)
                {
                    best = candidate;
                    bestScore = score;
                }
            }
            catch
            {
                // ignorar
            }
        }
        return best;
    }
    // --- Mojibake Source Encodings ---
    private static IEnumerable<Encoding> MojibakeSourceEncodings()
    {
        yield return ResolveWindowsAnsiEncoding();
        var oem = TryGetEncoding(850);
        if (oem != null)
            yield return oem;
        yield return Encoding.Latin1;
    }
    // --- Tenta Get codificação ---
    private static Encoding? TryGetEncoding(int codePage)
    {
        try
        {
            return Encoding.GetEncoding(codePage);
        }
        catch
        {
            return null;
        }
    }
    // --- parece como Mojibake ---
    private static bool LooksLikeMojibake(string text)
    {
        return text.Contains('\uFFFD', StringComparison.Ordinal)
               || text.Contains("Ã", StringComparison.Ordinal)
               || text.Contains("â€", StringComparison.Ordinal)
               || text.Contains("ÔöÇ", StringComparison.Ordinal)
               || text.Contains("Ôöé", StringComparison.Ordinal);
    }
    // --- Mojibake Score ---
    private static int MojibakeScore(string text)
    {
        var score = 0;
        foreach (var ch in text)
        {
            if (ch == '\uFFFD')
                score += 10;
            else if (ch is 'Ã' or 'Â' or '¤' or '¢')
                score += 2;
            else if (char.IsControl(ch) && ch is not '\r' and not '\n' and not '\t')
                score += 3;
        }
        return score;
    }
    // --- Strip inválido caracteres ---
    private static string StripInvalidChars(string text)
    {
        if (text.IndexOf('\uFFFD') < 0)
            return text;
        var sb = new StringBuilder(text.Length);
        foreach (var ch in text)
        {
            if (ch != '\uFFFD')
                sb.Append(ch);
        }
        return sb.ToString();
    }
}
