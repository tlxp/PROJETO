# --- Script: Phase3-Iso.ps1 ---
# --- Validação da ISO Windows (obrigatório en-US) ---

Write-Host "[3/8] Verificando ISO..."

if ([string]::IsNullOrWhiteSpace($WindowsIsoPath) -or -not (Test-Path -LiteralPath $WindowsIsoPath)) {
    throw "ISO não encontrado em '$WindowsIsoPath'. Edite WindowsIsoPath em _Config.ps1."
}

$isoSizeGB = [Math]::Round((Get-Item -LiteralPath $WindowsIsoPath).Length / 1GB, 2)
Write-Host "      ISO: $WindowsIsoPath ($isoSizeGB GB)"
Write-Host "      ISO existe (sanity check rápido)."

# --- Deteção do idioma default da ISO ---
# *lê sources\lang.ini ou x64\sources\lang.ini; mensagens em ASCII para evitar erros de parse*
try {
    $isoLang = Get-WindowsIsoDefaultLanguage -IsoPath $WindowsIsoPath
    if ($isoLang) {
        Write-Host ('      Idioma default detetado do ISO: ' + $isoLang)
        Log ('ISO default language: ' + $isoLang)
    } else {
        Write-Host '      Idioma default do ISO: (não determinado - não foi possível ler Default= em lang.ini)'
        Log 'ISO default language: unknown (lang.ini Default= not found or unreadable)' 'WARN'
    }
} catch {
    $isoLang = $null
    Log ('AVISO: Falha ao detetar idioma default do ISO. Erro: ' + $_.Exception.Message) 'WARN'
}

# --- Verificação de en-US no unattended ---
# *o autounattend deste projeto assume en-US; falha se a ISO não o incluir*
try {
    $uiLangs = Get-WindowsIsoUiLanguages -IsoPath $WindowsIsoPath
    if ($uiLangs -and ($uiLangs -contains 'en-US')) {
        Write-Host ('      Idiomas UI disponiveis no ISO: ' + ($uiLangs -join ', '))
        Write-Host '      OK: ISO inclui en-US.'
        Log ('ISO UI languages: ' + ($uiLangs -join ', '))
    } else {
        $listed = if ($uiLangs) { ($uiLangs -join ', ') } else { '(não foi possível ler sources\lang.ini)' }
        throw ('ISO sem en-US. Idiomas detectados: ' + $listed)
    }
} catch {
    throw (
        'ISO invalida para este projeto: e necessária uma ISO do Windows em en-US. ' +
        "Coloque uma ISO en-US em '$WindowsIsoPath' (ver _Config.ps1) e tente novamente. " +
        'Detalhes: ' + $_.Exception.Message
    )
}
