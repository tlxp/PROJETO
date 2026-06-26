# --- Módulo: 00-Reset-Sandbox.ps1 ---
# --- Remove VM, pastas e estado do sandbox Hyper-V ---
<#
.SYNOPSIS
    Limpa completamente o ambiente PROJETOVM (VM + pasta D:\PROJETOVM).
.DESCRIPTION
    - Verifica se a pasta base (por defeito D:\PROJETOVM) existe.
    - Pede CONFIRMAÇÃO explícita antes de apagar.
    - Para e remove a VM de sandbox (se existir).
    - Remove a pasta inteira (Reports, Samples, Logs, VM, etc.).
    USE COM CUIDADO: esta operação é destrutiva.
.EXAMPLE
    .\00-Reset-Sandbox.ps1
#>

#Requires -RunAsAdministrator

Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -ErrorAction Stop

$ErrorActionPreference = "Stop"

# --- Carregamento da configuração ---
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$BasePath = $script:PROJETOVM_BasePath
$VMName   = $script:PROJETOVM_VMName

Write-Host "=== Reset completo do ambiente de sandbox Hyper-V ==="
Write-Host "BasePath configurado: $BasePath"
Write-Host "VM configurada:       $VMName"
Write-Host ""

# --- Verificação prévia ---
if (-not (Test-Path $BasePath)) {
    Write-Host "A pasta '$BasePath' não existe. Nada para limpar."
    return
}

Write-Host "A pasta '$BasePath' já existe. Isto pode conter:"
Write-Host "  - VM\ (ficheiro VHDX, configuração da VM)"
Write-Host "  - Reports\, Samples\, Logs\"
Write-Host ""

# Confirmação explícita antes de apagar tudo
$answer = Read-Host "Tem a CERTEZA que quer parar/remover a VM '$VMName' (se existir) e APAGAR TUDO em '$BasePath'? (escreva 'SIM' para confirmar)"
if ($answer -ne "SIM") {
    Write-Host "Operação cancelada pelo utilizador. Nada foi alterado."
    return
}

# --- Remoção da VM Hyper-V ---
Write-Host ""
Write-Host "A parar e remover VM (se existir)..."
try {
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if ($vm) {
        if ($vm.State -ne "Off") {
            Write-Host "  - A parar VM '$VMName'..."
            Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 5
        }
        Write-Host "  - A remover VM '$VMName'..."
        Remove-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  - VM '$VMName' não encontrada (ignorado)."
    }
} catch {
    Write-Warning "Falha ao remover a VM '$VMName': $($_.Exception.Message)"
}

# --- Limpeza da pasta base ---
Write-Host ""
Write-Host "A apagar conteúdo da pasta '$BasePath'..."
try {
    # Remove tudo por baixo da pasta base, mantendo a drive
    Get-ChildItem -LiteralPath $BasePath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "  - Não foi possível apagar '$($_.FullName)': $($_.Exception.Message)"
        }
    }
    Write-Host "Limpeza concluída. '$BasePath' está vazio ou contém apenas itens que não puderam ser removidos."
} catch {
    Write-Warning "Erro ao limpar '$BasePath': $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Reset do ambiente de sandbox concluído."

