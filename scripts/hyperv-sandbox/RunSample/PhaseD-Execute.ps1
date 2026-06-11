# 6) Lançar análise destacada na VM
# A análise corre num processo separado dentro da VM e o relatório chega por COM1 -> Named Pipe.
# Assim o PowerShell Direct pode cair a meio sem matar a análise nem o envio do relatório.
Write-LogHost "[6/7] A lançar análise destacada na VM (relatório via COM1)..."
$analysisSuccess = $false

try {
    Start-DetachedAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath `
        -TimeoutSec $TimeoutSeconds -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256 -HostRunId $RunId | Out-Null
    $analysisSuccess = $true
    Add-LogLine -Path $HostLogPath -Value "Detached analysis launched successfully"
} catch {
    $analysisSuccess = $false
    Write-LogWarning "Lançamento da análise destacada falhou (tentativa 1): $($_.Exception.Message)"
    Add-LogLine -Path $HostLogPath -Value "Detached launch failed (try1): $($_.Exception.Message)"

    # Repetir se a VM ainda estiver ativa
    $vmState = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
    if ($vmState -eq 'Running') {
        Write-LogWarning "VM ainda em execução. A tentar re-lançar análise..."
        Start-Sleep -Seconds 5
        try {
            Start-DetachedAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath `
                -TimeoutSec $TimeoutSeconds -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256 -HostRunId $RunId | Out-Null
            $analysisSuccess = $true
            Add-LogLine -Path $HostLogPath -Value "Detached analysis re-launched successfully (try2)"
        } catch {
            Add-LogLine -Path $HostLogPath -Value "Detached launch failed (try2): $($_.Exception.Message)"
            Write-LogWarning "Segunda tentativa também falhou: $($_.Exception.Message)"
        }
    } else {
        Write-LogWarning "VM não está Running (estado: $vmState). Não é possível re-lançar."
    }
}

Start-Sleep -Seconds 1
$earlyState = $null
try { $earlyState = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State } catch { }
$pipeReportAlreadyReceived = ($earlyState -eq "Completed")
if ($pipeReportAlreadyReceived) {
    Write-LogHost "      [PIPE] Relatório já recebido durante execução da análise."
}
