# 3) Restaurar snapshot limpo
Write-LogHost "[3/7] A restaurar snapshot '$SnapshotName'..."
Stop-SandboxVM -VMName $VMName
Start-Sleep -Milliseconds 400
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      Snapshot restaurado."

# 4) Arrancar VM (espera pelo arranque = PowerShell Direct, sem sleep fixo)
Write-LogHost "[4/7] A arrancar a VM..."
$psDirectOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PsDirectTimeoutSeconds -LogPath $HostLogPath
if ($psDirectOk -is [pscredential]) {
    $cred = $psDirectOk
    Add-LogLine -Path $HostLogPath -Value "PowerShell Direct ready with credential: $($cred.UserName)"
} else {
    Add-LogLine -Path $HostLogPath -Value "PowerShell Direct timeout/not ready"
    Write-Warning "      PowerShell Direct não ficou pronto após timeout. A continuar com cautela..."
}

# Transferência host→guest via PowerShell Direct (Guest Services desactivados por política).
Write-LogHost "[5/7] Transferência host→guest via PowerShell Direct..."
