# 6) Receptor do pipe + lançamento da análise na VM
# O job do pipe arranca aqui (VM já a correr) para evitar sessão COM1 ociosa desde o boot.
# Tem de estar ligado antes do guest escrever no COM1 no fim da análise.
Write-LogHost "[6/7] A iniciar receptor do pipe e lançar análise na VM..."
if (-not $pipeJob) {
    $pipeJob = Start-Job -ScriptBlock {
        param($PipeName, $OutputPath, $TimeoutSecondsLocal, $ModulePath, $IdleReconnectSec)
        Write-Host "[PIPE] Job worker arrancou pid=$PID utc=$([DateTime]::UtcNow.ToString('o'))"
        Import-Module $ModulePath -DisableNameChecking -ErrorAction Stop
        return (Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath `
            -TimeoutSeconds $TimeoutSecondsLocal -IdleReconnectSeconds $IdleReconnectSec)
    } -ArgumentList $RunPipeName, $ReportOutputPath, $pipeTimeoutSeconds, $modulePath, $pipeIdleReconnectSeconds
    Add-LogLine -Path $HostLogPath -Value "Pipe job started: Id=$($pipeJob.Id) path=\\.\pipe\$RunPipeName timeout=${pipeTimeoutSeconds}s"
    Write-LogHost "      [PIPE-HOST] Job receptor id=$($pipeJob.Id) pipe=\\.\pipe\$RunPipeName"
    Start-Sleep -Seconds 3
}

$analysisSuccess = $false

try {
    $launchOut = Start-DetachedAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath `
        -TimeoutSec $TimeoutSeconds -WaitForSampleExit:$WaitForSampleExit -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256 -HostRunId $RunId
    $analysisSuccess = $true
    Add-LogLine -Path $HostLogPath -Value "Detached analysis launched successfully"
    foreach ($item in @($launchOut)) {
        if ($null -eq $item) { continue }
        $raw = ($item | Out-String).Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        try {
            $launchJson = $raw | ConvertFrom-Json -ErrorAction Stop
            if ($launchJson.detached_pid) { $detachedAnalysisPid = [int]$launchJson.detached_pid }
        } catch { }
    }
    if ($detachedAnalysisPid -gt 0) {
        Add-LogLine -Path $HostLogPath -Value "Detached analysis pid=$detachedAnalysisPid"
    }
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
                -TimeoutSec $TimeoutSeconds -WaitForSampleExit:$WaitForSampleExit -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256 -HostRunId $RunId | Out-Null
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

# Confirmar que o processo destacado arrancou de facto no guest (evita espera infinita no pipe).
if ($analysisSuccess -and $cred -is [pscredential]) {
    Start-Sleep -Seconds 3
    try {
        $bootDiag = Get-SandboxGuestAnalysisDiag -VMName $VMName -Credential $cred `
            -WorkDir $VMScriptsPath -ReportPath "C:\analysis.txt" -PidToCheck ([int]$detachedAnalysisPid)
        $bootMsg = "Launch verify: pidRunning=$($bootDiag.pidRunning) aliveFile=$($bootDiag.aliveFile) launchOk=$($bootDiag.launchOk)"
        if ($bootDiag.launchError) { $bootMsg += " err=$($bootDiag.launchError)" }
        Add-LogLine -Path $HostLogPath -Value $bootMsg
        Write-LogHost "      [GUEST] $bootMsg"
        if ($detachedAnalysisPid -gt 0 -and -not $bootDiag.pidRunning -and -not $bootDiag.aliveFile) {
            $analysisSuccess = $false
            Write-LogWarning "      Análise destacada não sobreviveu ao arranque no guest."
            if ($bootDiag.crashLogTail) {
                Add-LogLine -Path $HostLogPath -Value "Guest crash log: $($bootDiag.crashLogTail)"
                Write-LogHost "      [GUEST] crash=$($bootDiag.crashLogTail)"
            }
        }
    } catch {
        Add-LogLine -Path $HostLogPath -Value "Launch verify failed: $($_.Exception.Message)"
    }
}
