# --- Módulo: 04-Run-Sample.ps1 ---
# --- Orquestração host: amostra, análise, relatório, snapshot ---
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

# modo de espera: por omissão aguarda a amostra terminar; com -SampleTimeoutKill força timeout
$WaitForSampleExit = -not $SampleTimeoutKill

# --- Inicialização de módulos e preferências ---
# carrega SandboxCommon e define paragem imediata em erros
try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$ErrorActionPreference = "Stop"

$analysisStart = Get-Date

# --- Carregamento da configuração do sandbox ---
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
$BasePath = $script:PROJETOVM_BasePath
$VMName = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$ReportsDir = $script:PROJETOVM_ReportsPath
# raiz hyperv-sandbox; nas fases dot-sourced $PSScriptRoot aponta para RunSample\
$SandboxRoot = $PSScriptRoot
$VMScriptsPath = "C:\analysis_work"
$GuestUser = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword
$PsDirectTimeoutSeconds = if ($script:PROJETOVM_PowerShellDirectTimeoutSeconds -gt 0) {
    $script:PROJETOVM_PowerShellDirectTimeoutSeconds
} else { 240 }

# --- Ajuste do deadline global conforme modo de espera da amostra ---
# amostras longas ou cópia PS Direct exigem mais tempo total
if ($WaitForSampleExit) {
    $minGlobal = 8100
    if ($GlobalTimeoutSeconds -lt $minGlobal) { $GlobalTimeoutSeconds = $minGlobal }
} else {
    $minGlobal = $TimeoutSeconds + 900
    if ($GlobalTimeoutSeconds -lt $minGlobal) { $GlobalTimeoutSeconds = $minGlobal }
}

# --- Bibliotecas auxiliares (dot-sourcing) ---
# funções partilhadas carregadas no mesmo scope deste script
$RunSampleLibDir = Join-Path $PSScriptRoot 'RunSample'
foreach ($lib in @('SampleResolve.ps1', 'ReportCheck.ps1', 'VmInvoke.ps1')) {
    . (Join-Path $RunSampleLibDir $lib)
}

# --- Limpeza de emergência ---
# garante paragem da VM e restauro do snapshot se o run abortar a meio
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

# --- Orquestração por fases ---
# cada fase é dot-sourced no mesmo scope; fases E–G ignoram o deadline global
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
    # só faz cleanup de emergência se PhaseG não marcou conclusão normal
    if (-not $script:SandboxRunCleanupDone) {
        $vm = if ($VMName) { Get-VM -Name $VMName -ErrorAction SilentlyContinue } else { $null }
        if ($vm -and $vm.State -eq 'Running') {
            Invoke-SandboxRunEmergencyCleanup
        }
    }
}
