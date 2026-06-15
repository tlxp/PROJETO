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

# Limpar jobs de pipe orfaos, VM ligada e COM1 residual antes de preparar este run
Clear-SandboxPipeEnvironment -VMName $VMName -LogPath $HostLogPath
Write-LogHost "[1/7] Ambiente de pipes limpo (jobs orfaos / VM / COM1)"

if ($vmObj.Generation -ge 2) {
    Write-LogWarning "      VM '$VMName' e Gen$($vmObj.Generation): COM1->Named Pipe costuma não funcionar (use VM Gen1 / PROJETOVM_VMGeneration=1, ou relatório so por Guest Service)."
    Add-LogLine -Path $HostLogPath -Value "WARNING: Gen$($vmObj.Generation) VM -- serial pipe transport often unavailable"
}

Write-LogHost "=== Orquestração Sandbox Hyper-V ==="
Write-LogHost "Amostra: $SamplePath"
Write-LogHost "Hash SHA256: $sampleSha256"
Write-LogHost "Relatório: $ReportOutputPath"
Write-LogHost ""

# Credenciais para PowerShell Direct (evita popup e melhora diagnóstico)
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

# 1) Nome do pipe único por run (evita conflitos)
$RunPipeName = ($PipeName + "_" + $RunId) -replace "[^A-Za-z0-9_\-\.]", "_"
Add-LogLine -Path $HostLogPath -Value "Pipe name: $RunPipeName"

# 2) Preparar pipe do run (o job receptor arranca em PhaseD, quando a VM já está pronta)
$modulePath = Join-Path $SandboxRoot "SandboxCommon.psm1"
# Teto do pipe: tempo da amostra + ~25 min de overhead (baseline/after/diff/COM1).
$analysisOverheadSeconds = 1500
$sampleWindowSeconds = if ($WaitForSampleExit) { 7200 } else { $TimeoutSeconds }
$pipeTimeoutSeconds = $sampleWindowSeconds + $analysisOverheadSeconds
$pipeIdleReconnectSeconds = if ($script:PROJETOVM_PipeIdleReconnectSec -gt 0) {
    [int]$script:PROJETOVM_PipeIdleReconnectSec
} else { 900 }
$pipeJob = $null
$detachedAnalysisPid = 0
Write-LogHost "[2/7] Pipe do relatório: \\.\pipe\$RunPipeName (receptor arranca antes do lançamento da análise)"
