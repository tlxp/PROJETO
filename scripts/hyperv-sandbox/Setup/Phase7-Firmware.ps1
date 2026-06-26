# --- Módulo: Phase7-Firmware.ps1 ---
# --- Configuração de firmware UEFI/Secure Boot (Gen2) ---

if ($VMGeneration -eq 2) {
    Write-Host "[7/8] Firmware UEFI (SecureBoot Off)..."
    # Secure Boot desligado para permitir boot a partir do ISO de instalação
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off | Out-Null
    $sb = (Get-VMFirmware -VMName $VMName).SecureBoot
    Write-Host "      SecureBoot: $sb"
} else {
    Write-Host "[7/8] Firmware: Gen1 BIOS - sem UEFI/SecureBoot."
}
