# Hyper-V
Write-Host "[1/8] Verificando Hyper-V..."
$hv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
if ($hv.State -ne "Enabled") {
    Write-Host "      A ativar Hyper-V (requer reinicio)..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All | Out-Null
    Write-Host "      Reinicie e execute o script novamente."
    exit 0
}
Write-Host "      Hyper-V ativo. Geracao configurada: Gen$VMGeneration"

