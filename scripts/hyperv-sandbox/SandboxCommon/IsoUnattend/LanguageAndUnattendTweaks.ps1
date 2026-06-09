function Get-WindowsIsoDefaultLanguage {
    <#
    .SYNOPSIS
        Deteta o idioma default de um ISO do Windows (ex.: en-US, pt-PT) lendo sources\lang.ini.
    .DESCRIPTION
        O idioma do ISO afeta o comportamento do autounattend (Microsoft-Windows-International-Core-WinPE).
        Quando o autounattend fixa en-US mas o ISO é pt-PT (ou outro), o setup pode ignorar partes do unattended
        ou pedir input manual. Esta função tenta inferir o idioma do ISO para alinhar o autounattend.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $IsoPath,
        # Quando não é possível ler lang.ini, devolver $null (não fingir en-US — evita logs enganadores).
        [string] $Fallback = $null
    )

    if (-not (Test-Path -LiteralPath $IsoPath)) { return $Fallback }

    $mounted = $false
    try {
        Mount-DiskImage -ImagePath $IsoPath -StorageType ISO -ErrorAction Stop | Out-Null
        $mounted = $true
        Start-Sleep -Milliseconds 1200

        $vol = Get-DiskImage -ImagePath $IsoPath | Get-Volume | Select-Object -First 1
        $isoDrive = if ($vol -and $vol.DriveLetter) { "$($vol.DriveLetter):\" } else { $null }
        if (-not $isoDrive) { return $Fallback }

        $langIniCandidates = @(
            (Join-Path $isoDrive "sources\lang.ini"),
            (Join-Path $isoDrive "x64\sources\lang.ini"),
            (Join-Path $isoDrive "x86\sources\lang.ini")
        )

        foreach ($p in $langIniCandidates) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            $lines = Get-Content -LiteralPath $p -ErrorAction SilentlyContinue
            if (-not $lines) { continue }
            foreach ($line in $lines) {
                if ($line -match '^\s*Default\s*=\s*([A-Za-z]{2}-[A-Za-z]{2})\s*$') {
                    return $Matches[1]
                }
            }
        }

        $wimLangs = @(Get-WindowsImageLanguagesFromInstallMedia -IsoRoot $isoDrive)
        if ($wimLangs.Count -gt 0) {
            $first = [string]$wimLangs[0]
            if ($first -match '^[a-zA-Z]{2}-[a-zA-Z]{2,}$') { return $first }
        }

        return $Fallback
    } catch {
        return $Fallback
    } finally {
        if ($mounted) {
            try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch { }
        }
    }
}

function Set-UnattendLanguageInPlace {
    <#
    .SYNOPSIS
        Substitui idioma/locale no autounattend.xml (WinPE + OOBE) para alinhar com o ISO.
    .DESCRIPTION
        Atualiza os nós mais comuns: SetupUILanguage/UILanguage, InputLocale, SystemLocale, UILanguage, UserLocale.
        Se o ficheiro não contiver esses nós, não faz nada (mantém comportamento default do ISO).
    #>
    param(
        [Parameter(Mandatory = $true)][string] $UnattendXmlPath,
        [Parameter(Mandatory = $true)][string] $UiLanguage
    )

    if (-not (Test-Path -LiteralPath $UnattendXmlPath)) { return }
    if ([string]::IsNullOrWhiteSpace($UiLanguage)) { return }
    if ($UiLanguage -notmatch '^[a-zA-Z]{2}-[a-zA-Z]{2,}$') {
        Write-Warning "Set-UnattendLanguageInPlace: ignorando idioma invalido '$UiLanguage' (esperado xx-YY, ex.: en-US)."
        return
    }

    $xmlText = Get-Content -LiteralPath $UnattendXmlPath -Raw -ErrorAction Stop

    # WinPE / OOBE / general: substituir valores simples (ex.: en-US, pt-PT).
    $xmlText = [regex]::Replace($xmlText, '<UILanguage>\s*[^<]+\s*</UILanguage>', "<UILanguage>$UiLanguage</UILanguage>")
    $xmlText = [regex]::Replace($xmlText, '<InputLocale>\s*[^<]+\s*</InputLocale>', "<InputLocale>$UiLanguage</InputLocale>")
    $xmlText = [regex]::Replace($xmlText, '<SystemLocale>\s*[^<]+\s*</SystemLocale>', "<SystemLocale>$UiLanguage</SystemLocale>")
    $xmlText = [regex]::Replace($xmlText, '<UserLocale>\s*[^<]+\s*</UserLocale>', "<UserLocale>$UiLanguage</UserLocale>")

    Set-Content -LiteralPath $UnattendXmlPath -Value $xmlText -Encoding UTF8 -ErrorAction Stop
}

function Remove-UnattendInternationalSettings {
    <#
    .SYNOPSIS
        Remove componentes de idioma/locale do autounattend.xml para deixar o Setup seguir o idioma do ISO.
    .DESCRIPTION
        Em alguns ISOs não-en-US, forçar valores de locale pode fazer o unattended falhar ou pedir prompts.
        Esta função remove:
        - Microsoft-Windows-International-Core-WinPE (pass windowsPE)
        - Microsoft-Windows-International-Core (pass oobeSystem)
        Mantém o resto do autounattend intacto.
        NÃO usar no autounattend custom Gen1 (en-US): sem International-Core-WinPE o WinPE não aplica
        SetupUILanguage e o setup deixa de ser silencioso.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $UnattendXmlPath
    )

    if (-not (Test-Path -LiteralPath $UnattendXmlPath)) { return }

    $xmlText = Get-Content -LiteralPath $UnattendXmlPath -Raw -ErrorAction Stop

    # Remover bloco WinPE international core
    $xmlText = [regex]::Replace(
        $xmlText,
        '<component\s+name="Microsoft-Windows-International-Core-WinPE"[\s\S]*?</component>\s*',
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # Remover bloco OOBE international core
    $xmlText = [regex]::Replace(
        $xmlText,
        '<component\s+name="Microsoft-Windows-International-Core"[\s\S]*?</component>\s*',
        '',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    Set-Content -LiteralPath $UnattendXmlPath -Value $xmlText -Encoding UTF8 -ErrorAction Stop
}
