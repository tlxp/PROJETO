<#
.SYNOPSIS
    Primeira entrada na VM: valida PowerShell Direct, instala Sysmon, garante isolamento
    de rede (sem adaptadores externos) e guarda snapshot CleanState.
.DESCRIPTION
    A correr NO HOST. Fluxo:

      [1/5] Parar VM (estado limpo)
      [2/5] Arrancar VM + aguardar PowerShell Direct
      [3/5] Garantir isolamento: remover adaptadores em switches não-Internal
      [4/5] Runtimes offline + Sysmon (telemetria primária)
      [5/5] Parar VM, criar/atualizar snapshot CleanState

    Guest Services permanecem desactivados; transferências via PowerShell Direct.

    O snapshot final contém:
      - SEM qualquer adaptador externo -- só SandboxSwitch (Internal)
      - Sysmon activo (serviço + canal de eventos)
      - Garantia de isolamento total da internet
.EXAMPLE
    .\05-FirstTimeVmSetup.ps1
#>
#Requires -RunAsAdministrator

param(
    # Evita ficar preso indefinidamente se a VM não aceitar logon (credenciais erradas / OOBE / autounattend não aplicado)
    [int]    $PowerShellDirectTimeoutSeconds = 1200,

    # Staging seguro do WinUtil dentro da VM (NÃO executa automaticamente).
    # Útil para instalar software manualmente antes do snapshot, sem debloat/remover componentes.
    [switch] $StageWinutil
)

$ErrorActionPreference = "Stop"

$scriptRoot   = $PSScriptRoot
$configScript = Join-Path $scriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName          = $script:PROJETOVM_VMName
$SnapshotName    = $script:PROJETOVM_SnapshotName
$SandboxSwitch   = $script:PROJETOVM_SwitchName
$VMScriptsPath   = "C:\analysis_work"
$GuestUser       = $script:PROJETOVM_GuestUser
$GuestPassword   = $script:PROJETOVM_GuestPassword
$PsDirectTimeoutSeconds = if ($script:PROJETOVM_PowerShellDirectTimeoutSeconds -gt 0) {
    $script:PROJETOVM_PowerShellDirectTimeoutSeconds
} else { 240 }

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $scriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

# Funções auxiliares (host)
# Extraídas para .\FirstTimeVmSetup\ e carregadas via dot-sourcing (mesmo scope).
$FirstTimeLibDir = Join-Path $scriptRoot 'FirstTimeVmSetup'
. (Join-Path $FirstTimeLibDir 'Helpers.ps1')

# Fluxo por fases
# Cada fase é um fragmento procedural dot-sourced no MESMO scope deste script.
# A ordem replica exatamente a execução original [1/5]..[5/5].
foreach ($phase in @(
    'PhaseA-PreCheck.ps1',
    'PhaseB-Boot.ps1',
    'PhaseD-Isolation.ps1',
    'PhaseE-Runtimes.ps1',
    'PhaseE2-Sysmon.ps1',
    'PhaseF-Snapshot.ps1',
    'PhaseG-Summary.ps1'
)) {
    . (Join-Path $FirstTimeLibDir $phase)
}
