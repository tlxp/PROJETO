# 7) Aguardar relatório: pipe COM1 (primário) + cópia PsDirect (fallback imediato quando o guest termina).
Write-LogHost "      A aguardar relatório via pipe (timeout: ${pipeTimeoutSeconds}s; fallback PsDirect activo)..."
Add-LogLine -Path $HostLogPath -Value "Pipe wait begin: jobId=$($pipeJob.Id) earlyDone=$pipeReportAlreadyReceived analysisSuccess=$analysisSuccess"

$waitSec = $pipeTimeoutSeconds
$guestDonePath = "$VMScriptsPath\guest_analysis_done.txt"
$guestReportPath = "C:\analysis.txt"
$guestPidSeenRunning = $false
$guestPidDeadSince = $null
$lastGuestDiagUtc = [DateTime]::MinValue
$lastReportBytes = -1
$reportUnchangedSince = $null
$guestDiagIntervalSeconds = 5
$guestPidDeadGraceSeconds = 8
$guestStallAbortSeconds = 60
$guestPullPollSeconds = 3
$lastGuestPullUtc = [DateTime]::MinValue
$launchNoLifeDeadline = (Get-Date).AddSeconds(45)
$guestState = $null
$pipeWaitAbortedEarly = $false
$pipeWaitAbortReason = ""

function Receive-PipeJobOutput {
    try {
        $tmp = Receive-Job $pipeJob -ErrorAction SilentlyContinue 2>&1
        foreach ($item in @($tmp)) {
            $s = ($item | Out-String).TrimEnd()
            if ([string]::IsNullOrWhiteSpace($s) -or $s -eq "True") { continue }
            Write-LogHost ("      [PIPE] {0}" -f $s)
            Add-LogLine -Path $HostLogPath -Value ("[PIPE] " + $s)
        }
    } catch { }
}

function Try-PullGuestReport {
    param(
        [bool] $AllowPartial,
        [string] $Reason
    )
    if (-not ($cred -is [pscredential])) { return $false }
    try {
        $pull = Try-ReceiveSandboxGuestReport -VMName $VMName -Credential $cred `
            -HostDestinationPath $ReportOutputPath `
            -GuestReportPath $guestReportPath `
            -GuestDonePath $guestDonePath `
            -HostDiagnosticsDir $RunDir `
            -GuestWorkDir $VMScriptsPath `
            -AllowPartial:$AllowPartial

        if ($pull.pulled) {
            $partialNote = if ($pull.partial) { " (parcial)" } else { "" }
            Write-LogHost "      Relatório obtido via cópia guest->host ($Reason)${partialNote}: $ReportOutputPath"
            Add-LogLine -Path $HostLogPath -Value "Report pulled via guest copy ($Reason)$partialNote"
            if ($pull.diagnosticsCopied -and $pull.diagnosticsCopied.Count -gt 0) {
                $diagMsg = "Guest diagnostics copied: $($pull.diagnosticsCopied -join ', ')"
                Write-LogHost "      $diagMsg"
                Add-LogLine -Path $HostLogPath -Value $diagMsg
            }
            return $true
        }
    } catch {
        Write-LogWarning "      Fallback cópia guest->host falhou: $($_.Exception.Message)"
        Add-LogLine -Path $HostLogPath -Value "Guest copy fallback failed: $($_.Exception.Message)"
    }
    return $false
}

