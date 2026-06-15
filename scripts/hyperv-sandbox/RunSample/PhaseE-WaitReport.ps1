# 7) Aguardar relatório via cópia guest->host (PsDirect / Copy-VMFile)
Write-LogHost "      A aguardar relatório (cópia guest->host, timeout: ${reportTimeoutSeconds}s)..."
Add-LogLine -Path $HostLogPath -Value "Report wait begin: analysisSuccess=$analysisSuccess"

$waitSec = $reportTimeoutSeconds
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
$waitAbortedEarly = $false
$waitAbortReason = ""

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
            $hashNote = if ($pull.hashVerified) { " SHA256 OK" } else { "" }
            Write-LogHost "      Relatório obtido via cópia guest->host ($Reason)${partialNote}${hashNote}: $ReportOutputPath"
            Add-LogLine -Path $HostLogPath -Value "Report pulled via guest copy ($Reason)$partialNote$hashNote"
            if ($pull.reportSha256) {
                $reportSha256 = $pull.reportSha256
                Add-LogLine -Path $HostLogPath -Value "Report SHA256: $reportSha256"
            }
            if ($pull.hashVerified) { $reportHashVerified = $true }
            if ($pull.diagnosticsCopied -and $pull.diagnosticsCopied.Count -gt 0) {
                $diagMsg = "Guest diagnostics copied: $($pull.diagnosticsCopied -join ', ')"
                Write-LogHost "      $diagMsg"
                Add-LogLine -Path $HostLogPath -Value $diagMsg
            }
            return $true
        }
    } catch {
        Write-LogWarning "      Cópia guest->host falhou: $($_.Exception.Message)"
        Add-LogLine -Path $HostLogPath -Value "Guest copy failed: $($_.Exception.Message)"
    }
    return $false
}

if ($waitSec -gt 0) {
    $waitDeadline = (Get-Date).AddSeconds($waitSec)
    $lastStatusLog = Get-Date
    while (-not $reportReceived -and (Get-Date) -lt $waitDeadline) {
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
                if ($guestState.crashLogTail) { $msg += " crash=$($guestState.crashLogTail)" }
                Add-LogLine -Path $HostLogPath -Value $msg
                Write-LogHost "      [GUEST] $msg"
            } catch {
                Add-LogLine -Path $HostLogPath -Value "Guest diag failed: $($_.Exception.Message)"
            }
        }

        if ($analysisSuccess -and $detachedAnalysisPid -gt 0 -and (Get-Date) -gt $launchNoLifeDeadline) {
            $noLife = $guestState -and (-not $guestPidSeenRunning) -and ($guestState.reportBytes -le 0) -and (-not $guestState.doneFile)
            if ($noLife) {
                $errDetail = if ($guestState.launchError) { $guestState.launchError } else { "sem guest_alive.txt nem relatório" }
                Write-LogWarning "      Análise destacada não arrancou no guest ($errDetail). A abortar espera."
                Add-LogLine -Path $HostLogPath -Value "Early abort: detached analysis never started ($errDetail)"
                $waitAbortedEarly = $true
                $waitAbortReason = "detached analysis never started"
                break
            }
        }

        if (-not $analysisSuccess) {
            Write-LogWarning "      Lançamento da análise falhou no host. A abortar espera."
            Add-LogLine -Path $HostLogPath -Value "Early abort: host launch failed"
            $waitAbortedEarly = $true
            $waitAbortReason = "host launch failed"
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
                    $reportReceived = $true
                    break
                }
            }
            Write-LogWarning "      Análise no guest parou sem concluir ($stallDetail). A abortar espera."
            Add-LogLine -Path $HostLogPath -Value "Early abort: guest analysis stalled ($stallDetail)"
            $waitAbortedEarly = $true
            $waitAbortReason = "guest analysis stalled without completion"
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
                $reportReceived = $true
                break
            }
        }

        if (((Get-Date) - $lastStatusLog).TotalSeconds -ge 15) {
            $remain = [int]($waitDeadline - (Get-Date)).TotalSeconds
            Write-LogHost "      [WAIT] resto~${remain}s doneFile=$($guestState.doneFile) reportBytes=$($guestState.reportBytes)"
            Add-LogLine -Path $HostLogPath -Value "Report wait heartbeat rest=${remain}s done=$($guestState.doneFile) bytes=$($guestState.reportBytes)"
            $lastStatusLog = Get-Date
        }

        Start-Sleep -Seconds 2
    }

    if (-not $reportReceived -and (Try-PullGuestReport -AllowPartial:$true -Reason "última tentativa antes de timeout")) {
        $reportReceived = $true
    }

    if (-not $reportReceived) {
        if ($waitAbortedEarly) {
            Write-LogWarning "      Espera abortada ($waitAbortReason)."
            Add-LogLine -Path $HostLogPath -Value "Report wait aborted early: $waitAbortReason"
        } else {
            Write-LogWarning "      Relatório não obtido a tempo (timeout após ${waitSec}s)."
            Add-LogLine -Path $HostLogPath -Value "Report wait timeout after ${waitSec}s"
        }
    }
} else {
    Write-LogWarning "      Sem tempo restante para aguardar relatório."
    Add-LogLine -Path $HostLogPath -Value "No time remaining for report"
}
