# --- Script: PhaseF-CollectResult.ps1 ---
# --- Recolha e validação do relatório no host ---

if (Test-Path -LiteralPath $ReportOutputPath) {
    Write-LogHost "      Relatório no host: $ReportOutputPath"
    Add-LogLine -Path $HostLogPath -Value "Report on host: $ReportOutputPath"

    # --- Verificação SHA256 do relatório copiado ---
    if ($reportHashVerified -and $reportSha256) {
        Add-LogLine -Path $HostLogPath -Value "Report hash verified: $reportSha256"
    } elseif (-not $reportHashVerified -and $cred -is [pscredential]) {
        try {
            $digest = Get-SandboxGuestReportDigest -VMName $VMName -Credential $cred `
                -GuestReportPath "C:\analysis.txt" -GuestDonePath "$VMScriptsPath\guest_analysis_done.txt"
            if (-not [string]::IsNullOrWhiteSpace($digest.sha256)) {
                $reportSha256 = Assert-SandboxCopiedReportHash -HostReportPath $ReportOutputPath `
                    -ExpectedSha256 $digest.sha256 -ExpectedBytes $digest.reportBytes
                $reportHashVerified = $true
                Write-LogHost "      SHA256 do relatório verificado: $reportSha256"
                Add-LogLine -Path $HostLogPath -Value "Report hash verified (post-collect): $reportSha256"
            }
        } catch {
            Write-LogWarning "      Verificação SHA256 falhou: $($_.Exception.Message)"
            Add-LogLine -Path $HostLogPath -Value "Report hash verification failed: $($_.Exception.Message)"
            # *remove relatório inválido para não confundir o utilizador*
            try { Remove-Item -LiteralPath $ReportOutputPath -Force -ErrorAction SilentlyContinue } catch { }
        }
    }

    # --- Verificação de completude do relatório ---
    if (Test-Path -LiteralPath $ReportOutputPath) {
        if (-not (Test-ReportLooksComplete -Path $ReportOutputPath)) {
            Write-LogWarning "      Relatório parece incompleto (verificar manualmente: $ReportOutputPath)."
            Add-LogLine -Path $HostLogPath -Value "Report appears incomplete"
        }
    }
} else {
    # --- Recuperação de emergência: copiar directamente do guest ---
    Write-LogWarning "      Relatório não foi obtido do guest."
    Add-LogLine -Path $HostLogPath -Value "Report not obtained from guest"

    if ($cred -is [pscredential]) {
        Write-LogHost "      A tentar recuperar relatório diretamente do guest (C:\analysis.txt)..."
        try {
            Copy-SandboxVMFileFromGuest -VMName $VMName -Credential $cred `
                -GuestSourcePath "C:\analysis.txt" -HostDestinationPath $ReportOutputPath -Retries 3 -DelaySeconds 3
            if (Test-Path -LiteralPath $ReportOutputPath) {
                $digest = Get-SandboxGuestReportDigest -VMName $VMName -Credential $cred `
                    -GuestReportPath "C:\analysis.txt" -GuestDonePath "$VMScriptsPath\guest_analysis_done.txt"
                if (-not [string]::IsNullOrWhiteSpace($digest.sha256)) {
                    $reportSha256 = Assert-SandboxCopiedReportHash -HostReportPath $ReportOutputPath `
                        -ExpectedSha256 $digest.sha256 -ExpectedBytes $digest.reportBytes
                    $reportHashVerified = $true
                    Add-LogLine -Path $HostLogPath -Value "Report recovered and hash verified: $reportSha256"
                    Write-LogHost "      Relatório recuperado e SHA256 verificado: $ReportOutputPath"
                } else {
                    Add-LogLine -Path $HostLogPath -Value "Report recovered via final guest copy (no guest hash to verify)"
                    Write-LogHost "      Relatório recuperado (sem hash guest para validar): $ReportOutputPath"
                }
            }
        } catch {
            Write-LogWarning "      Recuperação final falhou: $($_.Exception.Message)"
            Add-LogLine -Path $HostLogPath -Value "Final guest copy failed: $($_.Exception.Message)"
            try { Remove-Item -LiteralPath $ReportOutputPath -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}
