# Resolução automática de amostra + leitura de header PE (host).
# Carregado via dot-sourcing (mesmo scope).

function Resolve-AutoSamplePath {
    param([string] $ProvidedPath, [string] $SamplesDir)

    function Ensure-DefaultSampleExists {
        param([string] $Dir)

        $defaultPath = Join-Path $Dir "sample_autogen.exe"
        if (Test-Path -LiteralPath $defaultPath) { return $defaultPath }

        try { New-Item -ItemType Directory -Path $Dir -Force | Out-Null } catch { }

        # Gerar um executável inofensivo (para permitir um "fluxo 100% automático")
        # NOTA: usa Add-Type (csc) disponível no Windows.
        $src = @"
using System;
using System.IO;
using System.Threading;

public static class Program
{
    public static int Main(string[] args)
    {
        try
        {
            var work = @"C:\analysis_work";
            try { Directory.CreateDirectory(work); } catch { }
            var p = Path.Combine(work, "autogen_sample_ran.txt");
            File.WriteAllText(p, "ran at: " + DateTime.UtcNow.ToString("o"));
        }
        catch { }

        // Pequena pausa para existir "atividade" observável
        Thread.Sleep(1500);
        return 0;
    }
}
"@
        Add-Type -TypeDefinition $src -Language CSharp -OutputAssembly $defaultPath -OutputType ConsoleApplication -ErrorAction Stop | Out-Null
        return $defaultPath
    }

    if (-not [string]::IsNullOrWhiteSpace($ProvidedPath)) {
        if ([System.IO.File]::Exists($ProvidedPath)) { return [System.IO.Path]::GetFullPath($ProvidedPath) }
        Write-Error "Amostra não encontrada: $ProvidedPath"
        exit 1
    }

    if (-not (Test-Path -LiteralPath $SamplesDir)) {
        Write-Error "Pasta de samples não existe: $SamplesDir"
        exit 1
    }

    $candidate = Get-ChildItem -LiteralPath $SamplesDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".exe", ".dll") } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $candidate) {
        $auto = Ensure-DefaultSampleExists -Dir $SamplesDir
        if (-not (Test-Path -LiteralPath $auto)) {
            Write-Error "Nenhuma amostra encontrada e falhou ao criar sample automático em: $SamplesDir"
            exit 1
        }
        return $auto
    }
    return $candidate.FullName
}

function Get-PeMachineInfo {
    param([Parameter(Mandatory = $true)][string] $Path)
    try {
        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $br = New-Object System.IO.BinaryReader($fs)
            $mz = $br.ReadUInt16()
            if ($mz -ne 0x5A4D) { return @{ ok = $false; reason = "Não é um executável PE (sem header MZ)." } } # 'MZ'
            $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
            $peOff = $br.ReadUInt32()
            if ($peOff -lt 0 -or $peOff -gt ($fs.Length - 6)) { return @{ ok = $false; reason = "Header PE inválido (offset fora do ficheiro)." } }
            $fs.Seek([int64]$peOff, [System.IO.SeekOrigin]::Begin) | Out-Null
            $sig = $br.ReadUInt32()
            if ($sig -ne 0x00004550) { return @{ ok = $false; reason = "Não é um PE válido (assinatura PE\\0\\0 ausente)." } }
            $machine = $br.ReadUInt16()
            $machineName = switch ($machine) {
                0x014c { "x86" }
                0x8664 { "x64" }
                0x01c4 { "ARM" }
                0xAA64 { "ARM64" }
                default { ("0x{0:X4}" -f $machine) }
            }
            return @{ ok = $true; machine = $machine; machineName = $machineName }
        } finally {
            try { $fs.Dispose() } catch { }
        }
    } catch {
        return @{ ok = $false; reason = ("Falha ao ler header PE: " + $_.Exception.Message) }
    }
}
