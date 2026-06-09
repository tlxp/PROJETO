# Firmware (apenas Gen2)
if ($VMGeneration -eq 2) {
    Write-Host "[7/8] Firmware UEFI (SecureBoot Off)..."
    Set-VMFirmware -VMName $VMName -EnableSecureBoot Off | Out-Null
    $sb = (Get-VMFirmware -VMName $VMName).SecureBoot
    Write-Host "      SecureBoot: $sb"
} else {
    Write-Host "[7/8] Firmware: Gen1 BIOS - sem UEFI/SecureBoot."
}
