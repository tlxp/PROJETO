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
    Reservado (o arranque usa espera por PowerShell Direct com credenciais do _Config.ps1, sem sleep fixo).
.PARAMETER NoInvokeCommand
    Se definido, não usa Invoke-Command na VM; copia o sample e espera. Execução manual na VM.
#>
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string]$SamplePath,
    [string]$RunId,
    [int]$TimeoutSeconds = 120,
    [int]$BootWaitSeconds = 60,
    [switch]$NoInvokeCommand,
    [int]$GlobalTimeoutSeconds = 300
)

Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -ErrorAction Stop

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
$GuestUser = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword

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
function Add-LogLine { param([string]$Path, [string]$Value) Add-Content -Path $Path -Value "[$(Get-Date -Format 'HH:mm:ss')] $Value" }
Add-LogLine -Path $HostLogPath -Value "==== Sandbox Run $RunId ===="
Add-LogLine -Path $HostLogPath -Value "Sample: $SamplePath"
Add-LogLine -Path $HostLogPath -Value "Sample SHA256: $sampleSha256"
Add-LogLine -Path $HostLogPath -Value "VM: $VMName  Snapshot: $SnapshotName"
Add-LogLine -Path $HostLogPath -Value "Report: $ReportOutputPath"
Add-LogLine -Path $HostLogPath -Value "RunDir: $RunDir"

Write-LogHost "=== Orquestração Sandbox Hyper-V ==="
Write-LogHost "Amostra: $SamplePath"
Write-LogHost "Hash SHA256: $sampleSha256"
Write-LogHost "Relatório: $ReportOutputPath"
Write-LogHost ""

# Credenciais para PowerShell Direct (evita popup e melhora diagnóstico)
$secure = ConvertTo-SecureString $GuestPassword -AsPlainText -Force
$cred = [pscredential]::new($GuestUser, $secure)

# 1) Restaurar snapshot limpo
Write-LogHost "[1/7] A restaurar snapshot '$SnapshotName'..."
Stop-SandboxVM -VMName $VMName
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      Snapshot restaurado."

# 1.5) Pipe único por run (evita erro 'instâncias ocupadas' em execuções repetidas)
$RunPipeName = ($PipeName + "_" + $RunId) -replace "[^A-Za-z0-9_\-\.]", "_"
try {
    Set-VMComPort -VMName $VMName -Number 1 -Path "\\.\pipe\$RunPipeName"
    Add-LogLine -Path $HostLogPath -Value "COM1 pipe set to: \\.\pipe\$RunPipeName"
} catch {
    Add-LogLine -Path $HostLogPath -Value "Failed to set VM COM1 pipe: $_"
}

# 2) Arrancar VM (espera pelo arranque = PowerShell Direct, sem sleep fixo)
Write-LogHost "[2/7] A arrancar a VM..."
Start-SandboxVM -VMName $VMName -Credential $cred -PowerShellDirectTimeoutSeconds 0 -LogPath $HostLogPath

# 3) Ativar Guest Service para Copy-VMFile (e opcionalmente Invoke-Command)
Write-LogHost "[3/7] A ativar Guest Service para transferência..."
Enable-SandboxGuestService -VMName $VMName
$null = Wait-SandboxGuestServiceReady -VMName $VMName -TimeoutSeconds 120

# 4) Copiar amostra para a VM
Write-LogHost "[4/7] A copiar amostra para a VM..."
Copy-SandboxVMFile -VMName $VMName -SourcePath $SamplePath -DestinationPath $VMSamplePath
# Copiar scripts de análise para a VM
$scriptDir = Join-Path $PSScriptRoot "vm"
$runScript = Join-Path $scriptDir "Run-MalwareAnalysis.ps1"
$sendScript = Join-Path $scriptDir "Send-ReportViaCom.ps1"
if (Test-Path $runScript) {
    try { Copy-SandboxVMFile -VMName $VMName -SourcePath $runScript -DestinationPath "$VMScriptsPath\Run-MalwareAnalysis.ps1" } catch { }
}
if (Test-Path $sendScript) {
    try { Copy-SandboxVMFile -VMName $VMName -SourcePath $sendScript -DestinationPath "$VMScriptsPath\Send-ReportViaCom.ps1" } catch { }
}
Write-LogHost "      Amostra e scripts copiados."

