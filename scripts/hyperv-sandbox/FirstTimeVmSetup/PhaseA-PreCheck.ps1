Write-LogHost "=== Primeira entrada: validar guest -> garantir isolamento -> snapshot ==="
Write-LogHost ""

# Pré-verificações
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-LogHost ('[ERRO] VM ''{0}'' nao encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1.' -f $VMName)
    exit 1
}

$secure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1
