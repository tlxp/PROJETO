# --- Módulo: 03-Install-SysmonInGuest.ps1 ---
# --- Instala Sysmon na VM e actualiza snapshot CleanState ---
<#
.SYNOPSIS
    Instala Sysmon dentro da VM MalwareSandbox e actualiza o snapshot CleanState.
.DESCRIPTION
    A correr NO HOST, depois do Windows já estar instalado na VM.

    Fluxo:
      - Arranca a VM (se necessário) e espera PowerShell Direct.
      - Copia Sysmon via PowerShell Direct (Guest Services permanecem desactivados).
      - Instala Sysmon com configuração dentro da VM.
      - Para a VM e actualiza o snapshot CleanState (por defeito).

    Também é executado automaticamente durante o 05-FirstTimeVmSetup.ps1.

.PARAMETER SysmonExePath
    Caminho, NO HOST, para o binário Sysmon 64-bit (ex.: D:\Tools\Sysmon\Sysmon64.exe).

.PARAMETER SysmonConfigPath
    Caminho, NO HOST, para o ficheiro de configuração XML do Sysmon.

.PARAMETER UpdateCleanSnapshot
    Se definido (por defeito), para a VM e recria o snapshot CleanState após instalação.

.PARAMETER SkipIfAlreadyInstalled
    Ignora a instalação se Sysmon já estiver operacional na VM.

.EXAMPLE
    .\03-Install-SysmonInGuest.ps1
.EXAMPLE
    .\03-Install-SysmonInGuest.ps1 -UpdateCleanSnapshot:$false
#>
#Requires -RunAsAdministrator

# --- Ponto de entrada: Sysmon na VM e snapshot limpo ---
# Instala Sysmon na VM sandbox e actualiza snapshot CleanState.

param(
    [string] $SysmonExePath = "",
    [string] $SysmonConfigPath = "",
    [switch] $UpdateCleanSnapshot = $true,
    [switch] $SkipIfAlreadyInstalled
)

$ErrorActionPreference = "Stop"

# --- Importação de módulos e configuração ---
try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

# Variáveis da VM sandbox definidas em _Config.ps1
$VMName       = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$GuestUser    = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword

# --- Carregamento das funções de instalação Sysmon ---
$InstallSysmonLibDir = Join-Path $PSScriptRoot 'InstallSysmon'
. (Join-Path $InstallSysmonLibDir 'SysmonResolve.ps1')
. (Join-Path $InstallSysmonLibDir 'Install-SysmonInGuestCore.ps1')

# --- Validação: VM sandbox existe ---
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    throw "VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1 e instale o Windows na VM."
}

Write-Host "=== Instalação do Sysmon na VM '$VMName' ==="
Write-Host "Guest Services: desactivados (cópia via PowerShell Direct)."
Write-Host ""

# Credenciais do convidado para PowerShell Direct
$credCandidates = New-SandboxCredentialCandidates -UserName $GuestUser -Password $GuestPassword -ComputerName $VMName
$cred = $credCandidates | Select-Object -First 1

# --- Arranque da VM e espera por PowerShell Direct ---
if ($vm.State -ne "Running") {
    Write-Host "[1/4] A arrancar a VM..."
    $psOk = Start-SandboxVM -VMName $VMName -CredentialCandidates $credCandidates -PowerShellDirectTimeoutSeconds 0
    if ($psOk -is [pscredential]) { $cred = $psOk }
} else {
    Write-Host "[1/4] VM já se encontra ligada."
}

Write-Host "      A aguardar PowerShell Direct (verificação a cada 10s, sem timeout)..."
$psOk2 = Wait-VMPowerShellDirectReady -VMName $VMName -CredentialCandidates $credCandidates -TimeoutSeconds 0 -LogPath $null -LogIntervalSeconds 10
if ($psOk2 -is [pscredential]) { $cred = $psOk2 }

# --- Instalação do Sysmon na VM ---
Write-Host "[2/4] A instalar Sysmon na VM..."
Install-SysmonInSandboxGuest -VMName $VMName -Credential $cred `
    -SysmonExePath $SysmonExePath -SysmonConfigPath $SysmonConfigPath `
    -SkipIfAlreadyInstalled:$SkipIfAlreadyInstalled

Write-Host "[3/4] Sysmon operacional na VM."

# --- Actualização opcional do snapshot CleanState ---
if ($UpdateCleanSnapshot) {
    Write-Host "[4/4] A actualizar snapshot '$SnapshotName'..."
    Update-SandboxCleanSnapshot -VMName $VMName -SnapshotName $SnapshotName
    Write-Host ""
    Write-Host "Concluído. O snapshot '$SnapshotName' inclui Sysmon activo."
} else {
    Write-Host "[4/4] Snapshot não actualizado (-UpdateCleanSnapshot:`$false)."
    Write-Host ""
    Write-Host "Para persistir Sysmon no snapshot limpo:"
    Write-Host "  .\03-Install-SysmonInGuest.ps1 -UpdateCleanSnapshot"
}

Write-Host ""
Write-Host "As próximas análises comportamentais usarão Sysmon como fonte primária (ProcessGuid)."
