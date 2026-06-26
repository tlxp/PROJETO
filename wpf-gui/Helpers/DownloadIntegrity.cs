// --- Módulo: DownloadIntegrity.cs ---
// Verificação SHA-256 de transferências de instaladores externos.
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;



namespace RatAnalyzer.Desktop.Helpers;



// --- Verificação de integridade (SHA-256) de ficheiros transferidos ---
internal static class DownloadIntegrity
{
    // --- Hash opcional do shim ilspycmd após instalação NuGet (versão pinada) ---
    public const string IlSpySha256Env = "RATANALYZER_ILSPY_SHA256";



    // --- Hash opcional de java.exe do JDK em uso (ex.: Temurin 21 via winget) ---
    public const string JavaExeSha256Env = "RATANALYZER_JAVA_EXE_SHA256";



    private static readonly Regex Sha256LineRegex = new(
        @"\b([0-9a-fA-F]{64})\b",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);



    // --- Calcula Sha 256 Hex ---
    public static string ComputeSha256Hex(string filePath)
    {
        using var sha = SHA256.Create();
        using var stream = File.OpenRead(filePath);
        var hash = sha.ComputeHash(stream);
        return Convert.ToHexString(hash);
    }



    // --- Verifica integridade de Sha 256 ou Throw ---
    public static void VerifySha256OrThrow(string filePath, string expectedHex)
    {
        if (string.IsNullOrWhiteSpace(expectedHex))
            throw new ArgumentException("Hash SHA-256 esperado em falta.", nameof(expectedHex));



        var actual = ComputeSha256Hex(filePath);
        if (!string.Equals(actual, expectedHex.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"SHA-256 do ficheiro não coincide com o esperado.{Environment.NewLine}" +
                $"Esperado: {expectedHex.Trim().ToUpperInvariant()}{Environment.NewLine}" +
                $"Obtido:   {actual}");
        }
    }



    // --- Calcula SHA-256, regista no log e valida apenas se a variável de ambiente estiver definida ---
    public static void LogAndVerifyOptionalEnvSha256(
        string filePath,
        string envVarName,
        Action<string> log,
        string label)
    {
        if (!File.Exists(filePath))
            throw new FileNotFoundException($"Ficheiro para verificação SHA-256 não encontrado: {filePath}");



        var actual = ComputeSha256Hex(filePath);
        log($"[INFO] {label} SHA-256: {actual}");



        var expected = Environment.GetEnvironmentVariable(envVarName);
        if (!string.IsNullOrWhiteSpace(expected))
        {
            VerifySha256OrThrow(filePath, expected);
            log($"[OK] {label} SHA-256 verificado ({envVarName}).");
        }
    }



    // --- Extrai o hash de um ficheiro .sha256 (formato GNU: hash + nome) ---
    public static string ParseSha256FileContent(string content)
    {
        if (string.IsNullOrWhiteSpace(content))
            throw new InvalidOperationException("Ficheiro SHA-256 vazio.");



        foreach (var line in content.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var m = Sha256LineRegex.Match(line);
            if (m.Success)
                return m.Groups[1].Value;
        }



        throw new InvalidOperationException("Não foi possível extrair SHA-256 do ficheiro de checksum.");
    }



    // --- Procura URL de um asset GitHub pelo nome (ex.: ficheiro.zip.sha256) ---
    public static string? TryFindGithubAssetUrl(string releaseJson, string assetFileName)
    {
        using var doc = JsonDocument.Parse(releaseJson);
        if (!doc.RootElement.TryGetProperty("assets", out var assets))
            return null;



        foreach (var a in assets.EnumerateArray())
        {
            if (!a.TryGetProperty("name", out var nameEl))
                continue;
            var name = nameEl.GetString();
            if (!string.Equals(name, assetFileName, StringComparison.OrdinalIgnoreCase))
                continue;
            if (!a.TryGetProperty("browser_download_url", out var urlEl))
                continue;
            return urlEl.GetString();
        }



        return null;
    }



    // --- Tenta Find GitHub Sha 256 asset URL ---
    public static string? TryFindGithubSha256AssetUrl(string releaseJson, string zipFileName)
    {
        if (string.IsNullOrWhiteSpace(zipFileName))
            return null;



        var direct = TryFindGithubAssetUrl(releaseJson, zipFileName + ".sha256");
        if (direct != null)
            return direct;



        // Alguns releases usam .SHA256 em maiúsculas
        return TryFindGithubAssetUrl(releaseJson, zipFileName + ".SHA256");
    }
}

