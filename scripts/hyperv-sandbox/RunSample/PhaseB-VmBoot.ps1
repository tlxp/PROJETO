# 3) Restaurar snapshot limpo
Write-LogHost "[3/7] A restaurar snapshot '$SnapshotName'..."
Stop-SandboxVM -VMName $VMName
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      Snapshot restaurado."

# 3.5) IMPORTANTE: configurar o pipe no COM1 após o restore, antes de arrancar a VM
try {
    Set-VMComPort -VMName $VMName -Number 1 -Path "\\.\pipe\$RunPipeName" -ErrorAction Stop
    Add-LogLine -Path $HostLogPath -Value "COM1 pipe set to: \\.\pipe\$RunPipeName"
    Write-LogHost "[3.5/7] Pipe configurado: \\.\pipe\$RunPipeName"
} catch {
    Add-LogLine -Path $HostLogPath -Value "Failed to set VM COM1 pipe: $_"
    Write-Warning "      Falha ao configurar COM1 pipe: $_"
}

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

# 5) Ativar Guest Service para Copy-VMFile (e opcionalmente Invoke-Command)
Write-LogHost "[5/7] A ativar Guest Service para transferência..."
Enable-SandboxGuestService -VMName $VMName
$null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120
