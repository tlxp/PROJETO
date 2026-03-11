<#
.SYNOPSIS
    Orquestração no host: restaura VM, copia amostra, executa análise, recebe relatório via pipe, restaura snapshot.
.DESCRIPTION
    Fluxo: Restore snapshot -> Start VM -> (opcional) Guest Service para Copy-VMFile ->
    Copiar sample e scripts para VM -> Iniciar listener do pipe em background ->
    Executar análise na VM (Invoke-Command ou manual) -> Esperar relatório ->
    Stop VM -> Restore snapshot -> Relatório em D:\PROJETOVM\Reports\.
.PARAMETER SamplePath
    Caminho no HOST do ficheiro .exe ou .dll a analisar.
.PARAMETER TimeoutSeconds
    Tempo máximo de execução do sample dentro da VM.
.PARAMETER BootWaitSeconds
    Tempo de espera após arranque da VM antes de copiar/executar.
.PARAMETER NoInvokeCommand
    Se definido, não usa Invoke-Command na VM; copia o sample e espera. Execução manual na VM.
#>
#Requires -RunAsAdministrator

Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -ErrorAction Stop

param(
    [Parameter(Mandatory = $true)]
    [string] $SamplePath,
    [int] $TimeoutSeconds = 120,
    [int] $BootWaitSeconds = 60,
    [switch] $NoInvokeCommand,
    [int] $GlobalTimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

$analysisStart = Get-Date

# Carregar configuração (D:\PROJETOVM)
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
$BasePath = $script:PROJETOVM_BasePath
$VMName = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$PipeName = $script:PROJETOVM_PipeName
$ReportsDir = $script:PROJETOVM_ReportsPath
$VMScriptsPath = "C:\analysis_work"

if (-not (Test-Path $SamplePath)) {
    Write-Error "Amostra não encontrada: $SamplePath"
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

$sampleHash = Get-FileHash -Path $SamplePath -Algorithm SHA256
$sampleSha256 = $sampleHash.Hash

$sampleFileName = [System.IO.Path]::GetFileName($SamplePath)
$VMSamplePath = "C:\analysis_work\$sampleFileName"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportOutputPath = Join-Path $ReportsDir "analysis_$timestamp.txt"

Ensure-DirectoryExists -Path $ReportsDir

# Logging básico do host
$LogsDir = $script:PROJETOVM_LogsPath
Ensure-DirectoryExists -Path $LogsDir
$HostLogPath = Join-Path $LogsDir "sandbox_run_$timestamp.log"
$HostJsonPath = Join-Path $LogsDir "run_$timestamp.json"
Add-Content -Path $HostLogPath -Value "==== Sandbox Run $timestamp ===="
Add-Content -Path $HostLogPath -Value "Sample: $SamplePath"
Add-Content -Path $HostLogPath -Value "Sample SHA256: $sampleSha256"
Add-Content -Path $HostLogPath -Value "VM: $VMName  Snapshot: $SnapshotName"
Add-Content -Path $HostLogPath -Value "Report: $ReportOutputPath"

Write-Host "=== Orquestração Sandbox Hyper-V ==="
Write-Host "Amostra: $SamplePath"
Write-Host "Hash SHA256: $sampleSha256"
Write-Host "Relatório: $ReportOutputPath"
Write-Host ""

# 1) Restaurar snapshot limpo
Write-Host "[1/7] A restaurar snapshot '$SnapshotName'..."
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-Host "      Snapshot restaurado."

# 2) Arrancar VM
Write-Host "[2/7] A arrancar a VM..."
Start-SandboxVM -VMName $VMName -BootWaitSeconds $BootWaitSeconds

# 3) Ativar Guest Service para Copy-VMFile (e opcionalmente Invoke-Command)
Write-Host "[3/7] A ativar Guest Service para transferência..."
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
Start-Sleep -Seconds 5

# 4) Copiar amostra para a VM
Write-Host "[4/7] A copiar amostra para a VM..."
$destDir = "C:\analysis_work"
Copy-VMFile -VMName $VMName -SourcePath $SamplePath -DestinationPath $VMSamplePath -CreateFullPath -FileSource Host -ErrorAction Stop
# Copiar scripts de análise para a VM
$scriptDir = Join-Path $PSScriptRoot "vm"
$runScript = Join-Path $scriptDir "Run-MalwareAnalysis.ps1"
$sendScript = Join-Path $scriptDir "Send-ReportViaCom.ps1"
if (Test-Path $runScript) {
    Copy-VMFile -VMName $VMName -SourcePath $runScript -DestinationPath "$VMScriptsPath\Run-MalwareAnalysis.ps1" -CreateFullPath -FileSource Host -ErrorAction SilentlyContinue
}
if (Test-Path $sendScript) {
    Copy-VMFile -VMName $VMName -SourcePath $sendScript -DestinationPath "$VMScriptsPath\Send-ReportViaCom.ps1" -CreateFullPath -FileSource Host -ErrorAction SilentlyContinue
}
Write-Host "      Amostra e scripts copiados."

# 5) Iniciar listener do pipe em background
Write-Host "[5/7] A iniciar receptor do relatório (Named Pipe)..."
$modulePath = Join-Path $PSScriptRoot "SandboxCommon.psm1"
$pipeJob = Start-Job -ScriptBlock {
    param($PipeName, $OutputPath, $TimeoutSeconds, $ModulePath)
    Import-Module $ModulePath -ErrorAction Stop
    return (Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath -TimeoutSeconds ($TimeoutSeconds + 60))
} -ArgumentList $PipeName, $ReportOutputPath, $TimeoutSeconds, $modulePath

# 6) Executar análise na VM
Write-Host "[6/7] A executar análise na VM..."
if (-not $NoInvokeCommand) {
    try {
        Invoke-Command -VMName $VMName -ScriptBlock {
            param($SamplePath, $TimeoutSec, $ScriptPath, $SampleSha256)
            Set-Location $ScriptPath
            & ".\Run-MalwareAnalysis.ps1" -SamplePath $SamplePath -TimeoutSeconds $TimeoutSec -SampleHash $SampleSha256
        } -ArgumentList $VMSamplePath, $TimeoutSeconds, $VMScriptsPath, $sampleSha256 -ErrorAction Stop
    }
    catch {
        Write-Warning "Invoke-Command falhou (a VM pode não suportar Direct VM Connection). Execute manualmente na VM: Run-MalwareAnalysis.ps1 -SamplePath '$VMSamplePath' -TimeoutSeconds $TimeoutSeconds"
        Write-Host "      À espera do relatório via pipe ($($TimeoutSeconds + 30) s)..."
        $null = Wait-Job $pipeJob -Timeout ($TimeoutSeconds + 60)
    }
} else {
    Write-Host "      Modo manual: execute na VM: .\Run-MalwareAnalysis.ps1 -SamplePath '$VMSamplePath' -TimeoutSeconds $TimeoutSeconds"
    Write-Host "      À espera do relatório via pipe..."
    $null = Wait-Job $pipeJob -Timeout ($TimeoutSeconds + 120)
}

# Esperar que o job do pipe termine (respeitando timeout global)
$elapsed = [int]([DateTime]::UtcNow - $analysisStart.ToUniversalTime()).TotalSeconds
$remainingGlobal = $GlobalTimeoutSeconds - $elapsed
if ($remainingGlobal -lt 0) { $remainingGlobal = 0 }
$waitSec = [Math]::Min($TimeoutSeconds + 90, $remainingGlobal)
if ($waitSec -gt 0) {
    $null = Wait-Job $pipeJob -Timeout $waitSec
}
$pipeResult = Receive-Job $pipeJob
Remove-Job $pipeJob -Force -ErrorAction SilentlyContinue
Add-Content -Path $HostLogPath -Value "Pipe lines received: $pipeResult"
if (Test-Path $ReportOutputPath) {
    Write-Host "      Relatório recebido: $ReportOutputPath"
    Add-Content -Path $HostLogPath -Value "Report received successfully."
} else {
    Write-Warning "      Relatório não recebido no tempo esperado. Verifique se na VM o script enviou via COM1."
    Add-Content -Path $HostLogPath -Value "Report NOT received within expected time."
}

# 7) Parar VM e restaurar snapshot
Write-Host "[7/7] A parar a VM e a restaurar snapshot..."
Stop-SandboxVM -VMName $VMName
Start-Sleep -Seconds 5
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-Host "      VM restaurada ao estado limpo."

Add-Content -Path $HostLogPath -Value "VM stopped and snapshot restored."

# Desativar Guest Service Interface após a execução para reduzir superfície de ataque
try {
    Disable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue
    Add-Content -Path $HostLogPath -Value "Guest Service Interface disabled after run."
} catch {
    Add-Content -Path $HostLogPath -Value "Failed to disable Guest Service Interface: $_"
}

# JSON estruturado do run
$analysisEnd = Get-Date
$status = if (Test-Path $ReportOutputPath) { "ok" } else { "failed" }
$jsonData = @{
    sample_path    = $SamplePath
    sample_sha256  = $sampleSha256
    vm_name        = $VMName
    snapshot       = $SnapshotName
    analysis_start = $analysisStart
    analysis_end   = $analysisEnd
    report_path    = $ReportOutputPath
    report_lines   = $pipeResult
    status         = $status
}
try {
    $jsonData | ConvertTo-Json -Depth 4 | Set-Content -Path $HostJsonPath -Encoding UTF8
} catch { }

Write-Host ""
Write-Host "Concluído. Relatório: $ReportOutputPath"
