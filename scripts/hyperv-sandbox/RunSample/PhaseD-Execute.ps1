# 6) Executar análise na VM
Write-LogHost "[6/7] A executar análise na VM..."
$analysisSuccess = $false

try {
    Invoke-RunAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath -TimeoutSec $TimeoutSeconds -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256
    $analysisSuccess = $true
    Add-LogLine -Path $HostLogPath -Value "Analysis executed via Invoke-Command successfully"
} catch {
    $analysisSuccess = $false
    Write-LogWarning "Invoke-Command falhou (tentativa 1): $($_.Exception.Message)"
    Add-LogLine -Path $HostLogPath -Value "Invoke-Command failed (try1): $($_.Exception.Message)"

    # Repetir se a VM ainda estiver ativa
    $vmState = (Get-VM -Name $VMName -ErrorAction SilentlyContinue).State
    if ($vmState -eq 'Running') {
        Write-LogWarning "VM ainda em execução. A tentar re-invocar análise..."
        Start-Sleep -Seconds 5
        try {
            Invoke-RunAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath `
                -TimeoutSec $TimeoutSeconds -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256
            $analysisSuccess = $true
            Add-LogLine -Path $HostLogPath -Value "Analysis re-invoked successfully (try2)"
        } catch {
            Add-LogLine -Path $HostLogPath -Value "Invoke-Command failed (try2): $($_.Exception.Message)"
            Write-LogWarning "Segunda tentativa também falhou: $($_.Exception.Message)"
        }
    } else {
        Write-LogWarning "VM não está Running (estado: $vmState). Não é possível re-invocar."
    }
}

Start-Sleep -Seconds 1
$earlyState = $null
try { $earlyState = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State } catch { }
$pipeReportAlreadyReceived = ($earlyState -eq "Completed")
if ($pipeReportAlreadyReceived) {
    Write-LogHost "      [PIPE] Relatório já recebido durante execução da análise."
}
