# --- Módulo: PhaseC-Boot.ps1 ---
# --- Arranque da VM para instalação de runtimes ---
# --- Arranque da VM e validação PowerShell Direct ---
# Credenciais para comunicação directa com a VM.
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

Write-LogHost ""
Write-LogHost "A arrancar VM e a validar PowerShell Direct..."
$ps = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds 600
if ($ps -is [pscredential]) { $cred = $ps }
if (-not $ps) {
    Write-LogHost ""
    Write-LogHost "=========================================================="
    Write-LogHost "[ERRO] PowerShell Direct não ficou disponível nesta fase."
    Write-LogHost "Isto normalmente significa OOBE/início de sessão ainda não concluído,"
    Write-LogHost "ou credenciais inválidas em `_Config.ps1` (GuestUser/GuestPassword)."
    Write-LogHost "Sugestão: corra primeiro `05-FirstTimeVmSetup.ps1` e confirme que a VM entra no Windows."
    Write-LogHost "=========================================================="
    Write-LogHost ""
    exit 3
}
