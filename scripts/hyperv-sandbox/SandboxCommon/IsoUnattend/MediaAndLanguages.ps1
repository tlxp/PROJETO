function Get-WindowsIsoInstallMediaCandidates {
    param([Parameter(Mandatory = $true)][string] $IsoRoot)
    return @(
        (Join-Path $IsoRoot 'x64\sources\install.wim'),
        (Join-Path $IsoRoot 'x64\sources\install.esd'),
        (Join-Path $IsoRoot 'sources\install.wim'),
        (Join-Path $IsoRoot 'sources\install.esd'),
        (Join-Path $IsoRoot 'x86\sources\install.wim'),
        (Join-Path $IsoRoot 'x86\sources\install.esd')
    )
}

function Get-WindowsImageLanguagesFromInstallMedia {
    <#
    .SYNOPSIS
        Lista idiomas expostos pelo install.wim / install.esd (índice 1) via Get-WindowsImage.
        Fallback quando lang.ini não existe ou não tem [Available UI Languages] reconhecível.
    #>
    param([Parameter(Mandatory = $true)][string] $IsoRoot)

    foreach ($media in (Get-WindowsIsoInstallMediaCandidates -IsoRoot $IsoRoot)) {
        if (-not (Test-Path -LiteralPath $media)) { continue }
        try {
            $img = Get-WindowsImage -ImagePath $media -Index 1 -ErrorAction Stop
            if (-not $img.Languages) { continue }
            # Get-WindowsImage pode devolver Languages como string "en-US". Se passar pelo pipeline,
            # o PowerShell enumera CARACTERES — o primeiro "idioma" vira "e" e corrompe o autounattend.
            $langList = @()
            if ($img.Languages -is [string]) {
                $t = $img.Languages.Trim()
                if ($t) { $langList = @($t) }
            } else {
                $langList = @($img.Languages | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
            }
            if ($langList.Count -gt 0) { return $langList }
        } catch {
            continue
        }
    }
    return @()
}

function Get-WindowsIsoUiLanguages {
    <#
    .SYNOPSIS
        Devolve os idiomas de UI disponíveis no ISO (sources\lang.ini), se possível.
    .DESCRIPTION
        - Monta o ISO temporariamente e lê a secção [Available UI Languages] de lang.ini.
        - Procura em sources\lang.ini na raiz do volume **e** em x64\sources\lang.ini / x86\sources\lang.ini
          (estrutura típica de ISOs MCT / imagens só x64).
        - Se lang.ini não listar idiomas, tenta **install.wim / install.esd** com Get-WindowsImage (índice 1).
        - Se falhar, devolve lista vazia (o chamador decide fallback).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $IsoPath
    )

    $langs = @()
    if (-not (Test-Path -LiteralPath $IsoPath)) { return $langs }

    $mounted = $false
    try {
        Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -ErrorAction Stop | Out-Null
        $mounted = $true
        Start-Sleep -Milliseconds 1200

        $vol = Get-DiskImage -ImagePath $IsoPath | Get-Volume | Select-Object -First 1
        $isoDrive = if ($vol -and $vol.DriveLetter) { "$($vol.DriveLetter):\" } else { $null }
        if (-not $isoDrive) { return $langs }

        $langIniCandidates = @(
            (Join-Path $isoDrive "sources\lang.ini"),
            (Join-Path $isoDrive "x64\sources\lang.ini"),
            (Join-Path $isoDrive "x86\sources\lang.ini")
        )

        foreach ($langIni in $langIniCandidates) {
            if (-not (Test-Path -LiteralPath $langIni)) { continue }
            try {
                $content = Get-Content -LiteralPath $langIni -ErrorAction Stop
            } catch {
                continue
            }
            $inSection = $false
            foreach ($line in $content) {
                $t = ("" + $line).Trim()
                if ($t -match '^\[(.+)\]\s*$') {
                    $sec = $matches[1].Trim()
                    $inSection = ($sec -match '^(?i)available ui languages$')
                    continue
                }
                if (-not $inSection) { continue }
                if ([string]::IsNullOrWhiteSpace($t)) { continue }
                # Linha só com tag (en-US) ou chave=valor (en-US = 1 / en-US=true)
                if ($t -match '^\s*([a-zA-Z]{2}-[a-zA-Z]{2,})\s*(=.*)?$') {
                    $langs += $matches[1]
                }
            }
        }

        if (@($langs).Count -eq 0) {
            foreach ($wl in (Get-WindowsImageLanguagesFromInstallMedia -IsoRoot $isoDrive)) {
                $langs += $wl
            }
        }

        $langs = $langs | Sort-Object -Unique
        return $langs
    }
    catch {
        return @()
    }
    finally {
        if ($mounted) {
            try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
    }
}

