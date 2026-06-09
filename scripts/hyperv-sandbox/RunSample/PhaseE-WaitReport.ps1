# 7) Aguardar o relatório via pipe
Write-LogHost "      A aguardar relatório via pipe (timeout: ${pipeTimeoutSeconds}s)..."
Add-LogLine -Path $HostLogPath -Value "Pipe wait begin: jobId=$($pipeJob.Id) earlyDone=$pipeReportAlreadyReceived analysisSuccess=$analysisSuccess"

# O pipe tem o seu próprio timeout ($pipeTimeoutSeconds); não cortar com $GlobalTimeoutSeconds.
$waitSec = $pipeTimeoutSeconds

if ($waitSec -gt 0) {
    $waitDeadline = (Get-Date).AddSeconds($waitSec)
    $lastJobLog = Get-Date
    $guestDonePath = "$VMScriptsPath\guest_analysis_done.txt"
    $guestReportPath = "C:\analysis.txt"
    while (-not $pipeReportAlreadyReceived -and (Get-Date) -lt $waitDeadline) {
        $st = $null
        try { $st = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State } catch { }
        if ($st -eq "Completed" -or $st -eq "Failed" -or $st -eq "Stopped") { break }

        # Puxar logs intermédios do job (drena só output novo desde a última chamada).
        try {
            $tmp = Receive-Job $pipeJob -ErrorAction SilentlyContinue 2>&1
            foreach ($item in @($tmp)) {
                $s = ($item | Out-String).TrimEnd()
                if ([string]::IsNullOrWhiteSpace($s) -or $s -eq "True") { continue }
                Write-LogHost ("      [PIPE] {0}" -f $s)
                Add-LogLine -Path $HostLogPath -Value ("[PIPE] " + $s)
            }
        } catch { }

        # Guest concluiu mas COM1/pipe não entregou -- saída antecipada com Copy-VMFile
        if ($st -ne "Completed") {
            try {
                $guestDone = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                    param($Path)
                    Test-Path -LiteralPath $Path
                } -ArgumentList $guestDonePath -ErrorAction SilentlyContinue
                if ($guestDone -eq $true) {
                    Write-LogWarning "      Guest análise concluída ($guestDonePath) mas pipe ainda não recebeu relatório. A tentar Copy-VMFile..."
                    Add-LogLine -Path $HostLogPath -Value "Guest done detected; pipe not complete -- fallback Copy-VMFile"
                    try {
                        Copy-SandboxVMFileFromGuest -VMName $VMName -Credential $cred `
                            -GuestSourcePath $guestReportPath -HostDestinationPath $ReportOutputPath
                        if (Test-Path -LiteralPath $ReportOutputPath) {
                            Write-LogHost "      Relatório obtido via Copy-VMFile (fallback): $ReportOutputPath"
                            Add-LogLine -Path $HostLogPath -Value "Report pulled via Copy-VMFile fallback"
                            $pipeReportAlreadyReceived = $true
                            break
                        }
                    } catch {
                        Write-LogWarning "      Fallback Copy-VMFile falhou: $($_.Exception.Message)"
                        Add-LogLine -Path $HostLogPath -Value "Copy-VMFile fallback failed: $($_.Exception.Message)"
                    }
                }
            } catch { }
        }

        # Heartbeat no host a cada ~10s
        if (((Get-Date) - $lastJobLog).TotalSeconds -ge 10) {
            $remain = [int]($waitDeadline - (Get-Date)).TotalSeconds
            $pj = Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue
            $hm = if ($pj) { [string]$pj.HasMoreData } else { "?" }
            $loc = if ($pj) { [string]$pj.Location } else { "" }
            Write-LogHost "      [PIPE-HOST] job id=$($pipeJob.Id) state=$st hasMoreData=$hm loc='$loc' resto~${remain}s"
            Add-LogLine -Path $HostLogPath -Value "PIPE-HOST heartbeat state=$st hasMore=$hm rest=${remain}s"
            $lastJobLog = Get-Date
        }

        Start-Sleep -Seconds 2
    }

    $jobCompleted = $false
    try {
        $st2 = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State
        $jobCompleted = ($st2 -eq "Completed")
    } catch { }

    if (-not $jobCompleted) {
        if (-not $pipeReportAlreadyReceived) {
            Write-LogWarning "      Listener do pipe não terminou a tempo (timeout após ${waitSec}s)."
            Add-LogLine -Path $HostLogPath -Value "Pipe listener timeout after ${waitSec}s"
        }
        Stop-Job $pipeJob -ErrorAction SilentlyContinue
    }
} else {
    Write-LogWarning "      Sem tempo restante para aguardar relatório."
    Add-LogLine -Path $HostLogPath -Value "No time remaining for report"
}
