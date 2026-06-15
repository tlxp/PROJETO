$SamplePath = Resolve-AutoSamplePath -ProvidedPath $SamplePath -SamplesDir $script:PROJETOVM_SamplesPath -AllowAutoSample:$AllowAutoSample

if (-not [System.IO.File]::Exists($SamplePath)) {
    Write-Error "Amostra não encontrada: $SamplePath"
    exit 1
}
if ([System.IO.Path]::GetExtension($SamplePath).ToLowerInvariant() -ne ".exe") {
    Write-Error "Esta pipeline (Run-MalwareAnalysis) executa amostras como .exe. Ficheiro fornecido: $SamplePath"
    exit 1
}
$vmObj = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vmObj) {
    Write-Error "VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1"
    exit 1
}
$snap = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
if (-not $snap) {
    Write-Error "Snapshot '$SnapshotName' não encontrado na VM '$VMName'. Crie-o após instalar o Windows na VM."
    exit 1
}

$sampleHash = Get-FileHash -LiteralPath $SamplePath -Algorithm SHA256
$sampleSha256 = $sampleHash.Hash

$sampleFileName = [System.IO.Path]::GetFileName($SamplePath)
$VMSamplePath = "C:\analysis_work\$sampleFileName"

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = Get-Date -Format "yyyyMMdd_HHmmss"
}
$ReportOutputPath = Join-Path $ReportsDir "analysis_$RunId.txt"

Ensure-DirectoryExists -Path $ReportsDir

# Logging básico do host
$LogsDir = $script:PROJETOVM_LogsPath
Ensure-DirectoryExists -Path $LogsDir
$RunsDir = Join-Path $LogsDir "Runs"
$RunDir = Join-Path $RunsDir $RunId
Ensure-DirectoryExists -Path $RunsDir
Ensure-DirectoryExists -Path $RunDir
$HostLogPath = Join-Path $RunDir "sandbox_run_$RunId.log"
$HostJsonPath = Join-Path $RunDir "run_$RunId.json"

# Preflight de isolamento de rede em cada run (não só no setup inicial)
$expectedSwitch = $script:PROJETOVM_SwitchName
if ([string]::IsNullOrWhiteSpace($expectedSwitch)) {
    Write-Error "PROJETOVM_SwitchName não definido em _Config.ps1."
    exit 1
}
Assert-SandboxVmNetworkIsolation -VMName $VMName -ExpectedSwitchName $expectedSwitch

# Amostras grandes via PS Direct consomem muito tempo de cópia; estender o deadline global.
if ($globalDeadline) {
    try {
        $sampleLen = (Get-Item -LiteralPath $SamplePath -ErrorAction Stop).Length
        $chunkSize = Get-SandboxPsDirectChunkSize
        $chunks = [math]::Ceiling($sampleLen / [double]$chunkSize)
        $copyExtraSeconds = [int][math]::Max(0, ($chunks * 4) + 180)
        $globalDeadline = $globalDeadline.AddSeconds($copyExtraSeconds)
        Add-LogLine -Path $HostLogPath -Value "Global deadline +${copyExtraSeconds}s for PS Direct copy ($sampleLen bytes, ~$chunks chunks of $chunkSize B)"
    } catch { }
}

Add-LogLine -Path $HostLogPath -Value "==== Sandbox Run $RunId ===="
Add-LogLine -Path $HostLogPath -Value "Sample: $SamplePath"
Add-LogLine -Path $HostLogPath -Value "Sample SHA256: $sampleSha256"
Add-LogLine -Path $HostLogPath -Value "VM: $VMName  Snapshot: $SnapshotName"
Add-LogLine -Path $HostLogPath -Value "Report: $ReportOutputPath"
Add-LogLine -Path $HostLogPath -Value "RunDir: $RunDir"
Add-LogLine -Path $HostLogPath -Value "Network preflight OK: VM adapters only on Internal switch '$expectedSwitch'"

Write-LogHost "=== Orquestração Sandbox Hyper-V ==="
Write-LogHost "Amostra: $SamplePath"
Write-LogHost "Hash SHA256: $sampleSha256"
Write-LogHost "Relatório: $ReportOutputPath"
Write-LogHost ""

# Credenciais para PowerShell Direct (evita popup e melhora diagnóstico)
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

# Tempo máximo para aguardar relatório (cópia guest->host via PsDirect)
$analysisOverheadSeconds = 1500
$sampleWindowSeconds = if ($WaitForSampleExit) { 7200 } else { $TimeoutSeconds }
$reportTimeoutSeconds = $sampleWindowSeconds + $analysisOverheadSeconds
$detachedAnalysisPid = 0
$reportReceived = $false
$reportSha256 = ""
$reportHashVerified = $false
Write-LogHost "[2/7] Relatório: cópia guest->host via PsDirect (timeout ${reportTimeoutSeconds}s)"
