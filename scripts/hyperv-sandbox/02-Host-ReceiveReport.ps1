# --- Módulo: 02-Host-ReceiveReport.ps1 ---
# --- Receptor no host do relatório via named pipe/COM1 ---
<#
.SYNOPSIS
    Servidor no host que recebe o relatório da VM via Named Pipe (porta serial virtual).
#>

param(
    [string] $PipeName = "",
    [string] $OutputPath = "",
    [int]    $TimeoutSeconds = 600,
    [switch] $Verbose
)

Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -ErrorAction Stop

# --- Configuração inicial e caminhos de saída ---
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
if ([string]::IsNullOrWhiteSpace($PipeName)) { $PipeName = $script:PROJETOVM_PipeName }
$ReportsDir = $script:PROJETOVM_ReportsPath
Ensure-DirectoryExists -Path $ReportsDir

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $ReportsDir "analysis_$timestamp.txt"
}

Write-Host "========================================"
Write-Host "RECEPTOR DE RELATÓRIO VIA COM1 (Melhorado)"
Write-Host "========================================"
Write-Host "Pipe: $PipeName"
Write-Host "Output: $OutputPath"
Write-Host "Timeout: $TimeoutSeconds s"
Write-Host ""

$logFile = $OutputPath -replace "\.txt$", "_receive.log"

# --- Registo de eventos da recepção ---
function Write-ReceiveLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp][$Level] $Message"
    Write-Host $logLine
    Add-Content -Path $logFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
}

# --- Recepção do relatório via Named Pipe ---
$startTime = Get-Date
try {
    Write-ReceiveLog "A iniciar servidor Named Pipe: $PipeName"
    # Bloqueia até receber todas as linhas ou expirar o timeout
    $receivedLines = Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath -TimeoutSeconds $TimeoutSeconds

    $duration = [int]((Get-Date) - $startTime).TotalSeconds
    Write-ReceiveLog ""
    Write-ReceiveLog "========================================"
    Write-ReceiveLog "RELATÓRIO RECEBIDO COM SUCESSO!"
    Write-ReceiveLog "========================================"
    Write-ReceiveLog "Output: $OutputPath"
    Write-ReceiveLog "Linhas: $receivedLines"
    Write-ReceiveLog "Duração: ${duration}s"
    exit 0
} catch {
    Write-ReceiveLog "ERRO FATAL: $_" "ERROR"
    exit 1
}
