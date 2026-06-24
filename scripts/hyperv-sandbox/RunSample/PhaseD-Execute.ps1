# --- Script: PhaseD-Execute.ps1 ---
# --- Lançamento da análise destacada na VM ---

Write-LogHost "[6/7] A lançar análise na VM..."

$analysisSuccess = $false

# --- Primeira tentativa de lançamento ---
try {
    $launchOut = Start-DetachedAnalysisInVm -VM $VMName -Cred $cred -VmSamplePath $VMSamplePath `
        -TimeoutSec $TimeoutSeconds -WaitForSampleExit:$WaitForSampleExit -VmScriptDir $VMScriptsPath -SampleSha256 $sampleSha256 -HostRunId $RunId
    $analysisSuccess = $true
    Add-LogLine -Path $HostLogPath -Value "Detached analysis launched successfully"
    # *extrai o PID do processo destacado a partir do JSON devolvido*
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

    # --- Segunda tentativa se a VM ainda estiver em execução ---
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

# --- Verificação de que o processo destacado arrancou no guest ---
if ($analysisSuccess -and $cred -is [pscredential]) {
    Start-Sleep -Seconds 3
    try {
        $bootDiag = Get-SandboxGuestAnalysisDiag -VMName $VMName -Credential $cred `
            -WorkDir $VMScriptsPath -ReportPath "C:\analysis.txt" -PidToCheck ([int]$detachedAnalysisPid)
        $bootMsg = "Launch verify: pidRunning=$($bootDiag.pidRunning) aliveFile=$($bootDiag.aliveFile) launchOk=$($bootDiag.launchOk)"
        if ($bootDiag.launchError) { $bootMsg += " err=$($bootDiag.launchError)" }
        Add-LogLine -Path $HostLogPath -Value $bootMsg
        Write-LogHost "      [GUEST] $bootMsg"
        # *marca falha se o PID morreu sem criar ficheiros de vida nem relatório*
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
