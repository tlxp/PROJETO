<#
.SYNOPSIS
    Orquestração no host: restaura VM, copia amostra, executa análise, recebe relatório via pipe, restaura snapshot.
.DESCRIPTION
    Fluxo: Restore snapshot -> Start VM -> (opcional) Guest Service para Copy-VMFile ->
    Copiar sample e scripts para VM -> Iniciar listener do pipe em background ->
    Executar análise na VM (Invoke-Command ou manual) -> Esperar relatório ->
    Stop VM -> Restore snapshot -> Relatório em D:\PROJETOVM\Reports\.
.PARAMETER SamplePath
    Caminho no HOST do ficheiro .exe ou .dll a analisar.
    Se omitido, o script escolhe automaticamente o ficheiro mais recente em D:\PROJETOVM\Samples\.
.PARAMETER TimeoutSeconds
    Tempo máximo de execução do sample dentro da VM.
.PARAMETER BootWaitSeconds
    Reservado (o arranque usa espera por PowerShell Direct com credenciais do _Config.ps1, sem sleep fixo).
#>
#Requires -RunAsAdministrator

param(
    [string]$SamplePath = "",
    [string]$RunId,
    [int]$TimeoutSeconds = 120,
    [int]$BootWaitSeconds = 60,
    [int]$GlobalTimeoutSeconds = 600
)

try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$ErrorActionPreference = "Stop"

$analysisStart = Get-Date

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }
$BasePath = $script:PROJETOVM_BasePath
$VMName = $script:PROJETOVM_VMName
$SnapshotName = $script:PROJETOVM_SnapshotName
$PipeName = $script:PROJETOVM_PipeName
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


# Funções auxiliares (host)
# Extraídas para .\RunSample\ e carregadas via dot-sourcing (mesmo scope deste
# script). Têm de existir junto a este script (mesmo $PSScriptRoot).
$RunSampleLibDir = Join-Path $PSScriptRoot 'RunSample'
foreach ($lib in @('SampleResolve.ps1', 'ReportCheck.ps1', 'VmInvoke.ps1')) {
    . (Join-Path $RunSampleLibDir $lib)
}

# Fluxo de orquestração por fases
# Cada fase é um fragmento procedural dot-sourced no MESMO scope deste script,
# por isso todas as variáveis ($pipeJob, $cred, $RunPipeName, ...) fluem entre
# fases tal como no ficheiro único. A ordem replica exatamente a execução original.
foreach ($phase in @(
    'PhaseA-Setup.ps1',
    'PhaseB-VmBoot.ps1',
    'PhaseC-CopyPreflight.ps1',
    'PhaseD-Execute.ps1',
    'PhaseE-WaitReport.ps1',
    'PhaseF-CollectResult.ps1',
    'PhaseG-Finish.ps1'
)) {
    . (Join-Path $RunSampleLibDir $phase)
}
