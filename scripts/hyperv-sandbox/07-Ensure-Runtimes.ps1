# --- Script: 07-Ensure-Runtimes.ps1 ---
<#
.SYNOPSIS
    Garante runtimes essenciais na VM (offline/sem internet).
.DESCRIPTION
    Script a correr NO HOST. Fluxo:
      1) Deteta/obtém instaladores no host (por ordem):
         - scripts/hyperv-sandbox/offline/runtimes/
         - -SourceDir (se fornecido)
         - C:\ProgramData\Package Cache (quando existir)
      2) Copia para uma pasta "partilhável" no host: D:\PROJETOVM\Shared\Installers
      3) Copia para a VM: C:\analysis_work\installers
      4) Instala silenciosamente dentro da VM (PowerShell Direct)

    Nota:
      - Por padrão, pode fazer download dos instaladores (host com internet) para a pasta offline do repo.
      - Se não houver internet, mantém o modo offline e indica quais faltam.
.PARAMETER SourceDir
    Pasta no host onde colocaste manualmente os instaladores (.exe).
.PARAMETER AutoDownload
    Se faltarem instaladores, tenta fazer download automático (links oficiais Microsoft) para `offline/runtimes/`.
.PARAMETER DownloadTimeoutSeconds
    Timeout por download (segundos).
.PARAMETER SkipDotNet48
    Não instalar .NET Framework 4.8.
.PARAMETER SkipDotNetDesktop
    Não instalar .NET Desktop Runtime 8.
.EXAMPLE
    .\07-Ensure-Runtimes.ps1 -SourceDir "D:\Installers"
#>
#Requires -RunAsAdministrator

param(
    [string] $SourceDir = "",
    [switch] $AutoDownload,
    [int] $DownloadTimeoutSeconds = 60,
    [switch] $SkipDotNet48,
    [switch] $SkipDotNetDesktop
)

$ErrorActionPreference = "Stop"

# --- Inicialização de módulos e configuração ---
try { Remove-Module SandboxCommon -ErrorAction SilentlyContinue } catch {}
Import-Module (Join-Path $PSScriptRoot "SandboxCommon.psm1") -Force -DisableNameChecking -ErrorAction Stop

$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName        = $script:PROJETOVM_VMName
$SnapshotName  = $script:PROJETOVM_SnapshotName
$BasePath      = $script:PROJETOVM_BasePath
$GuestUser     = $script:PROJETOVM_GuestUser
$GuestPassword = $script:PROJETOVM_GuestPassword

# --- Preparação de pastas no host ---
$SharedDir = Join-Path $BasePath "Shared\Installers"
Ensure-DirectoryExists -Path $SharedDir

$OfflineDir = Join-Path $PSScriptRoot "offline\runtimes"
Ensure-DirectoryExists -Path $OfflineDir

# --- Biblioteca auxiliar (host) ---
# *Funções de download e localização de instaladores, carregadas no mesmo scope.*
$EnsureRuntimesLibDir = Join-Path $PSScriptRoot 'EnsureRuntimes'
foreach ($lib in @('Downloads.ps1', 'Installers.ps1')) {
    . (Join-Path $EnsureRuntimesLibDir $lib)
}

# --- Fluxo por fases ---
# *Cada fase é dot-sourced no mesmo scope; a ordem replica a execução original.*
foreach ($phase in @(
    'PhaseA-Plan.ps1',
    'PhaseB-Resolve.ps1',
    'PhaseC-Boot.ps1',
    'PhaseD-CopyInstall.ps1',
    'PhaseE-Verify.ps1'
)) {
    . (Join-Path $EnsureRuntimesLibDir $phase)
}
