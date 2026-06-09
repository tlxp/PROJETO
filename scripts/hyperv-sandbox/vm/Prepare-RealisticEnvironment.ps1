<#
.SYNOPSIS
    Corre DENTRO da VM. Prepara um ambiente "realista" para análise (sem instalar aplicações).
.DESCRIPTION
    Este script:
      - aplica ajustes de sistema (Windows Update, SmartScreen, UAC, energia)
      - cria pasta de trabalho e ficheiros "isca"
      - grava um estado simples em JSON + uma flag de pronto

    Nota: nenhuma lógica de instalação (winget/offline/downloads) é executada aqui.

.PARAMETER WorkDir
    Diretório de trabalho na VM. Predefinição: C:\analysis_work
#>
param(
    [string] $WorkDir = "C:\analysis_work"
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

# Auxiliares
function LogMsg {
    param([string]$msg, [string]$level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts][$level] $msg"
}

function LogWarn  { param([string]$m) LogMsg $m "WARN"  }
function LogError { param([string]$m) LogMsg $m "ERROR" }

# Garantir pasta de trabalho
if (-not (Test-Path $WorkDir)) {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
}

$StateJsonPath = Join-Path $WorkDir "prepare_env_state.json"
$ReadyFlagPath = Join-Path $WorkDir "prepare_env_ready.flag"

# Limpar ficheiros de estado anteriores
Remove-Item -LiteralPath $StateJsonPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $ReadyFlagPath -Force -ErrorAction SilentlyContinue

# 1) Preparar ambiente "realista"
LogMsg "=== Prepare-RealisticEnvironment ==="
LogMsg "[1] A configurar ambiente realista..."

# Desativar Windows Update automático (evita que o sample seja perturbado por atualizações)
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoUpdate" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    LogMsg "  Windows Update automático desactivado."
} catch {
    LogWarn "  Não foi possível desactivar Windows Update: $($_.Exception.Message)"
}

# Desativar hibernação e ecrã de bloqueio (VM deve ficar ativa durante análise)
try {
    powercfg /hibernate off 2>&1 | Out-Null
    powercfg /change standby-timeout-ac 0 2>&1 | Out-Null
    powercfg /change monitor-timeout-ac 0 2>&1 | Out-Null
    LogMsg "  Hibernação/standby desactivados."
} catch {
    LogWarn "  Não foi possível configurar power: $($_.Exception.Message)"
}

# Desativar SmartScreen para não bloquear samples
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" `
        -Name "SmartScreenEnabled" -Value "Off" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" `
        -Name "EnableSmartScreen" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    LogMsg "  SmartScreen desactivado."
} catch {
    LogWarn "  Não foi possível desactivar SmartScreen: $($_.Exception.Message)"
}

# Desativar UAC (facilita a execução de samples como admin)
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "EnableLUA" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    LogMsg "  UAC desactivado."
} catch {
    LogWarn "  Não foi possível desactivar UAC: $($_.Exception.Message)"
}

$analysisDir = $WorkDir

# Criar documentos "isca" para o ambiente parecer usado
$decoyDocs = @(
    @{ Path = "$env:USERPROFILE\Documents\relatorio_q3_2024.txt"; Content = "Relatorio Q3 2024`nTotal vendas: 1.250.000 EUR`nMargem: 18,3%" },
    @{ Path = "$env:USERPROFILE\Documents\passwords_backup.txt";  Content = "# Notas pessoais - NÃO PARTILHAR`nEmail: analyst@empresa.pt`nVPN: changeme123" },
    @{ Path = "$env:USERPROFILE\Desktop\notas.txt";               Content = "Reunião amanhã às 10h. Ver email do João sobre contrato." }
)

foreach ($doc in $decoyDocs) {
    try {
        $dir = Split-Path $doc.Path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $doc.Path -Value $doc.Content -Encoding UTF8 -Force
    } catch {
        LogWarn "  Não foi possível criar ficheiro isca: $($doc.Path)"
    }
}
LogMsg "  Ficheiros isca criados."

# 2) Gravar estado final
LogMsg "[2] A gravar estado final..."

$state = @{
    ok         = $true
    timestamp            = (Get-Date -Format "o")
    hostname             = $env:COMPUTERNAME
    user                 = $env:USERNAME
    workDir              = $WorkDir
}

$state | ConvertTo-Json -Depth 6 | Set-Content -Path $StateJsonPath -Encoding UTF8
LogMsg "  Estado gravado: $StateJsonPath"

Set-Content -Path $ReadyFlagPath -Value "ready" -Encoding UTF8
LogMsg "  Flag de pronto criada: $ReadyFlagPath"

LogMsg ""
LogMsg "=== Prepare-RealisticEnvironment concluído. ok=true ==="