if ($waitSec -gt 0) {
    $waitDeadline = (Get-Date).AddSeconds($waitSec)
    $lastJobLog = Get-Date
    while (-not $pipeReportAlreadyReceived -and (Get-Date) -lt $waitDeadline) {
        $st = $null
        try { $st = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State } catch { }
        if ($st -eq "Completed") {
            $pipeReportAlreadyReceived = $true
            break
        }
        if ($st -eq "Failed" -or $st -eq "Stopped") { break }

        Receive-PipeJobOutput

        $nowUtc = [DateTime]::UtcNow
        if ($cred -is [pscredential] -and ($nowUtc - $lastGuestDiagUtc).TotalSeconds -ge $guestDiagIntervalSeconds) {
            $lastGuestDiagUtc = $nowUtc
            try {
                $guestState = Get-SandboxGuestAnalysisDiag -VMName $VMName -Credential $cred `
                    -WorkDir $VMScriptsPath -ReportPath $guestReportPath -PidToCheck ([int]$detachedAnalysisPid)

                if ($guestState.pidRunning) { $guestPidSeenRunning = $true }

                if (-not $guestState.pidRunning -and $detachedAnalysisPid -gt 0) {
                    $guestStarted = $guestPidSeenRunning -or $guestState.aliveFile -or ($guestState.reportBytes -gt 0)
                    if ($guestStarted -and -not $guestPidDeadSince) { $guestPidDeadSince = Get-Date }
                } elseif ($guestState.pidRunning) {
                    $guestPidDeadSince = $null
                    $reportUnchangedSince = $null
                }

                if ($guestState.reportBytes -eq $lastReportBytes) {
                    if ($guestState.reportBytes -gt 0 -and -not $reportUnchangedSince) {
                        $reportUnchangedSince = Get-Date
                    }
                } else {
                    $lastReportBytes = $guestState.reportBytes
                    $reportUnchangedSince = $null
                    $guestPidDeadSince = $null
                }

                $msg = "Guest diag: pidRunning=$($guestState.pidRunning) reportBytes=$($guestState.reportBytes) doneFile=$($guestState.doneFile) aliveFile=$($guestState.aliveFile) reportComplete=$($guestState.reportComplete)"
                if ($guestState.launchError) { $msg += " launchError=$($guestState.launchError)" }
                if ($guestState.com1LogTail) { $msg += " com1=$($guestState.com1LogTail)" }
                if ($guestState.crashLogTail) { $msg += " crash=$($guestState.crashLogTail)" }
                Add-LogLine -Path $HostLogPath -Value $msg
                Write-LogHost "      [GUEST] $msg"
            } catch {
                Add-LogLine -Path $HostLogPath -Value "Guest diag failed: $($_.Exception.Message)"
            }
        }

        # Abortar cedo: launch aparentou OK mas o processo nunca arrancou de facto.
        if ($analysisSuccess -and $detachedAnalysisPid -gt 0 -and (Get-Date) -gt $launchNoLifeDeadline) {
            $noLife = $guestState -and (-not $guestPidSeenRunning) -and ($guestState.reportBytes -le 0) -and (-not $guestState.doneFile)
            if ($noLife) {
                $errDetail = if ($guestState.launchError) { $guestState.launchError } else { "sem guest_alive.txt nem relatório" }
                Write-LogWarning "      Análise destacada não arrancou no guest ($errDetail). A abortar espera do pipe."
                Add-LogLine -Path $HostLogPath -Value "Early abort: detached analysis never started ($errDetail)"
                $pipeWaitAbortedEarly = $true
                $pipeWaitAbortReason = "detached analysis never started"
                break
            }
        }

        if (-not $analysisSuccess) {
            Write-LogWarning "      Lançamento da análise falhou no host. A abortar espera do pipe."
            Add-LogLine -Path $HostLogPath -Value "Early abort: host launch failed"
            $pipeWaitAbortedEarly = $true
            $pipeWaitAbortReason = "host launch failed"
            break
        }

        $guestInactiveLongEnough = ($guestPidDeadSince -and ((Get-Date) - $guestPidDeadSince).TotalSeconds -ge $guestPidDeadGraceSeconds)
        $reportFrozenLongEnough = ($reportUnchangedSince -and ((Get-Date) - $reportUnchangedSince).TotalSeconds -ge $guestStallAbortSeconds)
        $guestDeadLongEnough = ($guestPidDeadSince -and ((Get-Date) - $guestPidDeadSince).TotalSeconds -ge $guestStallAbortSeconds)
        $guestStartedWork = $guestPidSeenRunning -or ($guestState -and $guestState.aliveFile) -or ($guestState -and $guestState.reportBytes -gt 0)
        $guestAnalysisStalled = $guestState -and $guestStartedWork -and (-not $guestState.pidRunning) `
            -and (-not $guestState.doneFile) -and (-not $guestState.reportComplete) `
            -and ($guestDeadLongEnough -or $reportFrozenLongEnough)

        if ($guestAnalysisStalled) {
            $stallDetail = "pid morto/inactivo há $([int]((Get-Date) - $guestPidDeadSince).TotalSeconds)s, relatório=$($guestState.reportBytes) bytes, sem REPORT_END;"
            if ($guestState.reportBytes -gt 200) {
                if (Try-PullGuestReport -AllowPartial:$true -Reason "análise parada no guest ($stallDetail)") {
                    $pipeReportAlreadyReceived = $true
                    Stop-SandboxPipeReportJob -PipeJob $pipeJob
                    break
                }
            }
            Write-LogWarning "      Análise no guest parou sem concluir ($stallDetail). A abortar espera do pipe."
            Add-LogLine -Path $HostLogPath -Value "Early abort: guest analysis stalled ($stallDetail)"
            $pipeWaitAbortedEarly = $true
            $pipeWaitAbortReason = "guest analysis stalled without completion"
            break
        }

        $guestLikelyCrashed = $guestInactiveLongEnough -and (
            $guestState.doneFile -or
            (-not [string]::IsNullOrWhiteSpace($guestState.crashLogTail))
        )
        $allowPartial = $guestLikelyCrashed -and (-not $guestState.reportComplete)
        $shouldPullGuest = ($cred -is [pscredential]) -and (
            ($nowUtc - $lastGuestPullUtc).TotalSeconds -ge $guestPullPollSeconds
        )

        if ($shouldPullGuest -and $guestState) {
            $lastGuestPullUtc = $nowUtc
            $pullReason = $null

            if ($guestState.doneFile) {
                $pullReason = "guest_analysis_done.txt"
            } elseif ($guestState.reportComplete) {
                $pullReason = "REPORT_END; em C:\analysis.txt"
            } elseif ($allowPartial -and $guestState.reportBytes -gt 200) {
                $pullReason = "relatório parcial ($($guestState.reportBytes) bytes, guest terminou/crash)"
            }

            if ($pullReason -and (Try-PullGuestReport -AllowPartial:($allowPartial) -Reason $pullReason)) {
                $pipeReportAlreadyReceived = $true
                Stop-SandboxPipeReportJob -PipeJob $pipeJob
                break
            }
        }

        if (((Get-Date) - $lastJobLog).TotalSeconds -ge 10) {
            $remain = [int]($waitDeadline - (Get-Date)).TotalSeconds
            $pj = Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue
            $hm = if ($pj) { [string]$pj.HasMoreData } else { "?" }
            Write-LogHost "      [PIPE-HOST] job id=$($pipeJob.Id) state=$st hasMoreData=$hm resto~${remain}s"
            Add-LogLine -Path $HostLogPath -Value "PIPE-HOST heartbeat state=$st hasMore=$hm rest=${remain}s"
            $lastJobLog = Get-Date
        }

        Start-Sleep -Seconds 2
    }

    $jobCompleted = $false
    try {
        $st2 = (Get-Job -Id $pipeJob.Id -ErrorAction SilentlyContinue).State
        $jobCompleted = ($st2 -eq "Completed")
        if ($jobCompleted) { $pipeReportAlreadyReceived = $true }
    } catch { }

    if (-not $jobCompleted -and -not $pipeReportAlreadyReceived) {
        if ($cred -is [pscredential] -and (Try-PullGuestReport -AllowPartial:$true -Reason "última tentativa antes de timeout")) {
            $pipeReportAlreadyReceived = $true
        }
    }

    if (-not $jobCompleted -and -not $pipeReportAlreadyReceived) {
        if ($pipeWaitAbortedEarly) {
            Write-LogWarning "      Espera do pipe abortada ($pipeWaitAbortReason)."
            Add-LogLine -Path $HostLogPath -Value "Pipe wait aborted early: $pipeWaitAbortReason"
        } else {
            Write-LogWarning "      Listener do pipe não terminou a tempo (timeout após ${waitSec}s)."
            Add-LogLine -Path $HostLogPath -Value "Pipe listener timeout after ${waitSec}s"
        }
        Stop-SandboxPipeReportJob -PipeJob $pipeJob
    } elseif ($pipeReportAlreadyReceived -and -not $jobCompleted) {
        Stop-SandboxPipeReportJob -PipeJob $pipeJob
    }
} else {
    Write-LogWarning "      Sem tempo restante para aguardar relatório."
    Add-LogLine -Path $HostLogPath -Value "No time remaining for report"
}
