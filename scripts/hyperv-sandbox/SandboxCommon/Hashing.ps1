function Assert-FileSha1 {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $ExpectedSha1,
        [string] $Label = "ficheiro"
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "O $Label n-o foi encontrado em: $Path"
    }

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

    # Devolver o hash calculado para diagnóstico/logs
    return $actual
}
