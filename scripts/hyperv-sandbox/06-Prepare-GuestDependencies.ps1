<#
.SYNOPSIS
    Prepara dependências OFFLINE para análises futuras (sem internet durante execução de samples).
.DESCRIPTION
    A correr NO HOST. Fluxo:
      - Restaura a VM para snapshot limpo (CleanState)
      - Adiciona TEMPORARIAMENTE um adaptador de rede ligado a um switch com internet (por defeito: "Default Switch")
      - Arranca a VM e aguarda PowerShell Direct
      - Dentro da VM: descarrega instaladores (VC++ Redist x64/x86) para C:\analysis_work\deps
      - Copia os instaladores da VM para o projeto (scripts\hyperv-sandbox\tools\) via Guest Services (Copy-VMFile)
      - Remove o adaptador temporário e volta ao isolamento
      - (Opcional) atualiza o snapshot CleanState no fim

    Resultado:
      - Ficheiros offline ficam versionados/localizados no projeto para que 04-Run-Sample.ps1
        consiga instalar dependências (best-effort) sem internet.

.PARAMETER InternetSwitchName
    Nome do VMSwitch no host que dá acesso à internet. Por defeito "Default Switch".
.PARAMETER UpdateCleanSnapshot
    Se definido, cria/atualiza o snapshot CleanState depois de remover o adaptador temporário.
.PARAMETER ForceRedownload
    Se definido, força redownload dentro da VM mesmo que os ficheiros já existam.
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [string] $InternetSwitchName = "Default Switch",

    [Parameter()]
    [switch] $UpdateCleanSnapshot,

    [Parameter()]
    [switch] $ForceRedownload,

    [Parameter()]
    [switch] $StageWinutil
    ,
    [Parameter()]
    [ValidateRange(0, 900)]
    [int] $ConnectivityTimeoutSeconds = 90
    ,
    [Parameter()]
    [switch] $HostOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

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


# Funções auxiliares (host)
# Extraídas para .\PrepareGuestDependencies\ e carregadas via dot-sourcing (mesmo scope).
$PrepDepsLibDir = Join-Path $PSScriptRoot 'PrepareGuestDependencies'
. (Join-Path $PrepDepsLibDir 'Helpers.ps1')
Write-LogHost "=== Preparar dependências offline (via internet temporária) ==="
Write-LogHost "VM: $VMName | Snapshot: $SnapshotName | Internet switch: $InternetSwitchName"
Write-LogHost "Destino no projeto: $HostToolsDir"
Write-LogHost ""

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { throw "VM '$VMName' não encontrada." }

$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

Ensure-DirectoryExists -Path $HostToolsDir


# Fluxo principal (try/finally)
# O corpo do try está dividido em fragmentos dot-sourced (Flow1/Flow2) que correm
# no MESMO scope; o try/finally fica aqui para garantir o cleanup de isolamento.
try {
    . (Join-Path $PrepDepsLibDir 'Flow1-Download.ps1')
    . (Join-Path $PrepDepsLibDir 'Flow2-Stage.ps1')
}
finally {
    try {
        # Garantir isolamento mesmo em erro
        if (-not $HostOnly) {
            Stop-SandboxVM -VMName $VMName
            Remove-InternetAdapterIfAny -VMName $VMName
        }
    } catch { }
}
