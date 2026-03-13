<#
.SYNOPSIS
    Primeira entrada na VM: instala software comum (winget), para a VM e cria snapshot limpo.
.DESCRIPTION
    A correr NO HOST. Arranca a VM, ativa Guest Service, copia Prepare-RealisticEnvironment.ps1
    para a VM, executa-o com -InstallCommonSoftware (winget), para a VM e cria/atualiza
    o snapshot CleanState. Toda a saída é Write-Host para streaming em tempo real.
.PARAMETER BootWaitSeconds
    Tempo de espera após arranque da VM antes de copiar/executar.
.EXAMPLE
    .\05-FirstTimeVmSetup.ps1
#>
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$scriptRoot = $PSScriptRoot
$configScript = Join-Path $scriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$VMScriptsPath = "C:\analysis_work"

Import-Module (Join-Path $scriptRoot "SandboxCommon.psm1") -ErrorAction Stop

Write-LogHost "=== Primeira entrada na VM: instalar software comum e criar snapshot ==="
Write-LogHost ""

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-LogHost "[ERRO] VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1 e instale o Windows na VM."
    exit 1
}

# 1) Se a VM estiver ligada, parar para começar do estado limpo
if ($vm.State -eq "Running") {
    Write-LogHost "[1/6] A parar a VM..."
    Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
} else {
    Write-LogHost "[1/6] VM já está desligada."
}

# 2) Arrancar VM
Write-LogHost "[2/6] A arrancar a VM..."
Start-VM -Name $VMName | Out-Null
$bootWait = 90
Write-LogHost "      A aguardar $bootWait s pelo arranque do Windows..."
Start-Sleep -Seconds $bootWait

# 3) Ativar Guest Service
Write-LogHost "[3/6] A ativar Guest Service Interface..."
Enable-SandboxGuestService -VMName $VMName
Start-Sleep -Seconds 5

# 4) Copiar Prepare-RealisticEnvironment.ps1 para a VM e executar com -InstallCommonSoftware
$prepareScript = Join-Path $scriptRoot "vm\Prepare-RealisticEnvironment.ps1"
if (-not (Test-Path $prepareScript)) {
    Write-LogHost "[ERRO] Script não encontrado: $prepareScript"
    exit 1
}

$guestPath = "$VMScriptsPath\Prepare-RealisticEnvironment.ps1"
Write-LogHost "[4/6] A copiar Prepare-RealisticEnvironment.ps1 para a VM..."
Copy-SandboxVMFile -VMName $VMName -SourcePath $prepareScript -DestinationPath $guestPath
Write-LogHost "      A executar na VM: Prepare-RealisticEnvironment.ps1 -InstallCommonSoftware (winget)..."
try {
    Invoke-Command -VMName $VMName -ScriptBlock {
        param($Path)
        if (Test-Path $Path) {
            & $Path -InstallCommonSoftware
        } else {
            Write-Error "Ficheiro não encontrado na VM: $Path"
        }
    } -ArgumentList $guestPath -ErrorAction Stop
} catch {
    Write-LogHost "      [AVISO] Invoke-Command falhou: $_"
    Write-LogHost "      Se a VM não suportar PowerShell Direct, execute manualmente na VM:"
    Write-LogHost "        cd C:\analysis_work; .\Prepare-RealisticEnvironment.ps1 -InstallCommonSoftware"
    Write-LogHost "      Depois pare a VM e execute este script novamente para criar o snapshot."
}

# 5) Parar a VM
Write-LogHost "[5/6] A parar a VM..."
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 8

# 6) Criar ou atualizar snapshot CleanState
Write-LogHost "[6/6] A criar/atualizar snapshot '$SnapshotName'..."
$existing = Get-VMSnapshot -VMName $VMName -Name $SnapshotName -ErrorAction SilentlyContinue
if ($existing) {
    Remove-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}
Checkpoint-VM -VMName $VMName -SnapshotName $SnapshotName
Write-LogHost "      Snapshot '$SnapshotName' criado."

# Desativar Guest Service
Disable-SandboxGuestService -VMName $VMName

Write-LogHost ""
Write-LogHost "=== Primeira entrada concluída. Pode agora usar 04-Run-Sample.ps1 para analisar amostras. ==="
