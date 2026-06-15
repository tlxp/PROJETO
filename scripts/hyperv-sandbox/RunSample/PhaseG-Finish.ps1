# 8) Parar VM e restaurar snapshot
Write-LogHost "[8/8] A parar a VM e a restaurar snapshot..."
Stop-SandboxVM -VMName $VMName
Start-Sleep -Milliseconds 500
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      VM restaurada ao estado limpo."

Add-LogLine -Path $HostLogPath -Value "VM stopped and snapshot restored"

if ($script:PROJETOVM_UseGuestServices) {
    try {
        Disable-SandboxGuestService -VMName $VMName
        Add-LogLine -Path $HostLogPath -Value "Guest Service Interface disabled after run"
    } catch {
        Add-LogLine -Path $HostLogPath -Value "Failed to disable Guest Service Interface: $_"
    }
}

# JSON estruturado do run
$analysisEnd = Get-Date
$status = if (Test-ReportLooksComplete -Path $ReportOutputPath) { "ok" }
          elseif ((Test-Path -LiteralPath $ReportOutputPath) -and ((Get-Item -LiteralPath $ReportOutputPath).Length -gt 0)) { "partial" }
          else { "failed" }
$jsonData = @{
    run_id              = $RunId
    sample_path         = $SamplePath
    sample_sha256       = $sampleSha256
    vm_name             = $VMName
    snapshot            = $SnapshotName
    analysis_start      = $analysisStart.ToString("yyyy-MM-dd HH:mm:ss")
    analysis_end        = $analysisEnd.ToString("yyyy-MM-dd HH:mm:ss")
    report_path         = $ReportOutputPath
    report_sha256       = if ($reportSha256) { $reportSha256 } else { $null }
    report_hash_verified = $reportHashVerified
    status              = $status
}
try {
    $jsonData | ConvertTo-Json -Depth 4 | Set-Content -Path $HostJsonPath -Encoding UTF8
} catch { }

Write-LogHost ""
try { Set-Clipboard -Value $ReportOutputPath } catch { }
Write-LogHost "Concluído."
Write-LogHost "Relatório (copiado para clipboard): $ReportOutputPath"
$script:SandboxRunCleanupDone = $true