# 5) Iniciar listener do pipe em background
Write-LogHost "[5/7] A iniciar receptor do relatório (Named Pipe)..."
$modulePath = Join-Path $PSScriptRoot "SandboxCommon.psm1"
$pipeJob = Start-Job -ScriptBlock {
    param($PipeName, $OutputPath, $TimeoutSeconds, $ModulePath)
    Import-Module $ModulePath -ErrorAction Stop
    return (Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath -TimeoutSeconds ($TimeoutSeconds + 60))
} -ArgumentList $RunPipeName, $ReportOutputPath, $TimeoutSeconds, $modulePath

# 6) Executar análise na VM
Write-LogHost "[6/7] A executar análise na VM..."
if (-not $NoInvokeCommand) {
    try {
        # PSDirect já foi validado em Start-SandboxVM ao aguardar o arranque
        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($SamplePath, $TimeoutSec, $ScriptPath, $SampleSha256)
            Set-Location $ScriptPath
            & ".\Run-MalwareAnalysis.ps1" -SamplePath $SamplePath -TimeoutSeconds $TimeoutSec -SampleHash $SampleSha256
        } -ArgumentList $VMSamplePath, $TimeoutSeconds, $VMScriptsPath, $sampleSha256 -ErrorAction Stop
    }
    catch {
        Write-LogWarning "Invoke-Command falhou: $($_.Exception.Message)"
        Write-LogWarning "Execute manualmente na VM: Run-MalwareAnalysis.ps1 -SamplePath '$VMSamplePath' -TimeoutSeconds $TimeoutSeconds"
        Write-LogHost "      À espera do relatório via pipe ($($TimeoutSeconds + 30) s)..."
        $null = Wait-Job $pipeJob -Timeout ($TimeoutSeconds + 60)
    }
} else {
    Write-LogHost "      Modo manual: execute na VM: .\Run-MalwareAnalysis.ps1 -SamplePath '$VMSamplePath' -TimeoutSeconds $TimeoutSeconds"
    Write-LogHost "      À espera do relatório via pipe..."
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
Add-LogLine -Path $HostLogPath -Value "Pipe lines received: $pipeResult"
if (Test-Path $ReportOutputPath) {
    Write-LogHost "      Relatório recebido: $ReportOutputPath"
    Add-LogLine -Path $HostLogPath -Value "Report received successfully."
} else {
    Write-LogWarning "      Relatório não recebido no tempo esperado. Verifique se na VM o script enviou via COM1."
    Add-LogLine -Path $HostLogPath -Value "Report NOT received within expected time."
}

# 7) Parar VM e restaurar snapshot
Write-LogHost "[7/7] A parar a VM e a restaurar snapshot..."
Stop-SandboxVM -VMName $VMName
Start-Sleep -Seconds 5
Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      VM restaurada ao estado limpo."

Add-LogLine -Path $HostLogPath -Value "VM stopped and snapshot restored."

# Desativar Guest Service Interface após a execução para reduzir superfície de ataque
try {
    Disable-SandboxGuestService -VMName $VMName
    Add-LogLine -Path $HostLogPath -Value "Guest Service Interface disabled after run."
} catch {
    Add-LogLine -Path $HostLogPath -Value "Failed to disable Guest Service Interface: $_"
}

# JSON estruturado do run
$analysisEnd = Get-Date
$status = if (Test-Path $ReportOutputPath) { "ok" } else { "failed" }
$jsonData = @{
    run_id         = $RunId
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

Write-LogHost ""
Write-LogHost "Concluído. Relatório: $ReportOutputPath"
