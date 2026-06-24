# --- Script: Hashing.ps1 ---

# --- Validação SHA-1 de ficheiro ---
function Assert-FileSha1 {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ExpectedSha1,
        [string] $Label = "ficheiro"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "O $Label n-o foi encontrado em: $Path"
    }

    # *Normalizar hash esperado (sem espaços, minúsculas)*
    $expected = ($ExpectedSha1 -replace '\s', '').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        throw "SHA-1 esperado vazio para o $Label (config inv-lida)."
    }

    $actual = $null
    try {
        $h = Get-FileHash -LiteralPath $Path -Algorithm SHA1 -ErrorAction Stop
        $actual = ($h.Hash -replace '\s', '').ToLowerInvariant()
    } catch {
        throw "Falha ao calcular SHA-1 do $Label em '$Path': $($_.Exception.Message)"
    }

    if ($actual -ne $expected) {
        throw "SHA-1 do $Label N-O coincide. Esperado: $expected | Atual: $actual | Ficheiro: $Path"
    }

    # *Devolver o hash calculado para diagnóstico/logs*
    return $actual
}

# --- Validação SHA-256 de ficheiro ---
function Assert-FileSha256 {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ExpectedSha256,
        [string] $Label = "ficheiro"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "O $Label não foi encontrado em: $Path"
    }

    $expected = ($ExpectedSha256 -replace '\s', '').ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($expected)) {
        throw "SHA-256 esperado vazio para o $Label."
    }

    $actual = $null
    try {
        $h = Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop
        $actual = ($h.Hash -replace '\s', '').ToUpperInvariant()
    } catch {
        throw "Falha ao calcular SHA-256 do $Label em '$Path': $($_.Exception.Message)"
    }

    if ($actual -ne $expected) {
        throw "SHA-256 do $Label NÃO coincide. Esperado: $expected | Atual: $actual | Ficheiro: $Path"
    }

    return $actual
}
