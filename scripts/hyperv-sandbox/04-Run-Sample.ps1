<#
.SYNOPSIS
    Orquestração no host: restaura VM, copia amostra, executa análise, recolhe relatório via PsDirect, restaura snapshot.
.DESCRIPTION
    Fluxo: Restore snapshot -> Start VM -> transferência via PowerShell Direct ->
    Copiar sample e scripts para VM -> Executar análise na VM ->
    Copiar relatório guest->host com verificação SHA256 -> Stop VM -> Restore snapshot.
    Stop VM -> Restore snapshot -> Relatório em D:\PROJETOVM\Reports\.
.PARAMETER SamplePath
    Caminho no HOST do ficheiro .exe ou .dll a analisar.
    Se omitido, o script escolhe automaticamente o ficheiro mais recente em D:\PROJETOVM\Samples\.
.PARAMETER TimeoutSeconds
    Tempo máximo de execução do sample dentro da VM (usado com -SampleTimeoutKill).
.PARAMETER SampleTimeoutKill
    Se presente, mantém a amostra ativa até TimeoutSeconds e mata se ainda estiver a correr.
    Por omissão (switch ausente), aguarda a amostra terminar naturalmente (limite de segurança 7200s na VM).
.PARAMETER BootWaitSeconds
    Reservado (o arranque usa espera por PowerShell Direct com credenciais do _Config.ps1, sem sleep fixo).
#>
#Requires -RunAsAdministrator

param(
    [string]$SamplePath = "",
    [string]$RunId,
    [int]$TimeoutSeconds = 120,
    [switch]$SampleTimeoutKill,
    [int]$BootWaitSeconds = 60,
    [int]$GlobalTimeoutSeconds = 900,
    [switch]$AllowAutoSample
)

$WaitForSampleExit = -not $SampleTimeoutKill

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$ErrorActionPreference = "Stop"

$analysisStart = Get-Date

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
$BasePath = $script:PROJETOVM_BasePath
$VMName = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$ReportsDir = $script:PROJETOVM_ReportsPath
# Raiz da pasta hyperv-sandbox. As fases são dot-sourced a partir de .\RunSample\,
# por isso DENTRO delas $PSScriptRoot aponta para ...\RunSample (e não para esta raiz).
# Guardamos a raiz aqui para que as fases possam localizar SandboxCommon.psm1 e .\vm\.
$SandboxRoot = $PSScriptRoot
$VMScriptsPath = "C:\analysis_work"
$GuestUser = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword
$PsDirectTimeoutSeconds = if ($script:PROJETOVM_PowerShellDirectTimeoutSeconds -gt 0) {
    $script:PROJETOVM_PowerShellDirectTimeoutSeconds
} else { 240 }

# Estender deadline global quando a amostra pode correr muito tempo.
if ($WaitForSampleExit) {
    $minGlobal = 8100
    if ($GlobalTimeoutSeconds -lt $minGlobal) { $GlobalTimeoutSeconds = $minGlobal }
} else {
    $minGlobal = $TimeoutSeconds + 900
    if ($GlobalTimeoutSeconds -lt $minGlobal) { $GlobalTimeoutSeconds = $minGlobal }
}

# Funções auxiliares (host)
# Extraídas para .\RunSample\ e carregadas via dot-sourcing (mesmo scope deste
# script). Têm de existir junto a este script (mesmo $PSScriptRoot).
$RunSampleLibDir = Join-Path $PSScriptRoot 'RunSample'
foreach ($lib in @('SampleResolve.ps1', 'ReportCheck.ps1', 'VmInvoke.ps1')) {
    . (Join-Path $RunSampleLibDir $lib)
}

# Fluxo de orquestração por fases
# Cada fase é um fragmento procedural dot-sourced no MESMO scope deste script.
$script:SandboxRunCleanupDone = $false
function Invoke-SandboxRunEmergencyCleanup {
    if ($script:SandboxRunCleanupDone) { return }
    $script:SandboxRunCleanupDone = $true
    Write-Warning "[CLEANUP] A executar limpeza de emergência do run sandbox..."
    try {
        if ($VMName) { Stop-SandboxVM -VMName $VMName -ErrorAction SilentlyContinue }
    } catch {
        Write-Warning "[CLEANUP] Falha ao parar VM: $_"
    }
    try {
        if ($VMName -and $SnapshotName) {
            Restore-SandboxSnapshot -VMName $VMName -SnapshotName $SnapshotName -ErrorAction Stop
        }
    } catch {
        Write-Warning "[CLEANUP] Falha ao restaurar snapshot: $_"
    }
    try {
        if ($VMName -and $script:PROJETOVM_UseGuestServices) {
            Disable-SandboxGuestService -VMName $VMName -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "[CLEANUP] Falha ao desativar Guest Service: $_"
    }
}

try {
    $globalDeadline = if ($GlobalTimeoutSeconds -gt 0) { $analysisStart.AddSeconds($GlobalTimeoutSeconds) } else { $null }
    $phasesSkipGlobalDeadline = @(
        'PhaseE-WaitReport.ps1',
        'PhaseF-CollectResult.ps1',
        'PhaseG-Finish.ps1'
    )
    foreach ($phase in @(
        'PhaseA-Setup.ps1',
        'PhaseB-VmBoot.ps1',
        'PhaseC-CopyPreflight.ps1',
        'PhaseD-Execute.ps1',
        'PhaseE-WaitReport.ps1',
        'PhaseF-CollectResult.ps1',
        'PhaseG-Finish.ps1'
    )) {
        if ($globalDeadline -and (Get-Date) -gt $globalDeadline -and ($phasesSkipGlobalDeadline -notcontains $phase)) {
            throw "Timeout global do run ($GlobalTimeoutSeconds s) excedido antes de $phase"
        }
        . (Join-Path $RunSampleLibDir $phase)
    }
} finally {
    if (-not $script:SandboxRunCleanupDone) {
        # PhaseG marca conclusão normal; só fazemos emergency cleanup se ainda não terminou.
        $vm = if ($VMName) { Get-VM -Name $VMName -ErrorAction SilentlyContinue } else { $null }
        if ($vm -and $vm.State -eq 'Running') {
            Invoke-SandboxRunEmergencyCleanup
        }
    }
}
