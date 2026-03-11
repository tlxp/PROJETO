<#
.SYNOPSIS
    Servidor no host que recebe o relatório da VM via Named Pipe (porta serial virtual).
.DESCRIPTION
    Abre o pipe \\.\pipe\SandboxReportPipe e grava as linhas recebidas em D:\PROJETOVM\Reports\.
    Deve ser executado antes ou em paralelo com a análise na VM (ex.: por 04-Run-Sample.ps1).
.PARAMETER PipeName
    Nome do pipe (deve coincidir com Set-VMComPort no setup).
.PARAMETER OutputPath
    Ficheiro .txt onde gravar o relatório. Se não indicado, usa D:\PROJETOVM\Reports\analysis_<timestamp>.txt
.PARAMETER TimeoutSeconds
    Tempo máximo à espera da primeira ligação e entre leituras.
.EXAMPLE
    .\02-Host-ReceiveReport.ps1 -OutputPath "D:\PROJETOVM\Reports\analysis_001.txt"
#>

Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -ErrorAction Stop

param(
    [string] $PipeName = "",
    [string] $OutputPath = "",
    [int]    $TimeoutSeconds = 600
)

# Carregar configuração (D:\PROJETOVM)
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
if ([string]::IsNullOrWhiteSpace($PipeName)) { $PipeName = $script:PROJETOVM_PipeName }
$ReportsDir = $script:PROJETOVM_ReportsPath
Ensure-DirectoryExists -Path $ReportsDir

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $ReportsDir "analysis_$timestamp.txt"
}

Write-Host "Aguardando relatório da VM no pipe: $PipeName"
Write-Host "Ficheiro de saída: $OutputPath"
Write-Host "Timeout: $TimeoutSeconds s"

try {
    $linesCount = Receive-SandboxReportFromPipe -PipeName $PipeName -OutputPath $OutputPath -TimeoutSeconds $TimeoutSeconds
    Write-Host "Relatório guardado: $OutputPath ($linesCount linhas)"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
