# --- Script: PhaseB-VmBoot.ps1 ---
# --- Restauro do snapshot e arranque da VM ---

# *reverte a VM ao estado limpo antes de cada análise*
Write-LogHost "[3/7] A restaurar snapshot '$SnapshotName'..."
Stop-SandboxVM -VMName $VMName
Start-Sleep -Milliseconds 400
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      Snapshot restaurado."

# --- Arranque e espera por PowerShell Direct ---
# *sem sleep fixo; aguarda até a sessão remota estar pronta*
Write-LogHost "[4/7] A arrancar a VM..."
$psDirectOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds $PsDirectTimeoutSeconds -LogPath $HostLogPath
if ($psDirectOk -is [pscredential]) {
    $cred = $psDirectOk
    Add-LogLine -Path $HostLogPath -Value "PowerShell Direct ready with credential: $($cred.UserName)"
} else {
    Add-LogLine -Path $HostLogPath -Value "PowerShell Direct timeout/not ready"
    Write-Warning "      PowerShell Direct não ficou pronto após timeout. A continuar com cautela..."
}

# --- Preparação para transferência host→guest ---
# *Guest Services desactivados por política; cópia via PS Direct*
Write-LogHost "[5/7] Transferência host→guest via PowerShell Direct..."
