# Localização de instaladores no host e cópia para a pasta partilhada.
# Carregado via dot-sourcing (mesmo scope).

function Find-InstallerOnHost {
    param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [switch] $AllowPattern,
        [string[]] $PackageCacheLeafNames = @()
    )

    $isPattern = $AllowPattern -and ($FileName -match "[\*\?]")

    # 1) Offline dir do repo (mais determinístico)
    if (-not $isPattern) {
        $p1 = Join-Path $OfflineDir $FileName
        if (Test-Path -LiteralPath $p1) { return $p1 }
    } else {
        try {
            $hit0 = Get-ChildItem -LiteralPath $OfflineDir -File -Filter $FileName -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                Select-Object -First 1
            if ($hit0) { return $hit0.FullName }
        } catch { }
    }

    # 2) SourceDir fornecido pelo utilizador
    if (-not [string]::IsNullOrWhiteSpace($SourceDir) -and (Test-Path -LiteralPath $SourceDir)) {
        if (-not $isPattern) {
            $p2 = Join-Path $SourceDir $FileName
            if (Test-Path -LiteralPath $p2) { return $p2 }
            # fallback: procurar por nome aproximado
            try {
                $hit = Get-ChildItem -LiteralPath $SourceDir -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ieq $FileName } |
                    Select-Object -First 1
                if ($hit) { return $hit.FullName }
            } catch { }
        } else {
            try {
                $hit = Get-ChildItem -LiteralPath $SourceDir -File -Recurse -Filter $FileName -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending |
                    Select-Object -First 1
                if ($hit) { return $hit.FullName }
            } catch { }
        }
    }

    # 3) Package Cache (quando o host já instalou o runtime no passado)
    $pkgRoot = "C:\ProgramData\Package Cache"
    if (Test-Path -LiteralPath $pkgRoot) {
        $leafs = @($FileName) + @($PackageCacheLeafNames)
        foreach ($leaf in $leafs) {
            try {
                if ($AllowPattern -and ($leaf -match "[\*\?]")) {
                    $hit2 = Get-ChildItem -LiteralPath $pkgRoot -File -Recurse -Filter $leaf -ErrorAction SilentlyContinue |
                        Sort-Object Name -Descending |
                        Select-Object -First 1
                } else {
                    $hit2 = Get-ChildItem -LiteralPath $pkgRoot -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ieq $leaf } |
                        Select-Object -First 1
                }
                if ($hit2) { return $hit2.FullName }
            } catch { }
        }
    }

    return $null
}

function Ensure-SharedInstaller {
    param(
        [Parameter(Mandatory = $true)][string] $FileName,
        [switch] $AllowPattern,
        [string[]] $CacheLeafs = @()
    )

    # Quando usamos padrões (wildcards), o ficheiro real pode ter versão no nome.
    if (-not ($AllowPattern -and ($FileName -match "[\*\?]"))) {
        $dst = Join-Path $SharedDir $FileName
        if (Test-Path -LiteralPath $dst) {
            return [pscustomobject]@{ HostPath = $dst; FileName = $FileName }
        }
    }

    $src = Find-InstallerOnHost -FileName $FileName -AllowPattern:$AllowPattern -PackageCacheLeafNames $CacheLeafs
    if (-not $src) { return $null }

    $realName = Split-Path -Leaf $src
    $dst = Join-Path $SharedDir $realName
    Copy-Item -LiteralPath $src -Destination $dst -Force
    return [pscustomobject]@{ HostPath = $dst; FileName = $realName }
}
