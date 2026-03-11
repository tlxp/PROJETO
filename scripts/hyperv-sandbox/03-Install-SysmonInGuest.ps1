<#
.SYNOPSIS
    Instala Sysmon dentro da VM MalwareSandbox e prepara-a para captura de eventos.
.DESCRIPTION
    A correr NO HOST, depois do Windows já estar instalado na VM.

    Fluxo:
      - Garante que a VM existe.
      - Arranca a VM e espera pelo boot.
      - Ativa temporariamente o Guest Service Interface.
      - Copia Sysmon e o ficheiro de configuração para C:\tools\sysmon na VM.
      - Executa Sysmon com -accepteula -i <config> dentro da VM.

    Após este passo, recomenda-se desligar a VM e atualizar o snapshot limpo
    (CleanState) para que futuras análises usem sempre uma imagem com Sysmon ativo.

.PARAMETER SysmonExePath
    Caminho, NO HOST, para o binário Sysmon 64-bit (ex.: D:\Tools\Sysmon\Sysmon64.exe).

.PARAMETER SysmonConfigPath
    Caminho, NO HOST, para o ficheiro de configuração XML do Sysmon.

.PARAMETER BootWaitSeconds
    Tempo de espera após arrancar a VM para garantir que o Windows está pronto.

.EXAMPLE
    .\03-Install-SysmonInGuest.ps1 `
        -SysmonExePath "D:\Tools\Sysmon\Sysmon64.exe" `
        -SysmonConfigPath "D:\Tools\Sysmon\sysmon-config.xml"
#>
#Requires -RunAsAdministrator

param(
    [Parameter(Mandatory = $true)]
    [string] $SysmonExePath,

    [Parameter(Mandatory = $true)]
    [string] $SysmonConfigPath,

    [int] $BootWaitSeconds = 60
)

$ErrorActionPreference = "Stop"

# Carregar configuração (D:\PROJETOVM)
$configScript = Join-Path $PSScriptRoot "_Config.ps1"
if (Test-Path $configScript) { . $configScript }

$VMName = $script:PROJETOVM_VMName

if (-not (Test-Path $SysmonExePath)) {
    throw "SysmonExePath não encontrado: $SysmonExePath"
}
if (-not (Test-Path $SysmonConfigPath)) {
    throw "SysmonConfigPath não encontrado: $SysmonConfigPath"
}

$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    throw "VM '$VMName' não encontrada. Execute primeiro 01-Setup-MalwareSandbox.ps1 e instale o Windows na VM."
}

Write-Host "=== Instalação do Sysmon na VM '$VMName' ==="
Write-Host "Binário Sysmon (host): $SysmonExePath"
Write-Host "Configuração (host):   $SysmonConfigPath"
Write-Host ""

# 1) Ligar VM (se ainda não estiver ligada)
if ($vm.State -ne "Running") {
    Write-Host "[1/5] A arrancar a VM..."
    Start-VM -Name $VMName | Out-Null
} else {
    Write-Host "[1/5] VM já se encontra ligada."
}

Write-Host "      A aguardar $BootWaitSeconds s pelo arranque do Windows..."
Start-Sleep -Seconds $BootWaitSeconds

# 2) Ativar Guest Service Interface para Copy-VMFile / Invoke-Command
Write-Host "[2/5] A ativar Guest Service Interface na VM..."
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue | Out-Null
Start-Sleep -Seconds 5

# 3) Copiar Sysmon e configuração para a VM
Write-Host "[3/5] A copiar Sysmon para a VM..."
$guestSysmonDir   = "C:\tools\sysmon"
$guestSysmonExe   = Join-Path $guestSysmonDir "Sysmon64.exe"
$guestSysmonConfig = Join-Path $guestSysmonDir "sysmon-config.xml"

Copy-VMFile -VMName $VMName -SourcePath $SysmonExePath -DestinationPath $guestSysmonExe -FileSource Host -CreateFullPath -ErrorAction Stop
Copy-VMFile -VMName $VMName -SourcePath $SysmonConfigPath -DestinationPath $guestSysmonConfig -FileSource Host -CreateFullPath -ErrorAction Stop
Write-Host "      Sysmon e configuração copiados para $guestSysmonDir."

# 4) Instalar Sysmon dentro da VM
Write-Host "[4/5] A instalar Sysmon dentro da VM..."
try {
    Invoke-Command -VMName $VMName -ScriptBlock {
        param($exePath, $configPath)
        if (-not (Test-Path $exePath)) {
            throw "Sysmon não encontrado dentro da VM em: $exePath"
        }
        if (-not (Test-Path $configPath)) {
            throw "Configuração Sysmon não encontrada dentro da VM em: $configPath"
        }

        Write-Host "    [VM] A instalar Sysmon com configuração: $configPath"
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exePath
        $psi.Arguments = "-accepteula -i `"$configPath`""
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $null = $proc.WaitForExit(600000)  # até 10 minutos
        Write-Host "    [VM] Sysmon terminou com ExitCode $($proc.ExitCode)."
    } -ArgumentList $guestSysmonExe, $guestSysmonConfig -ErrorAction Stop
}
catch {
    Write-Warning "Falha ao instalar Sysmon dentro da VM: $_"
    Write-Warning "Verifique se a versão do Windows na VM suporta PowerShell Direct / Invoke-Command."
    throw
}

Write-Host "[5/5] Sysmon instalado na VM (serviço Sysmon deve estar ativo)."
Write-Host ""
Write-Host "Recomendação:"
Write-Host "  1. Desligue a VM para capturar um novo snapshot limpo com Sysmon:"
Write-Host "       Stop-VM -Name $VMName -Force"
Write-Host "  2. Crie/atualize o snapshot CleanState (ou o nome definido em _Config.ps1):"
Write-Host "       Checkpoint-VM -Name $VMName -SnapshotName $($script:PROJETOVM_SnapshotName)"
Write-Host ""
Write-Host "Após este passo, as próximas análises comportamentais já terão Sysmon ativo na imagem base."

