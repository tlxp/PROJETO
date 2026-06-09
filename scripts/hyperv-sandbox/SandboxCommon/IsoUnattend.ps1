# Funções de ISO / autounattend.xml / VHDX / idiomas (parte do SandboxCommon).
# Originalmente um único ficheiro; subdividido em .\IsoUnattend\ e carregado via
# dot-sourcing. Este ficheiro é ele próprio carregado via dot-sourcing por
# SandboxCommon.psm1, por isso as funções acabam no scope do módulo e são
# exportadas normalmente.
$IsoUnattendPartsDir = Join-Path $PSScriptRoot 'IsoUnattend'
foreach ($part in @(
    'MediaAndLanguages.ps1',         # candidatos de media, idiomas da imagem/UI
    'IsoCreation.ps1',               # New-IsoFromFolder, New-WindowsIsoWithUnattend
    'VhdxUnattend.ps1',              # New-UnattendVhdx
    'UnattendXml.ps1',               # New-Windows10UnattendXml
    'LanguageAndUnattendTweaks.ps1'  # idioma default do ISO, ajustes ao autounattend
)) {
    . (Join-Path $IsoUnattendPartsDir $part)
}
