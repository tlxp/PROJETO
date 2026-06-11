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

Add-LogLine -Path $HostLogPath -Value "==== Sandbox Run $RunId ===="
Add-LogLine -Path $HostLogPath -Value "Sample: $SamplePath"
Add-LogLine -Path $HostLogPath -Value "Sample SHA256: $sampleSha256"
Add-LogLine -Path $HostLogPath -Value "VM: $VMName  Snapshot: $SnapshotName"
Add-LogLine -Path $HostLogPath -Value "Report: $ReportOutputPath"
Add-LogLine -Path $HostLogPath -Value "RunDir: $RunDir"
Add-LogLine -Path $HostLogPath -Value "Network preflight OK: VM adapters only on Internal switch '$expectedSwitch'"
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

# 2) Iniciar receptor do pipe EM PARALELO com a restauração do snapshot
# O servidor do pipe é criado pelo vmwp.exe quando a VM arranca; o receptor
# liga-se como CLIENTE (com retry até a VM subir). Tem de estar ligado antes
# do guest escrever no COM1 — bytes enviados sem cliente ligado são descartados.
Write-LogHost "[2/7] A iniciar receptor do relatório (Named Pipe) em background..."
$modulePath = Join-Path $SandboxRoot "SandboxCommon.psm1"
# Com o envio simplificado (linha-a-linha) a transmissão pode demorar bastante.
# Dar margem generosa para evitar timeouts prematuros.
$pipeTimeoutSeconds = $TimeoutSeconds + 900

$pipeJob = Start-Job -ScriptBlock {
    param($PipeName, $OutputPath, $TimeoutSecondsLocal, $ModulePath)
    Write-Host "[PIPE] Job worker arrancou pid=$PID utc=$([DateTime]::UtcNow.ToString('o'))"
    Import-Module $ModulePath -DisableNameChecking -ErrorAction Stop
    return (Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath -TimeoutSeconds $TimeoutSecondsLocal)
} -ArgumentList $RunPipeName, $ReportOutputPath, $pipeTimeoutSeconds, $modulePath

Add-LogLine -Path $HostLogPath -Value "Pipe job started: Id=$($pipeJob.Id) Name=$($pipeJob.Name) path=\\.\pipe\$RunPipeName timeout=${pipeTimeoutSeconds}s"
Write-LogHost "      [PIPE-HOST] Job receptor id=$($pipeJob.Id) pipe=\\.\pipe\$RunPipeName (logs [PIPE] vêm do job)"
# Margem para o job arrancar e o pipe ficar genuinamente em escuta antes do restore/arranque da VM.
Start-Sleep -Seconds 2
Write-LogHost "      Receptor do relatório iniciado (background)."
