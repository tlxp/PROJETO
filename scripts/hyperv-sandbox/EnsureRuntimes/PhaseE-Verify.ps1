# --- Módulo: PhaseE-Verify.ps1 ---
# --- Verificação pós-instalação de runtimes na VM ---
# --- Verificação pós-instalação ---
Write-LogHost ""
Write-LogHost "Sanity check: dotnet --info (se existir)..."
try {
    # Consulta dotnet --info na VM via PowerShell Direct (best-effort)
    $dotnetInfo = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        $p = Get-Command dotnet -ErrorAction SilentlyContinue
        if (-not $p) { return "dotnet: não encontrado" }
        try { return (& dotnet --info 2>&1 | Select-Object -First 14) -join "`n" } catch { return "dotnet: erro ao executar --info" }
    } -ErrorAction SilentlyContinue
    if ($dotnetInfo) {
        ($dotnetInfo -split "`r?`n") | ForEach-Object { Write-LogHost ("  " + $_) }
    }
} catch { }

# --- Conclusão ---
Write-LogHost ""
# Indica scripts alternativos para persistir Sysmon/runtimes no snapshot
Write-LogHost "Concluído. (Para persistir Sysmon + runtimes no snapshot limpo, execute 05-FirstTimeVmSetup.ps1 ou 03-Install-SysmonInGuest.ps1.)"
