# Recolher resultado do pipe
$pipeResult = $null
$pipeState = $null
try { 
    $pipeState = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State 
} catch { }

if ($pipeState -eq "Completed") {
    $pipeResult = Receive-Job $pipeJob -ErrorAction SilentlyContinue
    Remove-Job $pipeJob -Force -ErrorAction SilentlyContinue
    Add-LogLine -Path $HostLogPath -Value "Pipe lines received: $pipeResult"
    if (Test-Path $ReportOutputPath) {
        Write-LogHost "      Relatório recebido via pipe: $ReportOutputPath"
        Add-LogLine -Path $HostLogPath -Value "Report received successfully via pipe"

        if (-not (Test-ReportLooksComplete -Path $ReportOutputPath)) {
            Write-LogWarning "      Relatório via pipe parece incompleto (verificar manualmente: $ReportOutputPath)."
            Add-LogLine -Path $HostLogPath -Value "Pipe report appears incomplete"
        }
    } else {
        Write-LogWarning "      Pipe concluído mas ficheiro de relatório não encontrado."
        Add-LogLine -Path $HostLogPath -Value "Pipe completed but report file not found"
    }
} elseif (Test-Path -LiteralPath $ReportOutputPath) {
    Write-LogHost "      Relatório obtido via fallback (Copy-VMFile), pipe estado=$pipeState"
    Add-LogLine -Path $HostLogPath -Value "Report from Copy-VMFile fallback; pipe state=$pipeState"
} else {
    Write-LogWarning "      Listener do pipe não completou (estado=$pipeState). O relatório não foi obtido."
    Add-LogLine -Path $HostLogPath -Value "Pipe state=$pipeState; report not obtained"

    # Tentar obter output de erro do job para diagnóstico
    try {
        $jobErrors = Receive-Job $pipeJob -ErrorAction SilentlyContinue 2>&1
        if ($jobErrors) {
            Add-LogLine -Path $HostLogPath -Value "Pipe job output: $jobErrors"
            Write-LogWarning "      Detalhes do erro do pipe: $jobErrors"
        }
    } catch { }
    try { Stop-Job $pipeJob -ErrorAction SilentlyContinue } catch { }
    try { Remove-Job $pipeJob -Force -ErrorAction SilentlyContinue } catch { }
}
