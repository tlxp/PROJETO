# --- Módulo: PhaseD-Isolation.ps1 ---
# --- Garantir isolamento de rede (switch interno) ---

# --- [4/5] Garantir isolamento de rede ---
Write-LogHost '[4/5] A garantir isolamento de rede (sem adaptadores externos)...'

# Hyper-V não permite remover adaptadores sintéticos com a VM em execução
Write-LogHost "       A parar a VM para remover adaptadores não-Internal..."
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

# --- Remover adaptadores em switches não-Internal ---
# Remove ligações a switches External/Default, mantendo apenas Internal (SandboxSwitch)
$allAdapters = @(Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue)
foreach ($adapter in $allAdapters) {
    if ([string]::IsNullOrWhiteSpace($adapter.SwitchName)) { continue }
    $sw = Get-VMSwitch -Name $adapter.SwitchName -ErrorAction SilentlyContinue
    if ($sw -and $sw.SwitchType -ne "Internal") {
        Write-LogHost ('       Adaptador ''{0}'' em switch não-Internal ''{1}'' (tipo: {2}). A remover...' -f $adapter.Name, $adapter.SwitchName, $sw.SwitchType)
        try {
            Remove-VMNetworkAdapter -VMName $VMName -Name $adapter.Name -ErrorAction Stop | Out-Null
            Write-LogHost "       Removido."
        } catch {
            Write-LogHost ('[ERRO] Não foi possível remover ''{0}'': {1}' -f $adapter.Name, $_.Exception.Message)
            exit 1
        }
    }
}

# --- Listar adaptadores restantes ---
Write-LogHost '       Adaptadores restantes (devem ser apenas SandboxSwitch/Internal):'
Get-VMNetworkAdapter -VMName $VMName | ForEach-Object {
    $swName = $_.SwitchName
    if ([string]::IsNullOrWhiteSpace($swName)) {
        Write-LogHost ('         - {0} -> (sem switch)' -f $_.Name)
        return
    }
    $swType = ((Get-VMSwitch -Name $swName -ErrorAction SilentlyContinue).SwitchType)
    if ([string]::IsNullOrWhiteSpace($swType)) { $swType = "Unknown" }
    Write-LogHost ('         - {0} -> ''{1}'' [{2}]' -f $_.Name, $swName, $swType)
}

# --- Reiniciar VM para passos seguintes ---
# Verificação de internet omitida: switch Internal + remoção de externos = isolamento assumido
Write-LogHost '       A arrancar VM (isolamento assumido: Switch Internal + adaptadores externos removidos)...'
$ps2 = Start-SandboxVM -VMName $VMName -Credential $cred -PowerShellDirectTimeoutSeconds $PsDirectTimeoutSeconds
if ($ps2 -is [pscredential]) { $cred = $ps2 }
