# --- Módulo: PhaseA-PreCheck.ps1 ---
# --- Pré-verificações: VM existente e credenciais ---

# --- Início da fase A ---
Write-LogHost "=== Primeira entrada: validar guest -> garantir isolamento -> snapshot ==="
Write-LogHost ""

# --- Pré-verificações ---
# Confirma que a VM existe no Hyper-V
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-LogHost ('[ERRO] VM ''{0}'' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1.' -f $VMName)
    exit 1
}

# Prepara credenciais candidatas para PowerShell Direct
$secure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1
