# --- Script: 06-Prepare-GuestDependencies.ps1 ---
<#
.SYNOPSIS
    Prepara dependências OFFLINE para análises futuras (sem internet na VM).
.DESCRIPTION
    A correr NO HOST. Fluxo:
      - Restaura a VM para snapshot limpo (CleanState)
      - Arranca a VM **isolada** (sem adaptador temporário com internet)
      - Descarrega instaladores no HOST para scripts\hyperv-sandbox\tools\
      - Copia os ficheiros para a VM via Guest Services (Copy-VMFile)
      - Revalida isolamento de rede e remove adaptadores TemporaryInternet órfãos
      - (Opcional) atualiza o snapshot CleanState no fim

    Resultado:
      - Ficheiros offline no projeto para que 04-Run-Sample.ps1 instale dependências
        (best-effort) sem expor a VM à internet.

.PARAMETER UpdateCleanSnapshot
    Se definido, cria/atualiza o snapshot CleanState depois de revalidar o isolamento.
.PARAMETER ForceRedownload
    Se definido, força redownload no host mesmo que os ficheiros já existam.
.PARAMETER HostOnly
    Apenas descarrega no host (sem operações na VM).
#>
#Requires -RunAsAdministrator

# --- Parâmetros de entrada ---
[CmdletBinding()]
param(
    [Parameter()]
    [switch] $UpdateCleanSnapshot,

    [Parameter()]
    [switch] $ForceRedownload,

    [Parameter()]
    [switch] $StageWinutil,

    [Parameter()]
    [switch] $HostOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- Importação de módulos e configuração ---
try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

# --- Variáveis de ambiente da sandbox ---
$VMName        = $script:PROJETOVM_VMName
$SnapshotName  = $script:PROJETOVM_SnapshotName
$GuestUser     = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword
$VmWorkDir     = "C:\analysis_work"
$VmDepsDir     = Join-Path $VmWorkDir "deps"
$HostToolsDir  = Join-Path $PSScriptRoot "tools"
$HostWinutilPath = Join-Path $HostToolsDir "winutil.ps1"
$DepsManifestPath = Join-Path $HostToolsDir "deps_manifest.json"
$PsDirectTimeoutSeconds = if ($script:PROJETOVM_PowerShellDirectTimeoutSeconds -gt 0) {
    $script:PROJETOVM_PowerShellDirectTimeoutSeconds
} else { 240 }

# --- Carregar biblioteca auxiliar e validar VM ---
$PrepDepsLibDir = Join-Path $PSScriptRoot 'PrepareGuestDependencies'
. (Join-Path $PrepDepsLibDir 'Helpers.ps1')
Write-LogHost "=== Preparar dependências offline (downloads só no host) ==="
Write-LogHost "VM: $VMName | Snapshot: $SnapshotName | Switch: $($script:PROJETOVM_SwitchName)"
Write-LogHost "Destino no projeto: $HostToolsDir"
Write-LogHost ""

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' não encontrada." }

# *Credenciais candidatas para PowerShell Direct e Copy-VMFile*
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

Ensure-DirectoryExists -Path $HostToolsDir

# --- Execução do fluxo (Flow1 + Flow2) com cleanup garantido ---
try {
    . (Join-Path $PrepDepsLibDir 'Flow1-Download.ps1')
    . (Join-Path $PrepDepsLibDir 'Flow2-Stage.ps1')
}
finally {
    # *Garante paragem da VM e remoção de adaptadores mesmo em caso de erro*
    try {
        if (-not $HostOnly) {
            Stop-SandboxVM -VMName $VMName -ErrorAction SilentlyContinue
            Remove-InternetAdapterIfAny -VMName $VMName
        }
    } catch { }
}
