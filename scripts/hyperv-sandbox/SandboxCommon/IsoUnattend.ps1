# --- Módulo: IsoUnattend.ps1 ---
# --- Orquestração ISO, autounattend e VHDX ---

# --- Carregamento dos módulos ISO / autounattend ---
# Funções de ISO, autounattend.xml, VHDX e idiomas (parte do SandboxCommon).
# Originalmente um único ficheiro; subdividido em .\IsoUnattend\ e carregado via dot-sourcing.
# Este ficheiro é carregado por SandboxCommon.psm1; as funções ficam no scope do módulo.
$IsoUnattendPartsDir = Join-Path $PSScriptRoot 'IsoUnattend'
foreach ($part in @(
    'MediaAndLanguages.ps1',
    'IsoCreation.ps1',
    'VhdxUnattend.ps1',
    'UnattendXml.ps1',
    'LanguageAndUnattendTweaks.ps1'
)) {
    . (Join-Path $IsoUnattendPartsDir $part)
}
