Write-LogHost ""
Write-LogHost "Sanity check: dotnet --info (se existir)..."
try {
    $dotnetInfo = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        $p = Get-Command dotnet -ErrorAction SilentlyContinue
        if (-not $p) { return "dotnet: não encontrado" }
        try { return (& dotnet --info 2>&1 | Select-Object -First 14) -join "`n" } catch { return "dotnet: erro ao executar --info" }
    } -ErrorAction SilentlyContinue
    if ($dotnetInfo) {
        ($dotnetInfo -split "`r?`n") | ForEach-Object { Write-LogHost ("  " + $_) }
    }
} catch { }

Write-LogHost ""
Write-LogHost "Concluído. (Se quiseres persistir isto no snapshot limpo, corre agora o 05-FirstTimeVmSetup.ps1 para criar novo CleanState.)"
